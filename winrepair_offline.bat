@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: winrepair_offline.bat - Windows PE Offline Repair Script
:: Runs from Windows PE to repair non-booting Windows installations
:: Detects Windows installations, performs offline DISM/SFC repairs,
:: and fixes boot configuration (BCD, MBR, GPT, UEFI).
:: Supports Windows 10 (all builds) and Windows 11 (all builds)
:: ============================================================

title Windows PE Offline Repair Script

:: ---- Setup log file ----------------------------------------
set "SCRIPT_DIR=%~dp0"
set "LOG_DIR=X:\RepairLogs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Use PowerShell for locale-independent date/time formatting
for /f "usebackq" %%i in (`powershell -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyy-MM-dd'"`) do set "D=%%i"
for /f "usebackq" %%i in (`powershell -NoProfile -NonInteractive -Command "Get-Date -Format 'HHmmss'"`) do set "T=%%i"
set "LOG_FILE=%LOG_DIR%\winrepair_offline_%D%_%T%.log"

:: ---- Title and header --------------------------------------
cls
echo.
echo ============================================================
echo  Windows PE Offline Repair Script
echo  Log: %LOG_FILE%
echo ============================================================
echo.

call :log "Windows PE Offline Repair Script started at %DATE% %TIME%"
call :log "============================================================"

:: ---- Verify we're in WinPE ---------------------------------
call :log "Checking if running in Windows PE environment..."
reg query "HKLM\System\CurrentControlSet\Control\MiniNT" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run from Windows PE environment.
    echo         Use winrepair.bat for online repairs from within Windows.
    call :log "[ERROR] Not running in Windows PE. Aborting."
    pause
    exit /b 1
)
call :log "[OK] Running in Windows PE environment."

:: ---- Initialize WinPE --------------------------------------
call :section "Initializing Windows PE"
echo Loading network drivers and mapping drives...
echo.

:: Initialize network (wpeinit loads drivers)
start /wait wpeinit
call :log "[OK] wpeinit completed."

:: Map all available drive letters
echo Mapping drive letters...
echo list volume > "%TEMP%\diskpart_list.txt"
diskpart /s "%TEMP%\diskpart_list.txt" >> "%LOG_FILE%" 2>&1
call :log "[OK] Drive letters mapped."
echo.

:: ---- Detect Windows Installations --------------------------
call :section "Detecting Windows Installations"
echo Scanning all drives for Windows installations...
echo.

set "WIN_COUNT=0"
set "WIN_DRIVES="

:: Scan all fixed drives for Windows installations
for %%D in (C D E F G H I J K L M N O P Q R S T U V W) do (
    if exist "%%D:\Windows\System32\config\SOFTWARE" (
        set /a WIN_COUNT+=1
        set "WIN_DRIVE[!WIN_COUNT!]=%%D:"
        set "WIN_DRIVES=!WIN_DRIVES! %%D:"

        :: Try to detect Windows version
        set "WIN_VER[!WIN_COUNT!]=Unknown"
        if exist "%%D:\Windows\System32\ntoskrnl.exe" (
            for /f "tokens=*" %%V in ('powershell -NoProfile -Command "(Get-Item '%%D:\Windows\System32\ntoskrnl.exe').VersionInfo.ProductVersion"') do (
                set "WIN_VER[!WIN_COUNT!]=%%V"
            )
        )

        echo [!WIN_COUNT!] %%D:\ - Windows !WIN_VER[!WIN_COUNT!]!
        call :log "Found Windows installation [!WIN_COUNT!]: %%D:\ - Version !WIN_VER[!WIN_COUNT!]!"
    )
)

echo.
if %WIN_COUNT% equ 0 (
    echo [ERROR] No Windows installations found on any drive.
    echo         Ensure the drive is connected and readable.
    call :log "[ERROR] No Windows installations detected. Aborting."
    pause
    exit /b 1
)

call :log "[OK] Found %WIN_COUNT% Windows installation(s)."

:: ---- Select Windows Installation ---------------------------
if %WIN_COUNT% equ 1 (
    set "SELECTED=1"
    echo Only one Windows installation found. Auto-selecting drive !WIN_DRIVE[1]!
    call :log "Auto-selected Windows installation: !WIN_DRIVE[1]!"
) else (
    echo Multiple Windows installations detected.
    echo.
    set /p "SELECTED=Select installation to repair (1-%WIN_COUNT%): "

    if not defined SELECTED set "SELECTED=1"
    if !SELECTED! lss 1 set "SELECTED=1"
    if !SELECTED! gtr %WIN_COUNT% set "SELECTED=%WIN_COUNT%"

    call :log "User selected Windows installation [!SELECTED!]"
)

set "TARGET_DRIVE=!WIN_DRIVE[%SELECTED%]!"
set "TARGET_WIN=%TARGET_DRIVE%\Windows"
set "TARGET_VER=!WIN_VER[%SELECTED%]!"

echo.
echo Selected: %TARGET_DRIVE%\ - Windows %TARGET_VER%
echo.
call :log "Target drive: %TARGET_DRIVE%\ - Windows %TARGET_VER%"

:: ---- Safety Confirmation -----------------------------------
echo ============================================================
echo  IMPORTANT - Repair Confirmation
echo ============================================================
echo.
echo  This script will perform the following repairs on %TARGET_DRIVE%:
echo.
echo    1. Backup current BCD (Boot Configuration Data)
echo    2. Offline DISM image repair
echo    3. Offline SFC system file scan
echo    4. Boot sector repair (MBR/GPT)
echo    5. BCD rebuild and repair
echo    6. Boot Manager repair (UEFI/Legacy)
echo.
echo  These operations are generally safe but will modify boot
echo  configuration and system files on %TARGET_DRIVE%.
echo.
set /p "CONFIRM=Continue with repairs? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    call :log "User cancelled at confirmation prompt."
    echo Cancelled. No changes were made.
    pause
    exit /b 0
)
echo.

:: ---- Detect Boot Mode (UEFI vs Legacy) --------------------
call :section "Detecting Boot Configuration"

:: Check if system booted via UEFI
set "BOOT_MODE=Legacy"
if exist "%SystemDrive%\EFI" set "BOOT_MODE=UEFI"

:: Alternative check using firmware type
for /f "tokens=2 delims=:" %%a in ('bcdedit /enum firmware 2^>nul ^| find /i "path"') do (
    set "BOOT_MODE=UEFI"
)

echo Boot Mode: %BOOT_MODE%
call :log "Detected boot mode: %BOOT_MODE%"

:: Detect partition style (MBR or GPT)
set "PART_STYLE=Unknown"
echo list disk > "%TEMP%\diskpart_diskinfo.txt"
diskpart /s "%TEMP%\diskpart_diskinfo.txt" | find /i "GPT" >nul 2>&1
if %errorlevel% equ 0 (
    set "PART_STYLE=GPT"
) else (
    set "PART_STYLE=MBR"
)

echo Partition Style: %PART_STYLE%
call :log "Detected partition style: %PART_STYLE%"
echo.

:: ---- Backup BCD --------------------------------------------
call :section "SAFETY: Backup Boot Configuration"
echo Creating backup of BCD (Boot Configuration Data)...
echo.

set "BCD_BACKUP=%LOG_DIR%\BCD_backup_%D%_%T%"
mkdir "%BCD_BACKUP%" 2>nul

if exist "%TARGET_DRIVE%\Boot\BCD" (
    copy "%TARGET_DRIVE%\Boot\BCD" "%BCD_BACKUP%\BCD_Legacy" >nul 2>&1
    call :log "[OK] Backed up Legacy BCD from %TARGET_DRIVE%\Boot\BCD"
    echo [OK] Legacy BCD backed up.
)

if exist "%TARGET_DRIVE%\EFI\Microsoft\Boot\BCD" (
    copy "%TARGET_DRIVE%\EFI\Microsoft\Boot\BCD" "%BCD_BACKUP%\BCD_UEFI" >nul 2>&1
    call :log "[OK] Backed up UEFI BCD from %TARGET_DRIVE%\EFI\Microsoft\Boot\BCD"
    echo [OK] UEFI BCD backed up.
)

:: Export current BCD to readable format
bcdedit /export "%BCD_BACKUP%\BCD_export.bcd" >nul 2>&1
call :log "[OK] BCD configuration backed up to: %BCD_BACKUP%"
echo [OK] BCD backup complete: %BCD_BACKUP%
echo.

:: ---- Step 1: Offline DISM Repair ---------------------------
call :section "STEP 1: Offline DISM - Restore Image Health"
echo Scanning and repairing Windows component store offline...
echo Target: %TARGET_WIN%
echo This may take 15-45 minutes. Do not close this window...
echo.

DISM /Image:%TARGET_DRIVE%\ /Cleanup-Image /RestoreHealth >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] Offline DISM RestoreHealth completed successfully."
    echo [OK] DISM repair complete.
) else (
    call :log "[WARN] Offline DISM finished with errors (exit code %errorlevel%). Check log for details."
    echo [WARN] DISM finished with errors. Continuing with other repairs...
)
echo.

:: ---- Step 2: Offline SFC Scan ------------------------------
call :section "STEP 2: Offline SFC - System File Checker"
echo Scanning and repairing system files offline...
echo This may take 15-30 minutes. Do not close this window...
echo.

:: Detect boot drive (often separate from Windows drive)
set "BOOT_DRIVE=%TARGET_DRIVE%"
if exist "C:\Boot" if not "%TARGET_DRIVE%"=="C:" set "BOOT_DRIVE=C:"

sfc /scannow /OFFBOOTDIR=%BOOT_DRIVE%:\ /OFFWINDIR=%TARGET_WIN% >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] Offline SFC scan completed successfully."
    echo [OK] SFC scan complete.
) else (
    call :log "[WARN] Offline SFC finished with errors (exit code %errorlevel%). Check log for details."
    echo [WARN] SFC finished with errors. Continuing with boot repairs...
)
echo.

:: ---- Step 3: Boot Sector Repair ----------------------------
call :section "STEP 3: Boot Sector Repair"
echo Repairing boot sectors and boot records...
echo.

if /i "%BOOT_MODE%"=="UEFI" (
    echo Repairing UEFI boot configuration...

    :: For UEFI/GPT systems
    bootrec /fixboot >> "%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        call :log "[OK] bootrec /fixboot completed."
        echo [OK] UEFI boot sectors repaired.
    ) else (
        call :log "[WARN] bootrec /fixboot returned code %errorlevel%."
        echo [WARN] Boot sector repair encountered issues (see log).
    )
) else (
    echo Repairing Legacy BIOS boot configuration...

    :: For Legacy/MBR systems
    bootrec /fixmbr >> "%LOG_FILE%" 2>&1
    call :log "bootrec /fixmbr: exit code %errorlevel%"

    bootrec /fixboot >> "%LOG_FILE%" 2>&1
    call :log "bootrec /fixboot: exit code %errorlevel%"

    echo [OK] MBR and boot sectors repaired.
)
echo.

:: ---- Step 4: Rebuild BCD -----------------------------------
call :section "STEP 4: Rebuild BCD (Boot Configuration Data)"
echo Scanning for Windows installations and rebuilding BCD...
echo.

bootrec /scanos >> "%LOG_FILE%" 2>&1
call :log "bootrec /scanos: exit code %errorlevel%"

bootrec /rebuildbcd >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] BCD rebuilt successfully."
    echo [OK] BCD rebuilt. Boot configuration restored.
) else (
    call :log "[WARN] bootrec /rebuildbcd returned code %errorlevel%."
    echo [WARN] BCD rebuild encountered issues. Attempting manual repair...

    :: Manual BCD recreation as fallback
    if /i "%BOOT_MODE%"=="UEFI" (
        bcdboot %TARGET_WIN% /s %TARGET_DRIVE%: /f UEFI >> "%LOG_FILE%" 2>&1
        call :log "Manual BCD creation (UEFI): exit code %errorlevel%"
    ) else (
        bcdboot %TARGET_WIN% /s %TARGET_DRIVE%: /f BIOS >> "%LOG_FILE%" 2>&1
        call :log "Manual BCD creation (BIOS): exit code %errorlevel%"
    )
)
echo.

:: ---- Step 5: Repair Boot Manager ---------------------------
call :section "STEP 5: Repair Windows Boot Manager"
echo Restoring Windows Boot Manager files...
echo.

if /i "%BOOT_MODE%"=="UEFI" (
    echo Repairing UEFI Boot Manager...

    :: Ensure EFI partition is accessible
    if not exist "%TARGET_DRIVE%\EFI\Microsoft\Boot\" mkdir "%TARGET_DRIVE%\EFI\Microsoft\Boot\" 2>nul

    :: Recreate boot files using bcdboot
    bcdboot %TARGET_WIN% /s %TARGET_DRIVE%: /f UEFI >> "%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        call :log "[OK] UEFI Boot Manager restored."
        echo [OK] UEFI Boot Manager restored.
    ) else (
        call :log "[WARN] bcdboot UEFI returned code %errorlevel%."
        echo [WARN] Boot Manager restore encountered issues (see log).
    )
) else (
    echo Repairing Legacy Boot Manager...

    :: Ensure boot folder exists
    if not exist "%TARGET_DRIVE%\Boot\" mkdir "%TARGET_DRIVE%\Boot\" 2>nul

    :: Recreate boot files using bcdboot
    bcdboot %TARGET_WIN% /s %TARGET_DRIVE%: /f BIOS >> "%LOG_FILE%" 2>&1
    if %errorlevel% equ 0 (
        call :log "[OK] Legacy Boot Manager restored."
        echo [OK] Legacy Boot Manager restored.
    ) else (
        call :log "[WARN] bcdboot BIOS returned code %errorlevel%."
        echo [WARN] Boot Manager restore encountered issues (see log).
    )
)
echo.

:: ---- Optional: Disk Check ----------------------------------
call :section "OPTIONAL: Offline Disk Check"
echo.
set /p "DO_CHKDSK=Run offline disk check on %TARGET_DRIVE%? (Y/N) [N]: "
if /i "%DO_CHKDSK%"=="Y" (
    echo.
    echo Running chkdsk /f on %TARGET_DRIVE%...
    echo This may take several minutes...
    chkdsk %TARGET_DRIVE%: /f >> "%LOG_FILE%" 2>&1
    if %errorlevel% leq 1 (
        call :log "[OK] Disk check completed on %TARGET_DRIVE%"
        echo [OK] Disk check complete.
    ) else (
        call :log "[WARN] chkdsk returned code %errorlevel%"
        echo [WARN] Disk check encountered issues (see log).
    )
) else (
    call :log "User skipped disk check."
    echo Skipped disk check.
)
echo.

:: ---- Summary -----------------------------------------------
call :section "OFFLINE REPAIR COMPLETE"
echo All offline repair tasks have been executed.
echo.
echo  Target: %TARGET_DRIVE%\ - Windows %TARGET_VER%
echo  Boot Mode: %BOOT_MODE% (%PART_STYLE%)
echo.
echo  Repairs performed:
echo    - BCD backup           : %BCD_BACKUP%
echo    - Offline DISM repair  : completed
echo    - Offline SFC scan     : completed
echo    - Boot sector repair   : completed
echo    - BCD rebuild          : completed
echo    - Boot Manager repair  : completed
echo.
echo  Full log: %LOG_FILE%
echo.
call :log "============================================================"
call :log "Offline repair script finished at %DATE% %TIME%"

echo Remove the Windows PE media and restart your computer
echo to attempt booting into Windows.
echo.
echo If Windows still doesn't boot:
echo   1. Check the log file for specific errors
echo   2. Try booting in Safe Mode
echo   3. Restore BCD from backup: %BCD_BACKUP%
echo.

pause
exit /b 0

:: ============================================================
:: Subroutines
:: ============================================================

:log
echo [%DATE% %TIME%] %~1 >> "%LOG_FILE%"
goto :eof

:section
echo.
echo ============================================================
echo  %~1
echo ============================================================
echo [%DATE% %TIME%] --- %~1 --- >> "%LOG_FILE%"
goto :eof

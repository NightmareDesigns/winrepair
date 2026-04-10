@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: winrepair.bat - Windows Automatic Repair Script
:: Runs common Windows repair tools in sequence and logs output.
:: Creates a System Restore Point, backs up user files and the
:: Registry BEFORE making any changes so nothing is ever lost.
:: ============================================================

:: ---- Setup log file ----------------------------------------
set "SCRIPT_DIR=%~dp0"
set "LOG_DIR=%SCRIPT_DIR%logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

:: Use PowerShell for locale-independent date/time formatting
for /f "usebackq" %%i in (`powershell -NoProfile -NonInteractive -Command "Get-Date -Format 'yyyy-MM-dd'"`) do set "D=%%i"
for /f "usebackq" %%i in (`powershell -NoProfile -NonInteractive -Command "Get-Date -Format 'HHmmss'"`) do set "T=%%i"
set "LOG_FILE=%LOG_DIR%\winrepair_%D%_%T%.log"

:: ---- Title and header --------------------------------------
title Windows Repair Script
echo.
echo ============================================================
echo  Windows Automatic Repair Script
echo  Log: %LOG_FILE%
echo ============================================================
echo.

call :log "Windows Automatic Repair Script started at %DATE% %TIME%"
call :log "============================================================"

:: ---- Administrator check -----------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script must be run as Administrator.
    echo        Right-click the script and select "Run as administrator".
    call :log "[ERROR] Script not run as Administrator. Aborting."
    pause
    exit /b 1
)
call :log "[OK] Running with Administrator privileges."

:: ---- Safety warning and confirmation -----------------------
echo ============================================================
echo  IMPORTANT - READ BEFORE CONTINUING
echo ============================================================
echo.
echo  This script will:
echo    1. Create a System Restore Point  (safety rollback)
echo    2. Back up your personal files    (non-destructive copy)
echo    3. Back up the Windows Registry   (safety rollback)
echo    4. Repair Windows system files    (DISM + SFC)
echo    5. Schedule a disk check          (runs on next reboot)
echo    6. Clear temporary files only     (no personal data)
echo    7. Reset the network stack
echo    8. Trigger a Windows Update scan
echo.
echo  Steps 1-3 protect your data BEFORE any changes are made.
echo  Your personal files (Documents, Desktop, Pictures, etc.)
echo  are NEVER deleted or modified by this script.
echo.
set /p "CONFIRM=Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    call :log "User cancelled at confirmation prompt."
    echo Cancelled. No changes were made.
    pause
    exit /b 0
)
echo.

:: ---- Ask for backup destination ----------------------------
echo ============================================================
echo  BACKUP DESTINATION
echo ============================================================
echo.
echo  Enter the full path where your files and Registry backup
echo  should be saved. This can be an external drive, USB stick,
echo  or any folder on a different drive.
echo.
echo  Example:  D:\WinRepairBackup
echo            E:\Backups\MyPC
echo.
set /p "BACKUP_ROOT=Backup destination path: "
if "%BACKUP_ROOT%"=="" (
    set "BACKUP_ROOT=%SCRIPT_DIR%backup"
    echo No path entered. Using default: %BACKUP_ROOT%
)
echo.

:: Create timestamped backup subfolder so each run is isolated
set "BACKUP_DIR=%BACKUP_ROOT%\winrepair_%D%_%T%"
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%" 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Could not create backup folder: %BACKUP_DIR%
    echo         Check that the drive exists and has enough space.
    call :log "[ERROR] Could not create backup folder: %BACKUP_DIR%. Aborting."
    pause
    exit /b 1
)
call :log "Backup folder: %BACKUP_DIR%"

:: ============================================================
:: SAFETY STEP A: Create System Restore Point
:: ============================================================
call :section "SAFETY A: Create System Restore Point"
echo Creating a System Restore Point so Windows can be rolled
echo back to its current state if anything goes wrong...
echo.

powershell -NoProfile -NonInteractive -Command ^
  "Enable-ComputerRestore -Drive '%SystemDrive%\' -ErrorAction SilentlyContinue; ^
   Checkpoint-Computer -Description 'WinRepair Script - pre-repair' ^
                       -RestorePointType 'MODIFY_SETTINGS'" >> "%LOG_FILE%" 2>&1

if %errorlevel% equ 0 (
    call :log "[OK] System Restore Point created successfully."
    echo [OK] System Restore Point created.
) else (
    call :log "[WARN] System Restore Point creation returned exit code %errorlevel%."
    echo [WARN] Could not create a System Restore Point (see log).
    echo        This may happen if System Restore is disabled or if one
    echo        was already created in the last 24 hours. Continuing...
)
echo.

:: ============================================================
:: SAFETY STEP B: Back Up User Files with Robocopy
:: ============================================================
call :section "SAFETY B: Back Up User Files"
echo Backing up your personal files to:
echo   %BACKUP_DIR%\UserFiles
echo.
echo  Folders included:
echo    Desktop, Documents, Downloads, Music, Pictures, Videos
echo.
echo  This is a COPY - your originals are untouched.
echo  Large folders may take a few minutes...
echo.

set "USER_BACKUP=%BACKUP_DIR%\UserFiles"

set "FOLDERS=Desktop Documents Downloads Music Pictures Videos"
for %%F in (%FOLDERS%) do (
    set "SRC=%USERPROFILE%\%%F"
    set "DST=%USER_BACKUP%\%%F"
    if exist "!SRC!" (
        echo   Backing up %%F...
        robocopy "!SRC!" "!DST!" /E /COPY:DAT /R:1 /W:1 /NP /LOG+:"%LOG_FILE%" >nul 2>&1
        :: robocopy exit codes 0-7 are success/informational
        if !errorlevel! leq 7 (
            call :log "[OK] %%F backed up to !DST!"
        ) else (
            call :log "[WARN] robocopy %%F exited with code !errorlevel! - some files may not have been copied."
        )
    ) else (
        call :log "[SKIP] %%F folder not found at !SRC!"
    )
)

echo.
echo [OK] User file backup complete.
call :log "[OK] User file backup complete: %USER_BACKUP%"
echo.

:: ============================================================
:: SAFETY STEP C: Back Up the Windows Registry
:: ============================================================
call :section "SAFETY C: Back Up Windows Registry"
echo Exporting registry hives to:
echo   %BACKUP_DIR%\Registry
echo.

set "REG_BACKUP=%BACKUP_DIR%\Registry"
if not exist "%REG_BACKUP%" mkdir "%REG_BACKUP%"

echo   Exporting HKEY_LOCAL_MACHINE...
reg export HKLM "%REG_BACKUP%\HKLM.reg" /y >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] HKLM exported."
) else (
    call :log "[WARN] HKLM export returned exit code %errorlevel%."
)

echo   Exporting HKEY_CURRENT_USER...
reg export HKCU "%REG_BACKUP%\HKCU.reg" /y >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] HKCU exported."
) else (
    call :log "[WARN] HKCU export returned exit code %errorlevel%."
)

echo.
echo [OK] Registry backup complete.
call :log "[OK] Registry backup complete: %REG_BACKUP%"
echo.

:: ============================================================
:: From here all changes are to Windows internals only.
:: Personal files are never touched below this line.
:: ============================================================

:: ---- Step 1: DISM - Restore Health -------------------------
call :section "STEP 1: DISM - Restore Windows Image Health"
echo Repairs the Windows component store.
echo This may take 10-30 minutes. Do not close this window...
echo.
DISM /Online /Cleanup-Image /RestoreHealth >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] DISM RestoreHealth completed successfully."
    echo [OK] DISM complete.
) else (
    call :log "[WARN] DISM RestoreHealth finished with errors (exit code %errorlevel%). Check log for details."
    echo [WARN] DISM finished with errors. See log for details.
)
echo.

:: ---- Step 2: SFC - System File Checker ---------------------
call :section "STEP 2: SFC - System File Checker"
echo Scans and repairs protected Windows system files.
echo This may take 10-20 minutes. Do not close this window...
echo.
sfc /scannow >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] SFC scan completed successfully."
    echo [OK] SFC complete.
) else (
    call :log "[WARN] SFC scan finished with errors (exit code %errorlevel%). Check log for details."
    echo [WARN] SFC finished with errors. See log for details.
)
echo.

:: ---- Step 3: Check Disk ------------------------------------
call :section "STEP 3: Check Disk (scheduled for next reboot)"
echo Schedules a filesystem error check on the system drive.
echo chkdsk only fixes filesystem metadata errors (/f).
echo.

set "SYS_DRIVE=%SystemDrive%"

:: Ask whether to also scan for bad sectors (takes much longer)
set /p "DO_BADSECTOR=Also scan for bad sectors? WARNING: takes 1-8 hours (Y/N) [N]: "
if /i "%DO_BADSECTOR%"=="Y" (
    set "CHKDSK_FLAGS=/f /r /x"
    call :log "User chose full chkdsk with bad-sector scan (/f /r /x)."
) else (
    set "CHKDSK_FLAGS=/f"
    call :log "User chose filesystem-only chkdsk (/f)."
)

echo y | chkdsk %SYS_DRIVE% %CHKDSK_FLAGS% >> "%LOG_FILE%" 2>&1
if %errorlevel% leq 1 (
    call :log "[OK] Check Disk scheduled on %SYS_DRIVE% (will run at next reboot)."
    echo [OK] Check Disk scheduled. It will run automatically on next reboot.
) else (
    call :log "[WARN] chkdsk returned exit code %errorlevel%."
    echo [WARN] chkdsk returned an unexpected code. See log for details.
)
echo.

:: ---- Step 4: Clear Temporary Files -------------------------
call :section "STEP 4: Clear Temporary Files"
echo Clearing system and user temporary files.
echo Your personal files (Documents, Desktop, etc.) are NOT touched.
echo.

:: Clear %TEMP% - delete contents only, keep the directory itself
:: (removing the directory could break apps that have handles open in it)
del /f /s /q "%TEMP%\*" >nul 2>&1

:: Clear Windows Temp
del /f /s /q "%SystemRoot%\Temp\*" >nul 2>&1

:: Clear Software Distribution download cache (Windows Update cache only)
del /f /s /q "%SystemRoot%\SoftwareDistribution\Download\*" >nul 2>&1

:: Clear Prefetch
del /f /s /q "%SystemRoot%\Prefetch\*" >nul 2>&1

call :log "[OK] Temporary files cleared (%TEMP%, Windows Temp, SoftwareDistribution Download, Prefetch)."
echo [OK] Temporary files cleared.
echo.

:: ---- Step 5: Reset Network Stack ---------------------------
call :section "STEP 5: Reset Network Stack"
echo Resetting Winsock, TCP/IP, DNS cache, and proxy settings.
echo.

netsh winsock reset >> "%LOG_FILE%" 2>&1
call :log "  netsh winsock reset: exit code %errorlevel%"

netsh int ip reset >> "%LOG_FILE%" 2>&1
call :log "  netsh int ip reset: exit code %errorlevel%"

ipconfig /flushdns >> "%LOG_FILE%" 2>&1
call :log "  ipconfig /flushdns: exit code %errorlevel%"

netsh winhttp reset proxy >> "%LOG_FILE%" 2>&1
call :log "  netsh winhttp reset proxy: exit code %errorlevel%"

call :log "[OK] Network stack reset complete."
echo [OK] Network stack reset.
echo.

:: ---- Step 6: Windows Update scan via usoclient ------------
call :section "STEP 6: Trigger Windows Update Scan"
echo Starting Windows Update scan in the background...
echo.
start /b usoclient StartScan >> "%LOG_FILE%" 2>&1
call :log "[OK] Windows Update scan triggered (usoclient StartScan)."
echo [OK] Windows Update scan triggered. Updates will install in the background.
echo.

:: ---- Summary -----------------------------------------------
call :section "REPAIR COMPLETE"
echo All repair tasks have been executed.
echo.
echo  Safety backups (created BEFORE any changes):
echo    Restore Point : created via System Restore
echo    User files    : %BACKUP_DIR%\UserFiles
echo    Registry      : %BACKUP_DIR%\Registry
echo.
echo  Repair tasks:
echo    DISM image restore       : done
echo    SFC system file scan     : done
echo    Check Disk               : scheduled for next reboot
echo    Temporary files cleared  : done
echo    Network stack reset      : done
echo    Windows Update scan      : triggered
echo.
echo  Full log: %LOG_FILE%
echo.
call :log "============================================================"
call :log "Repair script finished at %DATE% %TIME%"

echo A reboot is recommended to complete all repairs.
echo.
set /p "REBOOT=Reboot now? (Y/N): "
if /i "%REBOOT%"=="Y" (
    call :log "User chose to reboot."
    shutdown /r /t 10 /c "Windows Repair Script: Rebooting to complete repairs."
    echo Rebooting in 10 seconds... Press Ctrl+C to cancel.
) else (
    call :log "User chose not to reboot."
    echo Please reboot manually when ready to complete the disk check.
)

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

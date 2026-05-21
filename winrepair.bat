@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: winrepair.bat  -  Online Mode Windows Repair Script
::
:: Runs from inside a live (bootable) Windows session.
:: Creates a System Restore Point, backs up user files and the
:: Registry BEFORE making any changes so nothing is ever lost,
:: then runs DISM, SFC, CHKDSK, temp cleanup, network reset,
:: and a Windows Update scan.
::
:: GPU / Display adapter detection is included: if an NVIDIA
:: adapter is found, black-screen guidance and optional safe
:: recovery steps (Fast Startup toggle, PnP rescan) are offered.
::
:: If Windows will NOT boot at all, use the offline repair path:
::   1. Run build\build_winpe_usb.bat  (on a working PC)
::      to create a bootable repair USB from this repository.
::   2. Boot the broken PC from that USB.
::   3. winrepair_offline.bat starts automatically.
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
title Windows Repair Script  [Online Mode]
echo.
echo ============================================================
echo  Windows Automatic Repair Script  [ONLINE MODE]
echo  Running inside a live Windows session.
echo  Log: %LOG_FILE%
echo ============================================================
echo.
echo  NOTE: This script repairs Windows while it is running.
echo        If Windows cannot boot at all, use the offline path:
echo          build\build_winpe_usb.bat  to create a bootable USB
echo          then boot from the USB to run winrepair_offline.bat
echo.

call :log "Windows Automatic Repair Script [Online Mode] started at %DATE% %TIME%"
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
echo    4. Detect GPU / display adapters  (log info; NVIDIA advisory if found)
echo    5. Repair Windows system files    (DISM + SFC)
echo    6. Schedule a disk check          (runs on next reboot)
echo    7. Clear temporary files only     (no personal data)
echo    8. Reset the network stack
echo    9. Trigger a Windows Update scan
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

:: ============================================================
:: GPU DETECTION & DISPLAY DIAGNOSTICS
:: ============================================================
call :section "GPU / DISPLAY ADAPTER DETECTION"
echo Querying display adapters installed on this system...
echo.

:: Dump full display adapter details to the backup folder for reference
set "GPU_INFO_FILE=%BACKUP_DIR%\gpu_info.txt"
powershell -NoProfile -NonInteractive -Command ^
  "Get-WmiObject Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,Status | Format-List" ^
  > "%GPU_INFO_FILE%" 2>&1
type "%GPU_INFO_FILE%"
call :log "[OK] GPU info saved to: %GPU_INFO_FILE%"

:: Detect whether any NVIDIA adapter is present
set "NVIDIA_DETECTED=0"
for /f "usebackq" %%i in (`powershell -NoProfile -NonInteractive -Command "if (Get-WmiObject Win32_VideoController ^| Where-Object { $_.Name -like '*NVIDIA*' }) { '1' } else { '0' }"`) do (
    set "NVIDIA_DETECTED=%%i"
)

if "!NVIDIA_DETECTED!"=="1" (
    call :log "[INFO] NVIDIA display adapter detected on this system."
    echo.
    echo ============================================================
    echo  NVIDIA GPU DETECTED
    echo ============================================================
    echo.
    echo  An NVIDIA display adapter was found on this system.
    echo.
    echo  If you are experiencing a BLACK SCREEN or display issues,
    echo  the cause may be a corrupt, outdated, or incompatible NVIDIA
    echo  display driver rather than (or in addition to) a Windows
    echo  system-file problem.
    echo.
    echo  The DISM and SFC steps below repair core Windows system files
    echo  but do NOT reinstall or replace graphics driver files.
    echo.
    echo  Recommended steps if the black screen persists after this repair:
    echo    1. Boot into Safe Mode:
    echo         Hold SHIFT at the login screen, click Power > Restart,
    echo         then choose: Troubleshoot > Advanced options >
    echo         Startup Settings > Restart > press 4 (Safe Mode).
    echo    2. In Safe Mode, open Device Manager (devmgmt.msc),
    echo         expand "Display adapters", right-click the NVIDIA entry,
    echo         and choose "Uninstall device" (tick "Delete driver software").
    echo    3. Reboot normally. Windows will fall back to a generic display
    echo         driver.  Then reinstall the latest NVIDIA driver from:
    echo         https://www.nvidia.com/drivers
    echo    4. For a thorough driver cleanup before reinstalling, DDU
    echo         (Display Driver Uninstaller) can be used from Safe Mode.
    echo         Download only from https://www.guru3d.com
    echo         NOTE: DDU is a third-party tool; use at your own discretion.
    echo.

    :: ----------------------------------------------------------
    :: OPTIONAL: Disable Fast Startup
    :: ----------------------------------------------------------
    echo ============================================================
    echo  OPTIONAL: Disable Fast Startup
    echo ============================================================
    echo.
    echo  Windows Fast Startup (a form of hibernation) can prevent display
    echo  drivers from reinitialising correctly after a shutdown, causing
    echo  a black screen on the next boot.  Disabling it is safe and
    echo  easily reversed in:
    echo    Settings ^> System ^> Power ^& Sleep ^> Additional power settings
    echo    ^> "Choose what the power buttons do" ^> uncheck "Fast startup"
    echo.
    set /p "DISABLE_FASTSTARTUP=Disable Fast Startup now? (Y/N) [N]: "
    if /i "!DISABLE_FASTSTARTUP!"=="Y" (
        powercfg /h off >> "%LOG_FILE%" 2>&1
        if !errorlevel! equ 0 (
            call :log "[OK] Fast Startup (hibernate) disabled via powercfg /h off."
            echo [OK] Fast Startup disabled.
        ) else (
            call :log "[WARN] powercfg /h off returned exit code !errorlevel!."
            echo [WARN] Could not disable Fast Startup.  See log for details.
        )
    ) else (
        call :log "[SKIP] User declined to disable Fast Startup."
        echo [SKIP] Fast Startup unchanged.
    )
    echo.

    :: ----------------------------------------------------------
    :: OPTIONAL: Rescan PnP devices
    :: ----------------------------------------------------------
    echo ============================================================
    echo  OPTIONAL: Rescan PnP Devices (refresh Device Manager)
    echo ============================================================
    echo.
    echo  Rescanning PnP devices prompts Windows to re-detect and
    echo  re-initialise hardware.  This can help if the display adapter
    echo  shows a yellow warning in Device Manager or is listed as
    echo  "Unknown Device".  The scan is safe and non-destructive.
    echo.
    set /p "PNPSCAN=Rescan PnP devices now? (Y/N) [N]: "
    if /i "!PNPSCAN!"=="Y" (
        pnputil /scan-devices >> "%LOG_FILE%" 2>&1
        if !errorlevel! equ 0 (
            call :log "[OK] PnP device rescan triggered (pnputil /scan-devices)."
            echo [OK] PnP device rescan complete.
        ) else (
            call :log "[WARN] pnputil /scan-devices returned exit code !errorlevel!."
            echo [WARN] PnP rescan returned an error.  See log for details.
        )
    ) else (
        call :log "[SKIP] User declined PnP device rescan."
        echo [SKIP] PnP device rescan skipped.
    )
    echo.
) else (
    call :log "[INFO] No NVIDIA display adapter detected on this system."
    echo  No NVIDIA GPU detected on this system.
)
echo.

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
set /p "SCAN_BAD_SECTORS=Also scan for bad sectors? WARNING: takes 1-8 hours (Y/N) [N]: "
if /i "%SCAN_BAD_SECTORS%"=="Y" (
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
echo  Diagnostics:
echo    GPU info      : %BACKUP_DIR%\gpu_info.txt
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
echo If you have an NVIDIA GPU and still experience a black screen
echo after rebooting, see the GPU advisory above (and in the log).
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

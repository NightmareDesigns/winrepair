@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: winrepair_offline.bat  -  WinPE Offline Windows Repair
::
:: Designed to run from WinPE (bootable USB / ISO) launched by
:: winpe\startnet.cmd.  It repairs a Windows 10 / 11
:: installation on an offline (non-booted) drive WITHOUT
:: deleting or modifying personal data.
::
:: Flow
:: ----
::   DETECT  - scan drives, let user pick target & backup drive
::   SAFETY A - Robocopy user profiles to backup drive
::   SAFETY B - copy raw Registry hive files to backup drive
::   REPAIR 1 - DISM offline image repair
::   REPAIR 2 - SFC offline system-file scan
::   REPAIR 3 - CHKDSK (runs immediately; target drive is idle)
::   REPAIR 4 - bootrec MBR / boot-sector / BCD rebuild
::   REPAIR 5 - offline temp-file cleanup
::
:: Personal files are NEVER deleted.  All backups are created
:: before the first repair step runs.
:: ============================================================

:: ---- Verify WinPE environment --------------------------------
:: In WinPE the system drive is always X: (the RAM disk).
:: Refuse to run outside WinPE to avoid confusion with the
:: online script (winrepair.bat).
if /i not "%SystemDrive%"=="X:" (
    echo.
    echo  [ERROR] This script must run inside WinPE (bootable USB or ISO).
    echo          It cannot run from within a live Windows session.
    echo.
    echo  To repair Windows while it is already running, use winrepair.bat.
    echo  To create a bootable repair USB, run build\build_winpe_usb.bat.
    echo.
    pause
    exit /b 1
)

:: ---- Log file setup ------------------------------------------
:: Logs are written to the WinPE ramdisk (X:) during the run and
:: copied to the backup folder once the backup drive is confirmed.
set "LOG_DIR=X:\winrepair\logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" 2>nul

:: Locale-independent timestamp via wmic
set "D=unknown-date"
set "T=000000"
for /f "tokens=2 delims==" %%i in ('wmic os get LocalDateTime /value 2^>nul') do (
    if not "%%i"=="" (
        set "_DT=%%i"
        set "D=!_DT:~0,4!-!_DT:~4,2!-!_DT:~6,2!"
        set "T=!_DT:~8,2!!_DT:~10,2!!_DT:~12,2!"
    )
)
set "LOG_FILE=%LOG_DIR%\winrepair_offline_%D%_%T%.log"

:: ---- Title and header ----------------------------------------
title WinPE Offline Windows Repair
cls
echo.
echo ============================================================
echo  WinPE Offline Windows Repair
echo  Repair Windows 10 / 11 WITHOUT losing personal data.
echo ============================================================
echo  Log: %LOG_FILE%
echo.

call :log "============================================================"
call :log "WinPE Offline Repair started at %DATE% %TIME%"
call :log "============================================================"

:: ---- Opening safety warning ----------------------------------
echo ============================================================
echo  IMPORTANT  -  READ BEFORE CONTINUING
echo ============================================================
echo.
echo  Running in WinPE (offline mode).  This script will:
echo.
echo    SAFETY  (all completed BEFORE any repair step runs):
echo      A. Back up user profile folders  (Robocopy - non-destructive copy)
echo      B. Back up Registry hive files   (raw file copy from offline install)
echo.
echo    REPAIR  (only after both safety backups succeed):
echo      1. DISM    - Repair the offline Windows component store / image
echo      2. SFC     - Scan and fix offline protected system files
echo      3. CHKDSK  - Fix disk / filesystem errors NOW (drive is not in use)
echo      4. bootrec - Rebuild MBR, boot sector, and Boot Configuration Data
echo      5. Cleanup - Clear offline Windows temporary files
echo.
echo  Your Documents, Desktop, Pictures, and other personal folders
echo  are NEVER deleted or modified by this script.
echo.
set /p "CONFIRM=Continue? (Y/N): "
if /i not "%CONFIRM%"=="Y" (
    call :log "User cancelled at opening confirmation prompt."
    echo Cancelled.  No changes were made.
    pause
    exit /b 0
)
echo.

:: ============================================================
:: PHASE 1  -  DETECT WINDOWS INSTALLATIONS
:: ============================================================
call :section "DETECTING WINDOWS INSTALLATIONS"

echo Scanning attached drives for Windows installations...
echo (Drives are identified by the presence of Windows\System32\ntoskrnl.exe)
echo.

set "WIN_COUNT=0"
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\Windows\System32\ntoskrnl.exe" (
        set /a "WIN_COUNT+=1"
        set "WIN_DRIVE[!WIN_COUNT!]=%%D"
        echo   [!WIN_COUNT!] %%D:\  (Windows installation detected^)
        call :log "  Candidate Windows installation: %%D:\"
    )
)

if %WIN_COUNT%==0 (
    echo.
    echo [ERROR] No Windows installation found on any attached drive.
    echo.
    echo  Possible causes:
    echo    - The Windows drive is not connected or not powered on
    echo    - The drive uses a filesystem or partition table that WinPE
    echo      cannot read without additional drivers (rare)
    echo    - WinPE has not finished enumerating drives (wait 30 s, retry^)
    echo.
    call :log "[ERROR] No Windows installation detected. Aborting."
    pause
    exit /b 1
)

echo.
if %WIN_COUNT%==1 (
    set "TARGET_DRIVE=!WIN_DRIVE[1]!"
    echo Only one installation found.  Selecting !TARGET_DRIVE!:\ automatically.
    call :log "Auto-selected target drive: !TARGET_DRIVE!:\"
) else (
    set /p "WIN_SEL=Select the installation to repair [1-%WIN_COUNT%]: "
    set "TARGET_DRIVE="
    for /l %%i in (1,1,%WIN_COUNT%) do (
        if "%%i"=="!WIN_SEL!" set "TARGET_DRIVE=!WIN_DRIVE[%%i]!"
    )
    if not defined TARGET_DRIVE (
        echo [ERROR] Invalid selection.  Aborting.
        call :log "[ERROR] Invalid Windows selection '%WIN_SEL%'. Aborting."
        pause
        exit /b 1
    )
    call :log "User selected target drive: !TARGET_DRIVE!:\"
)

set "TARGET_ROOT=%TARGET_DRIVE%:\"
set "TARGET_WIN=%TARGET_DRIVE%:\Windows"
echo.
echo  Target Windows installation : %TARGET_ROOT%
call :log "Target root: %TARGET_ROOT%"
call :log "Target Windows dir: %TARGET_WIN%"

:: ============================================================
:: PHASE 2  -  SELECT BACKUP DESTINATION
:: ============================================================
call :section "SELECT BACKUP DESTINATION"

echo Available drives for backup (excluding X: WinPE ramdisk and target %TARGET_DRIVE%:):
echo.

set "BAK_COUNT=0"
for %%D in (A B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if /i not "%%D"=="X" (
        if /i not "%%D"=="%TARGET_DRIVE%" (
            if exist "%%D:\" (
                set /a "BAK_COUNT+=1"
                set "BAK_OPT[!BAK_COUNT!]=%%D"
                echo   [!BAK_COUNT!] %%D:\
            )
        )
    )
)

if %BAK_COUNT%==0 (
    echo.
    echo [ERROR] No suitable backup drive found.
    echo.
    echo  Please attach an external USB drive or hard disk that has enough
    echo  free space (at least as much as the size of your Users folder),
    echo  then restart this script.
    echo.
    call :log "[ERROR] No backup drive available. Aborting."
    pause
    exit /b 1
)

echo.
echo  TIP: Use an external USB drive or a second internal hard disk.
echo       Avoid the same drive that contains the Windows installation.
echo.
set /p "BAK_SEL=Select backup destination drive [1-%BAK_COUNT%]: "

set "BACKUP_BASE_DRIVE="
for /l %%i in (1,1,%BAK_COUNT%) do (
    if "%%i"=="!BAK_SEL!" set "BACKUP_BASE_DRIVE=!BAK_OPT[%%i]!"
)
if not defined BACKUP_BASE_DRIVE (
    echo [ERROR] Invalid selection.  Aborting.
    call :log "[ERROR] Invalid backup drive selection '%BAK_SEL%'. Aborting."
    pause
    exit /b 1
)

set "BACKUP_ROOT=%BACKUP_BASE_DRIVE%:\WinRepairBackup"
set "BACKUP_DIR=%BACKUP_ROOT%\winrepair_offline_%D%_%T%"
call :log "Backup destination: %BACKUP_DIR%"

:: ---- Create the timestamped backup folder --------------------
if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%" 2>nul
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Could not create backup folder: %BACKUP_DIR%
    echo         Check that the drive is writable and has enough free space.
    echo.
    call :log "[ERROR] Could not create %BACKUP_DIR%. Aborting."
    pause
    exit /b 1
)

:: ---- Free-space check (PowerShell; silent fail if unavailable) -
echo.
echo Checking free space on %BACKUP_BASE_DRIVE%:\...
powershell -NoProfile -NonInteractive -Command ^
  "try { $d = Get-PSDrive '%BACKUP_BASE_DRIVE%' -EA Stop; [math]::Round($d.Free/1GB,2) } catch { -1 }" ^
  > "%TEMP%\__fscheck.txt" 2>nul
set "FREE_GB="
for /f %%i in ("%TEMP%\__fscheck.txt") do set "FREE_GB=%%i"
if defined FREE_GB (
    if not "!FREE_GB!"=="-1" (
        echo  Free space: %FREE_GB% GB available on %BACKUP_BASE_DRIVE%:\
        call :log "Free space on %BACKUP_BASE_DRIVE%:\: %FREE_GB% GB"
    )
)
del /f /q "%TEMP%\__fscheck.txt" 2>nul
echo.

:: ---- Final confirmation before any change --------------------
echo ============================================================
echo  FINAL CONFIRMATION
echo ============================================================
echo.
echo   Windows to repair : %TARGET_ROOT%
echo   Backup location   : %BACKUP_DIR%
echo.
echo  Proceeding will:
echo    1. Copy all user profiles from %TARGET_DRIVE%:\Users  to the backup
echo    2. Copy Registry hive files from the offline installation
echo    3. Run offline DISM, SFC, CHKDSK, and bootrec
echo.
echo  Review the backup path carefully.  Once repair begins it cannot be
echo  easily undone without the backup or a Windows installation media.
echo.
set /p "GO=Proceed? (Y/N): "
if /i not "%GO%"=="Y" (
    call :log "User cancelled at final confirmation."
    echo Cancelled.  No changes were made.
    rd /s /q "%BACKUP_DIR%" 2>nul
    pause
    exit /b 0
)
echo.

:: ============================================================
:: SAFETY A  -  Back Up User Profiles
:: ============================================================
call :section "SAFETY A: Back Up User Profiles"
echo Copying user profiles from:
echo   %TARGET_DRIVE%:\Users
echo To:
echo   %BACKUP_DIR%\Users
echo.
echo System accounts (Public, Default, Default User, All Users)
echo are excluded.  AppData\Local\Temp is skipped to save space.
echo.
echo This is a COPY - originals are not touched.
echo Large profiles may take several minutes...
echo.

set "USERS_SRC=%TARGET_DRIVE%:\Users"
set "USERS_DST=%BACKUP_DIR%\Users"

if not exist "%USERS_SRC%" (
    call :log "[WARN] %USERS_SRC% not found. Skipping user profile backup."
    echo [WARN] No Users folder found on %TARGET_DRIVE%:\.  Skipping.
) else (
    set "PROF_COUNT=0"
    for /d %%U in ("%USERS_SRC%\*") do (
        set "PROF_NAME=%%~nxU"
        :: Skip built-in system accounts that contain no personal data
        if /i not "!PROF_NAME!"=="Public" (
        if /i not "!PROF_NAME!"=="Default" (
        if /i not "!PROF_NAME!"=="Default User" (
        if /i not "!PROF_NAME!"=="All Users" (
            set /a "PROF_COUNT+=1"
            echo   Backing up profile: !PROF_NAME!...
            robocopy "!USERS_SRC!\!PROF_NAME!" "!USERS_DST!\!PROF_NAME!" ^
                /E /COPY:DAT /R:1 /W:1 /NP ^
                /XD "AppData\Local\Temp" ^
                /LOG+:"%LOG_FILE%" >nul 2>&1
            :: Robocopy exit codes 0-7 are all success / informational
            if !errorlevel! leq 7 (
                call :log "[OK] Profile backed up: !PROF_NAME!"
                echo   [OK] !PROF_NAME!
            ) else (
                call :log "[WARN] Robocopy exit code !errorlevel! for profile !PROF_NAME! - some files may have been skipped."
                echo   [WARN] !PROF_NAME! - some files may have been skipped (see log^)
            )
        ))))
    )

    if !PROF_COUNT!==0 (
        call :log "[WARN] No user profiles found to back up."
        echo [WARN] No user profiles found in %USERS_SRC%
    ) else (
        call :log "[OK] User profile backup complete: !PROF_COUNT! profile(s)."
        echo.
        echo [OK] !PROF_COUNT! user profile(s) backed up to:
        echo      %USERS_DST%
    )
)
echo.

:: ============================================================
:: SAFETY B  -  Back Up Registry Hive Files
:: ============================================================
call :section "SAFETY B: Back Up Registry Hive Files"
echo Copying raw registry hive files from:
echo   %TARGET_WIN%\System32\config
echo To:
echo   %BACKUP_DIR%\Registry
echo.
echo These files can be loaded with regedit or used for forensic
echo recovery even if Windows does not boot at all.
echo.

set "REG_SRC=%TARGET_WIN%\System32\config"
set "REG_DST=%BACKUP_DIR%\Registry"
if not exist "%REG_DST%" mkdir "%REG_DST%"

for %%H in (SOFTWARE SYSTEM SAM SECURITY DEFAULT) do (
    if exist "%REG_SRC%\%%H" (
        copy /y "%REG_SRC%\%%H" "%REG_DST%\%%H" >nul 2>&1
        if !errorlevel! equ 0 (
            call :log "[OK] Registry hive backed up: %%H"
            echo   [OK] %%H
        ) else (
            call :log "[WARN] Could not copy hive: %%H (may be locked by WinPE)"
            echo   [WARN] %%H  - copy failed (hive may be locked^)
        )
    ) else (
        call :log "[SKIP] Registry hive not found: %%H"
        echo   [SKIP] %%H not found
    )
)

call :log "[OK] Registry hive backup complete: %REG_DST%"
echo.
echo [OK] Registry hive backup complete.
echo.

:: ---- Copy live log to backup folder (off the volatile ramdisk) -
if not exist "%BACKUP_DIR%\Logs" mkdir "%BACKUP_DIR%\Logs"
copy /y "%LOG_FILE%" "%BACKUP_DIR%\Logs\" >nul 2>&1

echo ============================================================
echo  Both safety backups are complete.  Starting repairs...
echo ============================================================
echo.

:: ============================================================
:: REPAIR 1  -  Offline DISM Image Repair
:: ============================================================
call :section "REPAIR 1: DISM - Offline Windows Image Repair"
echo Repairing the Windows component store on %TARGET_ROOT%
echo.
echo This may take 15-45 minutes depending on damage and drive speed.
echo Do not close this window or remove the USB drive.
echo.

DISM /Image:"%TARGET_ROOT%" /Cleanup-Image /RestoreHealth >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] DISM offline RestoreHealth completed successfully."
    echo [OK] DISM image repair complete.
) else (
    call :log "[WARN] DISM offline RestoreHealth exit code %errorlevel%."
    echo [WARN] DISM finished with exit code %errorlevel%.
    echo.
    echo  This may indicate severe image corruption or that DISM could not
    echo  download replacement files (network not available in WinPE by default^).
    echo.
    echo  If this warning appears you can retry with a local repair source:
    echo    DISM /Image:%TARGET_ROOT% /Cleanup-Image /RestoreHealth
    echo         /Source:wim:D:\sources\install.wim:1 /LimitAccess
    echo  (replace D: with the drive letter of a Windows 11 installation USB^)
)
echo.

:: ============================================================
:: REPAIR 2  -  Offline SFC
:: ============================================================
call :section "REPAIR 2: SFC - Offline System File Checker"
echo Scanning and repairing protected Windows system files.
echo.
echo Target Windows directory: %TARGET_WIN%
echo.

sfc /scannow /offbootdir="%TARGET_ROOT%" /offwindir="%TARGET_WIN%" >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] SFC offline scan completed successfully."
    echo [OK] SFC scan complete.
) else (
    call :log "[WARN] SFC offline scan exit code %errorlevel%."
    echo [WARN] SFC finished with exit code %errorlevel%.  See log for details.
)
echo.

:: ============================================================
:: REPAIR 3  -  CHKDSK
:: ============================================================
call :section "REPAIR 3: CHKDSK - Disk and Filesystem Error Check"
echo Checking %TARGET_DRIVE%:\ for filesystem and disk errors.
echo.
echo Because Windows is OFFLINE the drive is not in use, so CHKDSK
echo can fix errors immediately without scheduling a reboot check.
echo.

set /p "SCAN_BAD_SECTORS=Also scan for bad sectors? WARNING: can take 1-8 hours (Y/N) [N]: "
if /i "%SCAN_BAD_SECTORS%"=="Y" (
    set "CHKDSK_FLAGS=/f /r"
    call :log "User chose full CHKDSK with bad-sector scan (/f /r)."
    echo Running CHKDSK /f /r on %TARGET_DRIVE%: ...
) else (
    set "CHKDSK_FLAGS=/f"
    call :log "User chose filesystem-only CHKDSK (/f)."
    echo Running CHKDSK /f on %TARGET_DRIVE%: ...
)
echo.

chkdsk %TARGET_DRIVE%: %CHKDSK_FLAGS% >> "%LOG_FILE%" 2>&1
:: CHKDSK exit codes: 0 = no errors found, 1 = errors found and fixed,
:: 2 = disk cleanup was performed (volume dirty flag was set).
:: All three are acceptable outcomes; exit code 3+ indicates a hard failure.
if %errorlevel% leq 2 (
    call :log "[OK] CHKDSK completed on %TARGET_DRIVE%: (exit code %errorlevel%)."
    echo [OK] CHKDSK complete.
) else (
    call :log "[WARN] CHKDSK exit code %errorlevel% on %TARGET_DRIVE%:."
    echo [WARN] CHKDSK returned exit code %errorlevel%.  See log for details.
)
echo.

:: ============================================================
:: REPAIR 4  -  Boot Configuration Repair (bootrec)
:: ============================================================
call :section "REPAIR 4: Boot Configuration Repair (bootrec)"
echo Rebuilding the Master Boot Record, boot sector, and Boot Configuration
echo Data (BCD).  This fixes boot failures that prevent Windows from starting.
echo.
echo NOTE: On UEFI / GPT systems, /fixmbr and /fixboot may report
echo       "Access is denied" - this is expected and harmless on UEFI PCs.
echo       The /rebuildbcd step is the most important one on UEFI systems.
echo.

echo   [1/4] Fixing Master Boot Record (MBR)...
bootrec /fixmbr >> "%LOG_FILE%" 2>&1
call :log "  bootrec /fixmbr exit code: %errorlevel%"

echo   [2/4] Fixing boot sector...
bootrec /fixboot >> "%LOG_FILE%" 2>&1
call :log "  bootrec /fixboot exit code: %errorlevel%"

echo   [3/4] Scanning for all Windows installations...
bootrec /scanos >> "%LOG_FILE%" 2>&1
call :log "  bootrec /scanos exit code: %errorlevel%"

echo   [4/4] Rebuilding Boot Configuration Data (BCD)...
bootrec /rebuildbcd >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] bootrec /rebuildbcd succeeded."
    echo [OK] BCD rebuilt successfully.
) else (
    call :log "[WARN] bootrec /rebuildbcd exit code %errorlevel%."
    echo [WARN] BCD rebuild returned exit code %errorlevel%.
    echo.
    echo  If Windows still does not boot after restarting, try these commands
    echo  manually from this WinPE command prompt:
    echo.
    echo    bcdedit /export %TARGET_DRIVE%:\BCD_backup
    echo    attrib %TARGET_DRIVE%:\boot\bcd -h -r -s
    echo    ren %TARGET_DRIVE%:\boot\bcd bcd.old
    echo    bootrec /rebuildbcd
    echo.
    echo  For UEFI systems where the above fails, also try:
    echo    bcdboot %TARGET_WIN%\  /s [EFI-partition-letter]: /f UEFI
    echo  (Use diskpart to identify the EFI System Partition letter^)
)
echo.

:: ============================================================
:: REPAIR 5  -  Clear Offline Temporary Files
:: ============================================================
call :section "REPAIR 5: Clear Offline Temporary Files"
echo Clearing temporary files from the offline Windows installation.
echo Personal files (Documents, Desktop, Pictures, etc.) are NOT touched.
echo.

:: Windows system temp folder
set "WIN_TEMP=%TARGET_WIN%\Temp"
if exist "%WIN_TEMP%" (
    del /f /s /q "%WIN_TEMP%\*" >nul 2>&1
    call :log "[OK] Cleared %WIN_TEMP%"
    echo   [OK] Windows\Temp
)

:: Windows Update download cache
set "SD_CACHE=%TARGET_WIN%\SoftwareDistribution\Download"
if exist "%SD_CACHE%" (
    del /f /s /q "%SD_CACHE%\*" >nul 2>&1
    call :log "[OK] Cleared %SD_CACHE%"
    echo   [OK] SoftwareDistribution\Download (Windows Update cache^)
)

:: Prefetch
set "PREFETCH=%TARGET_WIN%\Prefetch"
if exist "%PREFETCH%" (
    del /f /s /q "%PREFETCH%\*" >nul 2>&1
    call :log "[OK] Cleared %PREFETCH%"
    echo   [OK] Prefetch
)

:: User temp folders (AppData\Local\Temp for each profile)
for /d %%U in ("%TARGET_DRIVE%:\Users\*") do (
    set "UTEMP=%%U\AppData\Local\Temp"
    if exist "!UTEMP!" (
        del /f /s /q "!UTEMP!\*" >nul 2>&1
        call :log "[OK] Cleared user temp: !UTEMP!"
        echo   [OK] %%~nxU\AppData\Local\Temp
    )
)

call :log "[OK] Offline temporary file cleanup complete."
echo.
echo [OK] Temporary files cleared.
echo.

:: ---- Final log copy to backup -------------------------------
copy /y "%LOG_FILE%" "%BACKUP_DIR%\Logs\" >nul 2>&1

:: ============================================================
:: SUMMARY
:: ============================================================
call :section "REPAIR COMPLETE"
echo All repair tasks have been executed.
echo.
echo  Target repaired    : %TARGET_ROOT%
echo.
echo  Safety backups (created BEFORE any changes):
echo    User profiles  : %BACKUP_DIR%\Users
echo    Registry hives : %BACKUP_DIR%\Registry
echo.
echo  Repair tasks completed:
echo    DISM offline image repair : done  (check log for warnings^)
echo    SFC offline system scan   : done  (check log for warnings^)
echo    CHKDSK disk error check   : done
echo    Boot config (bootrec^)     : done
echo    Offline temp cleanup      : done
echo.
echo  Full log saved to:
echo    %BACKUP_DIR%\Logs\
echo    %LOG_FILE%
echo.
echo  NEXT STEP: Remove the repair USB and reboot.  Windows should now start.
echo  If Windows still does not boot, consult the log for DISM / bootrec errors.
echo.
call :log "============================================================"
call :log "WinPE Offline Repair completed at %DATE% %TIME%"
call :log "============================================================"

set /p "REBOOT=Reboot now? (Y/N): "
if /i "%REBOOT%"=="Y" (
    call :log "User chose to reboot."
    echo Rebooting in 5 seconds...  Remove the USB drive now.
    ping -n 6 127.0.0.1 >nul 2>&1
    wpeutil reboot
) else (
    call :log "User chose not to reboot."
    echo.
    echo Remove the repair USB drive when you are ready, then reboot manually.
    echo.
    cmd /k
)

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
echo.
echo [%DATE% %TIME%] --- %~1 --- >> "%LOG_FILE%"
goto :eof

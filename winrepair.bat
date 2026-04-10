@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: winrepair.bat - Windows Automatic Repair Script
:: Runs common Windows repair tools in sequence and logs output
:: ============================================================

:: ---- Setup log file ----------------------------------------
set "LOG_DIR=%~dp0logs"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

for /f "tokens=1-3 delims=/ " %%a in ("%DATE%") do set "D=%%a-%%b-%%c"
for /f "tokens=1-3 delims=:." %%a in ("%TIME: =0%") do set "T=%%a%%b%%c"
set "LOG_FILE=%LOG_DIR%\winrepair_%D%_%T%.log"

:: Redirect all output to log file while still showing on screen
set "LOGCMD=call :log"

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

:: ---- Step 1: DISM - Restore Health -------------------------
call :section "STEP 1: DISM - Restore Windows Image Health"
echo This may take several minutes...
echo.
DISM /Online /Cleanup-Image /RestoreHealth >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] DISM RestoreHealth completed successfully."
) else (
    call :log "[WARN] DISM RestoreHealth finished with errors (exit code %errorlevel%). Check log for details."
)
echo Done. See log for details.
echo.

:: ---- Step 2: SFC - System File Checker ---------------------
call :section "STEP 2: SFC - System File Checker"
echo Scanning protected system files...
echo.
sfc /scannow >> "%LOG_FILE%" 2>&1
if %errorlevel% equ 0 (
    call :log "[OK] SFC scan completed successfully."
) else (
    call :log "[WARN] SFC scan finished with errors (exit code %errorlevel%). Check log for details."
)
echo Done. See log for details.
echo.

:: ---- Step 3: Check Disk ------------------------------------
call :section "STEP 3: Check Disk (scheduled for next reboot)"
echo Scheduling chkdsk on the system drive...
echo.
set "SYS_DRIVE=%SystemDrive%"
echo y | chkdsk %SYS_DRIVE% /f /r /x >> "%LOG_FILE%" 2>&1
if %errorlevel% leq 1 (
    call :log "[OK] Check Disk scheduled on %SYS_DRIVE% (will run at next reboot)."
) else (
    call :log "[WARN] chkdsk returned exit code %errorlevel%."
)
echo Done. Check Disk will run on next reboot if required.
echo.

:: ---- Step 4: Clear Temporary Files -------------------------
call :section "STEP 4: Clear Temporary Files"
echo Clearing temporary files...
echo.

set "DEL_COUNT=0"

:: Clear %TEMP%
for /f %%i in ('dir /b /s /a "%TEMP%\*" 2^>nul ^| find /c /v ""') do set /a "DEL_COUNT+=%%i"
del /f /s /q "%TEMP%\*" >nul 2>&1
rd /s /q "%TEMP%" >nul 2>&1
md "%TEMP%" >nul 2>&1

:: Clear Windows Temp
del /f /s /q "%SystemRoot%\Temp\*" >nul 2>&1
rd /s /q "%SystemRoot%\Temp" >nul 2>&1
md "%SystemRoot%\Temp" >nul 2>&1

:: Clear Software Distribution download cache
del /f /s /q "%SystemRoot%\SoftwareDistribution\Download\*" >nul 2>&1

:: Clear Prefetch
del /f /s /q "%SystemRoot%\Prefetch\*" >nul 2>&1

call :log "[OK] Temporary files cleared (%%TEMP%%, Windows Temp, SoftwareDistribution Download, Prefetch)."
echo Done.
echo.

:: ---- Step 5: Reset Network Stack ---------------------------
call :section "STEP 5: Reset Network Stack"
echo Resetting Winsock, TCP/IP, DNS cache, and proxy...
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
echo Done.
echo.

:: ---- Step 6: Windows Update scan via usoclient ------------
call :section "STEP 6: Trigger Windows Update Scan"
echo Starting Windows Update scan in the background...
echo.
start /b usoclient StartScan >> "%LOG_FILE%" 2>&1
call :log "[OK] Windows Update scan triggered (usoclient StartScan)."
echo Done. Updates will download and install in the background.
echo.

:: ---- Summary -----------------------------------------------
call :section "REPAIR COMPLETE"
echo All repair tasks have been executed.
echo.
echo  - DISM image restore       : done
echo  - SFC system file scan     : done
echo  - Check Disk               : scheduled for next reboot
echo  - Temporary files cleared  : done
echo  - Network stack reset      : done
echo  - Windows Update scan      : triggered
echo.
echo Full log saved to:
echo   %LOG_FILE%
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
    echo Please reboot manually when ready.
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
echo ============================================================
echo  %~1
echo ============================================================
echo [%DATE% %TIME%] --- %~1 --- >> "%LOG_FILE%"
goto :eof

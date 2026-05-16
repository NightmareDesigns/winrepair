@echo off
:: ============================================================
:: startnet.cmd - Windows PE Startup Script
:: This script runs automatically when Windows PE boots.
:: It initializes the environment and presents repair options.
:: ============================================================

:: Set title
title Windows PE Repair Environment

:: Initialize WinPE network support (loads drivers)
wpeinit

:: Wait a moment for initialization
timeout /t 3 /nobreak >nul

:: Clear screen and show menu
cls
echo.
echo ============================================================
echo           Windows PE Repair Environment
echo ============================================================
echo.
echo  System Information:
echo  -------------------
wpeutil UpdateBootInfo >nul 2>&1

:: Display WinPE version
for /f "tokens=2 delims=[]" %%i in ('ver') do echo  Windows PE Version: %%i
echo.

:: List available drives
echo  Available Drives:
echo  -----------------
echo list volume | diskpart | findstr /i "Volume"
echo.

echo ============================================================
echo                    REPAIR OPTIONS
echo ============================================================
echo.
echo  [1] Run Automatic Offline Repair (Recommended)
echo      - Detects Windows installations
echo      - Repairs system files (DISM, SFC)
echo      - Fixes boot configuration (BCD, MBR, UEFI)
echo.
echo  [2] Open Command Prompt (Manual Repair)
echo      - Advanced users only
echo      - Full access to all Windows PE tools
echo.
echo  [3] Reboot Computer
echo      - Exit Windows PE and restart
echo.
echo  [4] Power Off Computer
echo      - Shut down the system
echo.
echo ============================================================
echo.

:menu
set /p "CHOICE=Select option (1-4): "

if "%CHOICE%"=="1" goto :auto_repair
if "%CHOICE%"=="2" goto :manual_repair
if "%CHOICE%"=="3" goto :reboot
if "%CHOICE%"=="4" goto :poweroff

echo Invalid choice. Please enter 1, 2, 3, or 4.
echo.
goto :menu

:auto_repair
cls
echo.
echo ============================================================
echo        Launching Automatic Offline Repair Script
echo ============================================================
echo.

:: Check if winrepair_offline.bat exists in common locations
if exist "%~dp0winrepair_offline.bat" (
    call "%~dp0winrepair_offline.bat"
) else if exist "X:\winrepair_offline.bat" (
    call "X:\winrepair_offline.bat"
) else if exist "X:\sources\winrepair_offline.bat" (
    call "X:\sources\winrepair_offline.bat"
) else if exist "%SystemDrive%\winrepair_offline.bat" (
    call "%SystemDrive%\winrepair_offline.bat"
) else (
    echo [ERROR] Cannot find winrepair_offline.bat
    echo         The repair script should be on the Windows PE media.
    echo.
    echo Press any key to return to menu...
    pause >nul
    goto :start
)

echo.
echo Repair script completed.
echo Press any key to return to menu or close to reboot...
pause >nul
goto :start

:manual_repair
cls
echo.
echo ============================================================
echo           Manual Repair - Command Prompt
echo ============================================================
echo.
echo  Opening command prompt for manual repairs...
echo  Type 'exit' to return to this menu.
echo.
echo  Common repair commands:
echo    diskpart           - Disk partition management
echo    bcdedit            - Boot configuration editor
echo    bootrec /fixmbr    - Fix Master Boot Record
echo    bootrec /fixboot   - Fix boot sector
echo    bootrec /rebuildbcd - Rebuild boot configuration
echo    DISM /Image:C:\ /Cleanup-Image /RestoreHealth - Offline DISM
echo    sfc /scannow /OFFBOOTDIR=C:\ /OFFWINDIR=C:\Windows - Offline SFC
echo.
pause

:: Open new command prompt
cmd

echo.
echo Returned from command prompt.
echo Press any key to return to menu...
pause >nul
goto :start

:reboot
cls
echo.
echo ============================================================
echo                    Rebooting System
echo ============================================================
echo.
echo  Remove the Windows PE media (USB/DVD) before reboot.
echo  Press Ctrl+C to cancel.
echo.
timeout /t 5
wpeutil reboot
goto :eof

:poweroff
cls
echo.
echo ============================================================
echo                  Shutting Down System
echo ============================================================
echo.
echo  Press Ctrl+C to cancel.
echo.
timeout /t 5
wpeutil shutdown
goto :eof

:start
cls
goto :menu

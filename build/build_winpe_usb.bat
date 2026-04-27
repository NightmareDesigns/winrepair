@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: build_winpe_usb.bat  -  Build a bootable WinPE repair USB
::
:: Creates a USB drive that boots directly into the offline
:: Windows repair tool (winrepair_offline.bat).
::
:: Requirements
:: ------------
::   - Windows 10 or Windows 11 host PC
::   - Windows ADK (Assessment and Deployment Kit)
::       https://learn.microsoft.com/windows-hardware/get-started/adk-install
::   - Windows PE add-on for the ADK (same download page)
::   - Run as Administrator
::   - A USB flash drive with at least 2 GB free space
::     (ALL EXISTING DATA ON THE USB WILL BE ERASED)
::
:: Usage
:: -----
::   Right-click build_winpe_usb.bat -> Run as administrator
::   Follow the on-screen prompts.
:: ============================================================

:: ---- Admin check --------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click the script and choose "Run as administrator".
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  WinRepair  -  Build Bootable USB Drive
echo ============================================================
echo.

:: ---- Locate Windows ADK + WinPE add-on ----------------------
set "ADK_ROOT="
for %%P in (
    "%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit"
    "%ProgramFiles%\Windows Kits\10\Assessment and Deployment Kit"
) do (
    if exist "%%~P\Windows Preinstallation Environment\copype.cmd" (
        set "ADK_ROOT=%%~P"
        goto :adk_found
    )
)

echo [ERROR] Windows ADK with WinPE add-on was not found.
echo.
echo  Please install BOTH of the following (links below), then re-run:
echo.
echo  1. Windows ADK:
echo     https://learn.microsoft.com/windows-hardware/get-started/adk-install
echo.
echo  2. Windows PE add-on for the ADK (on the same download page):
echo     Select "Download Windows PE add-on for the Windows ADK"
echo.
pause
exit /b 1

:adk_found
set "COPYPE=%ADK_ROOT%\Windows Preinstallation Environment\copype.cmd"
set "MAKEMEDIA=%ADK_ROOT%\Windows Preinstallation Environment\MakeWinPEMedia.cmd"
echo [OK] Windows ADK found: %ADK_ROOT%
echo.

:: ---- Resolve repo root (one level up from build\) -----------
set "SCRIPT_DIR=%~dp0"
:: Remove trailing backslash then go up one level
set "REPO_ROOT=%SCRIPT_DIR:~0,-1%"
for %%R in ("%REPO_ROOT%") do set "REPO_ROOT=%%~dpR"
set "REPO_ROOT=%REPO_ROOT:~0,-1%"
echo Repository root: %REPO_ROOT%
echo.

:: Sanity check: make sure repair scripts exist
if not exist "%REPO_ROOT%\winrepair_offline.bat" (
    echo [ERROR] winrepair_offline.bat not found at %REPO_ROOT%
    echo         Run this script from the build\ subfolder of the repository.
    pause
    exit /b 1
)
if not exist "%REPO_ROOT%\winpe\startnet.cmd" (
    echo [ERROR] winpe\startnet.cmd not found at %REPO_ROOT%\winpe\
    echo         Run this script from the build\ subfolder of the repository.
    pause
    exit /b 1
)

:: ---- Architecture selection ---------------------------------
echo Select WinPE architecture:
echo   [1] amd64   (64-bit Intel/AMD - recommended for most PCs)
echo   [2] arm64   (ARM 64-bit - Surface Pro X, Snapdragon PCs)
echo.
set /p "ARCH_SEL=Architecture [1]: "
if /i "%ARCH_SEL%"=="2" (
    set "ARCH=arm64"
) else (
    set "ARCH=amd64"
)
echo Using architecture: %ARCH%
echo.

:: ---- Working directory (always in %TEMP% to avoid UAC issues) -
set "WORK_DIR=%TEMP%\WinRepair_WinPE_%ARCH%"
set "MOUNT_DIR=%TEMP%\WinRepair_mount_%ARCH%"

:: ---- USB drive selection ------------------------------------
echo ============================================================
echo  SELECT USB DRIVE
echo ============================================================
echo.
echo  WARNING: ALL DATA on the selected USB drive will be ERASED.
echo           Back up anything important before continuing.
echo.
echo Removable drives detected:
echo.
wmic logicaldisk where "drivetype=2" get deviceid,volumename,size 2>nul
echo.
set /p "USB_LETTER=Enter the USB drive letter (letter only, e.g. E): "

:: Normalise input - strip colon, spaces, quotes
set "USB_LETTER=%USB_LETTER::=%"
set "USB_LETTER=%USB_LETTER: =%"
set "USB_LETTER=%USB_LETTER:"=%"

if not defined USB_LETTER (
    echo [ERROR] No drive letter entered.  Aborting.
    pause
    exit /b 1
)

:: Guard against wiping the system or boot drives
if /i "%USB_LETTER%"=="C" (
    echo [ERROR] C:\ is your system drive.  Aborting.
    pause
    exit /b 1
)
if /i "%USB_LETTER%"=="X" (
    echo [ERROR] X:\ is the WinPE ramdisk.  Aborting.
    pause
    exit /b 1
)
if not exist "%USB_LETTER%:\" (
    echo [ERROR] Drive %USB_LETTER%:\ does not exist.  Check the letter and try again.
    pause
    exit /b 1
)

echo.
echo  USB drive    : %USB_LETTER%:\
echo  Architecture : %ARCH%
echo  Work dir     : %WORK_DIR%
echo.
echo  ALL EXISTING DATA ON %USB_LETTER%:\ WILL BE ERASED.
echo.
set /p "CONFIRM=Type YES to confirm and continue: "
if /i not "%CONFIRM%"=="YES" (
    echo Cancelled.  No changes were made.
    pause
    exit /b 0
)
echo.

:: ============================================================
:: Step 1: Create WinPE working environment
:: ============================================================
echo [1/5] Creating WinPE working environment (%ARCH%)...
if exist "%WORK_DIR%" (
    echo       Removing previous working directory...
    rd /s /q "%WORK_DIR%" 2>nul
)
call "%COPYPE%" %ARCH% "%WORK_DIR%"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] copype.cmd failed (exit code %errorlevel%).
    echo         Ensure the WinPE add-on is installed for the ADK.
    pause
    exit /b 1
)
echo [OK] WinPE working environment created.
echo.

:: ============================================================
:: Step 2: Inject custom startnet.cmd into the WinPE image
:: ============================================================
echo [2/5] Injecting repair startup script into WinPE image...
if exist "%MOUNT_DIR%" rd /s /q "%MOUNT_DIR%" 2>nul
mkdir "%MOUNT_DIR%"

set "BOOT_WIM=%WORK_DIR%\media\sources\boot.wim"

:: Mount the WinPE boot image
Dism /Mount-Image /ImageFile:"%BOOT_WIM%" /Index:1 /MountDir:"%MOUNT_DIR%" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] DISM failed to mount boot.wim (exit code %errorlevel%).
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    pause
    exit /b 1
)

:: Replace the default startnet.cmd with our custom launcher
copy /y "%REPO_ROOT%\winpe\startnet.cmd" "%MOUNT_DIR%\Windows\System32\startnet.cmd" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Could not copy startnet.cmd into the WinPE image.
    Dism /Unmount-Image /MountDir:"%MOUNT_DIR%" /Discard >nul 2>&1
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    pause
    exit /b 1
)

:: Unmount and commit the changes
Dism /Unmount-Image /MountDir:"%MOUNT_DIR%" /Commit >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] DISM failed to commit WinPE image changes (exit code %errorlevel%).
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    pause
    exit /b 1
)
rd /s /q "%MOUNT_DIR%" 2>nul
echo [OK] WinPE startup script injected.
echo.

:: ============================================================
:: Step 3: Write WinPE to the USB drive (erases it)
:: ============================================================
echo [3/5] Writing WinPE to USB drive %USB_LETTER%:\...
echo       (This formats the USB drive - this will take a few minutes)
call "%MAKEMEDIA%" /UFD "%WORK_DIR%" %USB_LETTER%:
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] MakeWinPEMedia failed (exit code %errorlevel%).
    rd /s /q "%WORK_DIR%" 2>nul
    pause
    exit /b 1
)
echo [OK] WinPE written to USB.
echo.

:: ============================================================
:: Step 4: Copy repair scripts to the USB drive
:: ============================================================
echo [4/5] Copying repair scripts to USB drive...
if not exist "%USB_LETTER%:\winrepair" mkdir "%USB_LETTER%:\winrepair"

copy /y "%REPO_ROOT%\winrepair_offline.bat" "%USB_LETTER%:\winrepair\" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Could not copy winrepair_offline.bat to the USB drive.
    rd /s /q "%WORK_DIR%" 2>nul
    pause
    exit /b 1
)
copy /y "%REPO_ROOT%\winrepair.bat" "%USB_LETTER%:\winrepair\" >nul 2>&1

echo [OK] Repair scripts copied to %USB_LETTER%:\winrepair\
echo.

:: ============================================================
:: Step 5: Clean up temporary working directory
:: ============================================================
echo [5/5] Cleaning up temporary files...
rd /s /q "%WORK_DIR%" 2>nul
echo [OK] Temporary files removed.
echo.

:: ============================================================
:: Done
:: ============================================================
echo ============================================================
echo  SUCCESS  -  Bootable repair USB created on %USB_LETTER%:\
echo ============================================================
echo.
echo  How to use:
echo.
echo    1. Safely eject the USB drive from this PC.
echo    2. Insert it into the PC you want to repair.
echo    3. Boot from the USB drive:
echo         - Power on the PC and immediately press F12, F11, F10,
echo           ESC, or DEL (varies by manufacturer) to open the
echo           boot device selection menu.
echo         - Select the USB drive from the list.
echo    4. The repair tool starts automatically.
echo.
echo  The repair USB contains:
echo    %USB_LETTER%:\winrepair\winrepair_offline.bat  (offline repair^)
echo    %USB_LETTER%:\winrepair\winrepair.bat          (online repair, for reference^)
echo.
pause
exit /b 0

@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: build_winpe_iso.bat  -  Build a bootable WinPE repair ISO
::
:: Creates a .iso file that can be:
::   - Written to a USB drive with Rufus (https://rufus.ie)
::     in "ISO Image" mode
::   - Burned to a DVD via Windows Explorer
::     (right-click the .iso -> Burn disc image)
::   - Used in a virtual machine for testing
::
:: The ISO boots directly into the offline Windows repair tool
:: (winrepair_offline.bat).
::
:: Requirements
:: ------------
::   - Windows 10 or Windows 11 host PC
::   - Windows ADK (Assessment and Deployment Kit)
::       https://learn.microsoft.com/windows-hardware/get-started/adk-install
::   - Windows PE add-on for the ADK (same download page)
::   - Run as Administrator
::   - ~1 GB of free space in %TEMP% for the working directory
::
:: Output
:: ------
::   winrepair_amd64.iso  (or _arm64.iso)  in the repository root
::
:: Usage
:: -----
::   Right-click build_winpe_iso.bat -> Run as administrator
::   Follow the on-screen prompts.
:: ============================================================

:: ---- Admin check --------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] This script must be run as Administrator.
    echo         Right-click the script and choose "Run as administrator".
    echo.
    if not defined CI pause
    exit /b 1
)

echo.
echo ============================================================
echo  WinRepair  -  Build Bootable ISO
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
echo  Please install BOTH of the following, then re-run:
echo.
echo  1. Windows ADK:
echo     https://learn.microsoft.com/windows-hardware/get-started/adk-install
echo.
echo  2. Windows PE add-on for the ADK (on the same download page):
echo     Select "Download Windows PE add-on for the Windows ADK"
echo.
if not defined CI pause
exit /b 1

:adk_found
set "COPYPE=%ADK_ROOT%\Windows Preinstallation Environment\copype.cmd"
set "MAKEMEDIA=%ADK_ROOT%\Windows Preinstallation Environment\MakeWinPEMedia.cmd"
echo [OK] Windows ADK found: %ADK_ROOT%
echo.

:: ---- Resolve repo root (one level up from build\) -----------
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR:~0,-1%"
for %%R in ("%REPO_ROOT%") do set "REPO_ROOT=%%~dpR"
set "REPO_ROOT=%REPO_ROOT:~0,-1%"
echo Repository root: %REPO_ROOT%
echo.

:: Sanity checks
if not exist "%REPO_ROOT%\winrepair_offline.bat" (
    echo [ERROR] winrepair_offline.bat not found at %REPO_ROOT%
    echo         Run this script from the build\ subfolder of the repository.
    if not defined CI pause
    exit /b 1
)
if not exist "%REPO_ROOT%\winpe\startnet.cmd" (
    echo [ERROR] winpe\startnet.cmd not found at %REPO_ROOT%\winpe\
    echo         Run this script from the build\ subfolder of the repository.
    if not defined CI pause
    exit /b 1
)

:: ---- Architecture selection ---------------------------------
if defined CI (
    if /i "%WINREPAIR_ARCH%"=="arm64" (
        set "ARCH=arm64"
    ) else (
        set "ARCH=amd64"
    )
    echo CI mode detected. Using architecture: %ARCH%
) else (
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
)
echo.

:: ---- Output ISO path ----------------------------------------
set "ISO_OUT=%REPO_ROOT%\winrepair_%ARCH%.iso"
echo Output ISO: %ISO_OUT%
echo.

:: ---- Working directories ------------------------------------
set "WORK_DIR=%TEMP%\WinRepair_WinPE_%ARCH%_iso"
set "MOUNT_DIR=%TEMP%\WinRepair_mount_%ARCH%_iso"

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
    if not defined CI pause
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

Dism /Mount-Image /ImageFile:"%BOOT_WIM%" /Index:1 /MountDir:"%MOUNT_DIR%" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] DISM failed to mount boot.wim (exit code %errorlevel%).
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    if not defined CI pause
    exit /b 1
)

copy /y "%REPO_ROOT%\winpe\startnet.cmd" "%MOUNT_DIR%\Windows\System32\startnet.cmd" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Could not copy startnet.cmd into the WinPE image.
    Dism /Unmount-Image /MountDir:"%MOUNT_DIR%" /Discard >nul 2>&1
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    if not defined CI pause
    exit /b 1
)

Dism /Unmount-Image /MountDir:"%MOUNT_DIR%" /Commit >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] DISM failed to commit WinPE image changes (exit code %errorlevel%).
    rd /s /q "%MOUNT_DIR%" 2>nul
    rd /s /q "%WORK_DIR%" 2>nul
    if not defined CI pause
    exit /b 1
)
rd /s /q "%MOUNT_DIR%" 2>nul
echo [OK] WinPE startup script injected.
echo.

:: ============================================================
:: Step 3: Copy repair scripts into the ISO media folder
:: ============================================================
echo [3/5] Copying repair scripts into ISO media...
if not exist "%WORK_DIR%\media\winrepair" mkdir "%WORK_DIR%\media\winrepair"

copy /y "%REPO_ROOT%\winrepair_offline.bat" "%WORK_DIR%\media\winrepair\" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Could not copy winrepair_offline.bat into the ISO media.
    rd /s /q "%WORK_DIR%" 2>nul
    if not defined CI pause
    exit /b 1
)
copy /y "%REPO_ROOT%\winrepair.bat" "%WORK_DIR%\media\winrepair\" >nul 2>&1

echo [OK] Repair scripts added to ISO media.
echo.

:: ============================================================
:: Step 4: Build the ISO file
:: ============================================================
echo [4/5] Creating bootable ISO file...
echo       Output: %ISO_OUT%
echo.
call "%MAKEMEDIA%" /ISO "%WORK_DIR%" "%ISO_OUT%"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] MakeWinPEMedia /ISO failed (exit code %errorlevel%).
    rd /s /q "%WORK_DIR%" 2>nul
    if not defined CI pause
    exit /b 1
)
echo [OK] ISO created successfully.
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
echo  SUCCESS  -  Bootable ISO created:
echo  %ISO_OUT%
echo ============================================================
echo.
echo  How to use the ISO:
echo.
echo  Option A  -  Write to USB with Rufus (recommended^):
echo    1. Download Rufus from https://rufus.ie
echo    2. Open Rufus as Administrator
echo    3. Select your USB drive under "Device"
echo    4. Click SELECT and choose winrepair_%ARCH%.iso
echo    5. Leave "Partition scheme" as GPT and "File system" as FAT32
echo    6. Click START and accept the warning
echo.
echo  Option B  -  Burn to DVD:
echo    1. Right-click winrepair_%ARCH%.iso in Windows Explorer
echo    2. Choose "Burn disc image"
echo    3. Insert a blank DVD-R or DVD-RW and click Burn
echo.
echo  Option C  -  Virtual machine testing:
echo    1. Create a new VM in Hyper-V, VirtualBox, or VMware
echo    2. Attach winrepair_%ARCH%.iso as the boot CD-ROM
echo    3. Add a second virtual disk to use as the backup drive
echo    4. Boot the VM
echo.
echo  After booting from the USB or DVD, the repair tool starts automatically.
echo.
if not defined CI pause
exit /b 0

@echo off
setlocal EnableDelayedExpansion

:: ============================================================
:: build_winpe_usb.bat - Create Bootable Windows PE USB Drive
:: Creates a bootable USB drive with Windows PE and the
:: winrepair offline repair tools.
::
:: Requirements:
::   - Windows ADK (Assessment and Deployment Kit) installed
::   - Administrator privileges
::   - USB drive (8GB+ recommended)
:: ============================================================

title Build WinPE USB - Windows Repair Tool

:: ---- Admin check -------------------------------------------
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires Administrator privileges.
    echo         Right-click and select "Run as administrator".
    pause
    exit /b 1
)

cls
echo.
echo ============================================================
echo      Build Bootable Windows PE USB - Repair Tool
echo ============================================================
echo.

:: ---- Locate Windows ADK ------------------------------------
echo [1/8] Locating Windows ADK...

set "ADK_PATH=%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit"
if not exist "%ADK_PATH%\Windows Preinstallation Environment" (
    echo [ERROR] Windows ADK not found at:
    echo         %ADK_PATH%
    echo.
    echo         Please install Windows ADK from:
    echo         https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install
    echo.
    pause
    exit /b 1
)

set "WINPE_ROOT=%ADK_PATH%\Windows Preinstallation Environment"
set "COPYPE=%WINPE_ROOT%\copype.cmd"
set "MAKEWINPE=%WINPE_ROOT%\MakeWinPEMedia.cmd"

if not exist "%COPYPE%" (
    echo [ERROR] copype.cmd not found in ADK.
    echo         Ensure Windows PE add-on is installed.
    pause
    exit /b 1
)

echo [OK] Windows ADK found: %ADK_PATH%
echo.

:: ---- Set up workspace --------------------------------------
echo [2/8] Setting up workspace...

set "WORK_DIR=%~dp0..\build_temp"
set "WINPE_DIR=%WORK_DIR%\winpe_x64"
set "MOUNT_DIR=%WORK_DIR%\mount"

:: Clean up previous build
if exist "%WORK_DIR%" (
    echo Cleaning previous build...
    rmdir /s /q "%WORK_DIR%" 2>nul
    timeout /t 2 /nobreak >nul
)

mkdir "%WORK_DIR%" 2>nul
mkdir "%MOUNT_DIR%" 2>nul

echo [OK] Workspace created: %WORK_DIR%
echo.

:: ---- Create WinPE base using ADK ---------------------------
echo [3/8] Creating Windows PE base (this takes a moment)...

:: Run copype.cmd to create WinPE structure
pushd "%WINPE_ROOT%"
call "%COPYPE%" amd64 "%WINPE_DIR%"
popd

if not exist "%WINPE_DIR%\media\sources\boot.wim" (
    echo [ERROR] Failed to create WinPE base.
    echo         copype.cmd did not create boot.wim.
    pause
    exit /b 1
)

echo [OK] WinPE base created.
echo.

:: ---- Mount boot.wim ----------------------------------------
echo [4/8] Mounting boot.wim for customization...

set "BOOT_WIM=%WINPE_DIR%\media\sources\boot.wim"

DISM /Mount-Wim /WimFile:"%BOOT_WIM%" /Index:1 /MountDir:"%MOUNT_DIR%"
if %errorlevel% neq 0 (
    echo [ERROR] Failed to mount boot.wim
    pause
    exit /b 1
)

echo [OK] boot.wim mounted at: %MOUNT_DIR%
echo.

:: ---- Inject repair scripts ---------------------------------
echo [5/8] Injecting winrepair scripts into WinPE...

:: Copy winrepair_offline.bat to root of WinPE
copy /y "%~dp0..\winrepair_offline.bat" "%MOUNT_DIR%\winrepair_offline.bat" >nul
if %errorlevel% neq 0 (
    echo [WARN] Could not copy winrepair_offline.bat
) else (
    echo [OK] Injected: winrepair_offline.bat
)

:: Copy startnet.cmd to replace default WinPE startup
copy /y "%~dp0..\winpe\startnet.cmd" "%MOUNT_DIR%\Windows\System32\startnet.cmd" >nul
if %errorlevel% neq 0 (
    echo [WARN] Could not copy startnet.cmd
) else (
    echo [OK] Injected: startnet.cmd (WinPE startup)
)

echo.

:: ---- Optional: Add additional packages ---------------------
echo [6/8] Adding optional WinPE packages...

set "PACKAGES_DIR=%WINPE_ROOT%\amd64\WinPE_OCs"

:: Add PowerShell support (useful for advanced scripts)
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-WMI.cab" /Quiet
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-NetFX.cab" /Quiet
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-Scripting.cab" /Quiet
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-PowerShell.cab" /Quiet

:: Add storage and scripting support
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-StorageWMI.cab" /Quiet
DISM /Image:"%MOUNT_DIR%" /Add-Package /PackagePath:"%PACKAGES_DIR%\WinPE-DismCmdlets.cab" /Quiet

echo [OK] Optional packages added.
echo.

:: ---- Unmount and commit changes ----------------------------
echo [7/8] Unmounting and committing changes to boot.wim...

DISM /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Commit
if %errorlevel% neq 0 (
    echo [ERROR] Failed to unmount boot.wim
    echo         Attempting cleanup...
    DISM /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Discard
    pause
    exit /b 1
)

echo [OK] boot.wim updated and committed.
echo.

:: ---- Prompt for USB drive ----------------------------------
echo [8/8] Creating bootable USB drive...
echo.
echo ============================================================
echo                  USB DRIVE SELECTION
echo ============================================================
echo.
echo  WARNING: All data on the selected drive will be ERASED!
echo.
echo  Available drives:
echo.

:: List removable drives
echo list disk | diskpart | findstr /i "Disk"
echo.
echo  Please identify your USB drive number from the list above.
echo  Example: If your USB is "Disk 1", enter: 1
echo.
set /p "USB_DISK=Enter USB disk number (or Q to quit): "

if /i "%USB_DISK%"=="Q" (
    echo.
    echo Build cancelled. WinPE files remain at: %WINPE_DIR%\media
    echo You can manually create bootable media later.
    pause
    exit /b 0
)

:: Validate input is a number
echo %USB_DISK%| findstr /r "^[0-9][0-9]*$" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Invalid disk number.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo                    FINAL WARNING
echo ============================================================
echo.
echo  You selected: Disk %USB_DISK%
echo.
echo  ALL DATA ON DISK %USB_DISK% WILL BE PERMANENTLY ERASED!
echo.
set /p "FINAL_CONFIRM=Type YES to continue: "

if /i not "%FINAL_CONFIRM%"=="YES" (
    echo.
    echo Cancelled. No changes made.
    echo WinPE files remain at: %WINPE_DIR%\media
    pause
    exit /b 0
)

echo.
echo Creating bootable USB drive...
echo This will take several minutes...
echo.

:: Use MakeWinPEMedia.cmd to create bootable USB
pushd "%WINPE_ROOT%"
call "%MAKEWINPE%" /UFD "%WINPE_DIR%" %USB_DISK%:
set "RESULT=%errorlevel%"
popd

if %RESULT% neq 0 (
    echo.
    echo [ERROR] Failed to create bootable USB (error code %RESULT%).
    echo         Check that Disk %USB_DISK% is correct and accessible.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo                  BUILD COMPLETE
echo ============================================================
echo.
echo [OK] Bootable Windows PE USB drive created successfully!
echo.
echo  USB Drive: Disk %USB_DISK%
echo  Contains:
echo    - Windows PE (bootable)
echo    - winrepair_offline.bat (automatic repair)
echo    - startnet.cmd (boot menu)
echo.
echo  To use:
echo    1. Insert USB drive into target computer
echo    2. Boot from USB (may need to change BIOS/UEFI boot order)
echo    3. Select repair options from the menu
echo.
echo  Cleaning up temporary files...
rmdir /s /q "%WORK_DIR%" 2>nul

echo.
echo [OK] Done. USB is ready to use.
echo.
pause
exit /b 0

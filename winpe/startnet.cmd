@echo off
:: ============================================================
:: startnet.cmd  -  WinPE startup script
::
:: This file replaces the default startnet.cmd that ships with
:: WinPE.  It is injected into the boot.wim image by the build
:: scripts in the build\ folder.
::
:: Execution order inside WinPE:
::   winpeshl.exe → startnet.cmd → our repair script
::
:: What it does:
::   1. Runs wpeinit (loads drivers, PnP, network stack)
::   2. Waits briefly for drive-letter assignment to settle
::   3. Searches all drive letters for winrepair_offline.bat
::   4. Launches the offline repair tool automatically
::   5. Falls back to an interactive command prompt if the
::      script cannot be found (so the user is not stranded)
:: ============================================================

:: Initialise WinPE hardware and network stack
wpeinit

:: Brief pause so Windows PE finishes assigning drive letters
:: to attached disks before we start scanning them.
ping -n 4 127.0.0.1 >nul 2>&1

echo.
echo ============================================================
echo  WinPE Offline Repair  -  searching for repair scripts...
echo ============================================================
echo.

:: Search every possible drive letter except X: (the WinPE ramdisk).
:: MakeWinPEMedia copies the \winrepair\ folder to the root of the
:: boot media, so the USB or ISO will contain the scripts there.
for %%D in (B C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if exist "%%D:\winrepair\winrepair_offline.bat" (
        echo Found repair scripts on %%D:\
        cd /d "%%D:\winrepair"
        call winrepair_offline.bat
        goto :done
    )
)

:: ---- Fallback: scripts not found ----------------------------
echo.
echo  [ERROR] winrepair_offline.bat was not found on any attached drive.
echo.
echo  Possible causes:
echo    - The USB was not built with build\build_winpe_usb.bat
echo    - The USB drive has not been detected yet (wait 10 s, then reboot)
echo    - The repair script folder was accidentally deleted from the USB
echo.
echo  Dropping to an interactive command prompt.
echo  Type EXIT to reboot, or manually run:
echo    winrepair_offline.bat  (after navigating to the correct drive)
echo.
cmd /k

:done

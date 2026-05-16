# Building Bootable Windows PE Repair Media

This directory contains scripts to build bootable Windows PE media (USB or ISO) with the WinRepair offline repair tools.

## Prerequisites

### 1. Windows ADK (Assessment and Deployment Kit)

Download and install the Windows ADK from Microsoft:
- **Download:** https://docs.microsoft.com/en-us/windows-hardware/get-started/adk-install
- **Version:** Windows 10 ADK or Windows 11 ADK (both work for creating WinPE media)

**Required components:**
- Deployment Tools
- Windows Preinstallation Environment (Windows PE)

**Installation path:** The scripts expect ADK at:
```
%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit
```

### 2. Administrator Privileges

Both build scripts require administrator privileges to:
- Mount and modify WIM images using DISM
- Create bootable media
- Format drives (USB script only)

### 3. System Requirements

- Windows 10 or Windows 11 host system
- 10 GB free disk space (for temporary build files)
- USB drive 8GB+ (for USB build only)

## Building Bootable USB Drive

### Usage

1. **Insert USB drive** into your computer (8GB or larger recommended)
   - ⚠️ **WARNING:** All data on the USB will be erased!

2. **Right-click** `build_winpe_usb.bat` → **Run as administrator**

3. The script will:
   - Locate Windows ADK installation
   - Create WinPE base image
   - Mount boot.wim
   - Inject `winrepair_offline.bat` and `startnet.cmd`
   - Add PowerShell and storage management packages
   - Unmount and commit changes
   - Prompt you to select USB drive

4. **Select USB drive carefully:**
   - The script lists all disks (use disk number, e.g., "1" for Disk 1)
   - Verify the disk number matches your USB drive
   - Type `YES` to confirm and create bootable USB

5. **Result:** Bootable USB drive ready to use

### What Gets Created

```
USB Drive:\
├── Boot\           (Boot files)
├── EFI\            (UEFI boot files)
├── sources\
│   └── boot.wim    (Windows PE image with repair tools)
└── bootmgr         (Boot manager)
```

The repair scripts are embedded inside `boot.wim` and run automatically when WinPE boots.

## Building Bootable ISO

### Usage

1. **Right-click** `build_winpe_iso.bat` → **Run as administrator**

2. The script will:
   - Locate Windows ADK installation
   - Create WinPE base image
   - Mount boot.wim
   - Inject `winrepair_offline.bat` and `startnet.cmd`
   - Add PowerShell and storage management packages
   - Unmount and commit changes
   - Create bootable ISO file in `output/` directory

3. **Result:** ISO file created at:
   ```
   output\WinPE_Repair_YYYY-MM-DD.iso
   ```

### Using the ISO

**Option 1: Burn to DVD**
- Use Windows built-in disc burner or tools like ImgBurn
- Boot from DVD

**Option 2: Use in Virtual Machine**
- Mount ISO in VMware, VirtualBox, Hyper-V, etc.
- Boot VM from ISO

**Option 3: Create USB from ISO**
- Use Rufus (https://rufus.ie/) or similar tool
- Select ISO file and target USB drive
- Create bootable USB

## How the Build Process Works

### 1. Create WinPE Base
Uses Windows ADK's `copype.cmd` to create a standard WinPE x64 environment:
```batch
copype.cmd amd64 <destination>
```

### 2. Mount boot.wim
Uses DISM to mount the WinPE image for modification:
```batch
DISM /Mount-Wim /WimFile:boot.wim /Index:1 /MountDir:<mount_point>
```

### 3. Inject Repair Scripts
Copies our custom scripts into the mounted WinPE image:
- `winrepair_offline.bat` → Root of WinPE
- `startnet.cmd` → Replaces `Windows\System32\startnet.cmd` (runs at boot)

### 4. Add Optional Packages
Injects useful WinPE optional components:
- **WinPE-WMI.cab** - Windows Management Instrumentation
- **WinPE-NetFX.cab** - .NET Framework support
- **WinPE-Scripting.cab** - WSH scripting support
- **WinPE-PowerShell.cab** - PowerShell support
- **WinPE-StorageWMI.cab** - Storage management
- **WinPE-DismCmdlets.cab** - DISM PowerShell cmdlets

### 5. Unmount and Commit
Saves all changes back to boot.wim:
```batch
DISM /Unmount-Wim /MountDir:<mount_point> /Commit
```

### 6. Create Bootable Media
Uses ADK's `MakeWinPEMedia.cmd`:
- **For USB:** `/UFD` flag writes directly to USB drive
- **For ISO:** `/ISO` flag creates ISO file

## Troubleshooting

### Error: "Windows ADK not found"
- Install Windows ADK with the Windows PE add-on
- Verify installation at: `%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit`

### Error: "Failed to mount boot.wim"
- Ensure no other DISM operations are running
- Check if previous mount is stuck: `DISM /Cleanup-Wim`
- Restart and try again

### Error: "Failed to create bootable USB"
- Verify USB drive is connected and accessible
- Check disk number carefully (wrong disk = data loss!)
- Try a different USB port or USB drive
- Ensure USB has at least 2GB free space

### ISO Build Succeeds but ISO Won't Boot
- Verify BIOS/UEFI boot order (media must be first)
- Some older systems may not support UEFI boot from ISO
- Try using USB instead, or create USB from ISO using Rufus

### Build Process is Slow
- Normal - WinPE build can take 10-20 minutes
- Creating USB/ISO adds another 5-10 minutes
- Faster drives and SSDs help

## Advanced Customization

### Adding More Tools to WinPE

1. **Mount boot.wim manually:**
   ```batch
   DISM /Mount-Wim /WimFile:boot.wim /Index:1 /MountDir:C:\mount
   ```

2. **Copy additional tools:**
   ```batch
   copy mytool.exe C:\mount\Windows\System32\
   ```

3. **Unmount with commit:**
   ```batch
   DISM /Unmount-Wim /MountDir:C:\mount /Commit
   ```

### Adding Device Drivers

Inject drivers for specific hardware (RAID controllers, network adapters, etc.):
```batch
DISM /Image:C:\mount /Add-Driver /Driver:C:\drivers /Recurse
```

### Customizing startnet.cmd

Edit `winpe/startnet.cmd` before building to:
- Change default menu options
- Add custom commands
- Modify boot behavior
- Set environment variables

## File Structure After Build

```
build/
├── build_winpe_usb.bat       (This script - creates USB)
├── build_winpe_iso.bat       (This script - creates ISO)
├── README_BUILD.md           (This file)
└── ..\build_temp\            (Temporary, auto-deleted after build)
    └── winpe_x64\
        ├── media\            (WinPE files)
        └── mount\            (Mount point for boot.wim)

output/
└── WinPE_Repair_YYYY-MM-DD.iso  (Created by ISO build script)
```

## Next Steps

After creating bootable media:

1. **Test the media** in a virtual machine first (recommended)
2. **Boot from the media** on the target computer
3. **Select repair option** from the WinPE menu
4. **Follow on-screen prompts** to repair Windows

See the main README.md for usage instructions and repair capabilities.

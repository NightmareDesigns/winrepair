# winrepair

A comprehensive Windows repair toolkit with **two modes of operation**:
- **Online Mode** (`winrepair.bat`) - Repairs Windows from within a running Windows system
- **Offline Mode** (`winrepair_offline.bat`) - Repairs non-booting Windows from a bootable USB/ISO

Both modes back up your data first, then run repair tools in sequence. All output is logged to timestamped log files.

## Two Modes of Operation

### Online Mode - `winrepair.bat`
**Use when:** Windows boots normally but has issues (slow performance, corruption, errors)

**Runs from:** Within Windows (requires Administrator privileges)

**What it does:**
- Creates System Restore Point
- Backs up user files (Desktop, Documents, Downloads, etc.)
- Backs up Windows Registry
- Runs DISM and SFC to repair system files
- Schedules disk check
- Clears temporary files
- Resets network stack
- Triggers Windows Update scan

### Offline Mode - `winrepair_offline.bat`
**Use when:** Windows won't boot, gets stuck at boot screen, or boot errors occur

**Runs from:** Bootable USB/ISO (Windows PE environment)

**What it does:**
- Detects and mounts Windows installations
- Backs up Boot Configuration Data (BCD)
- Performs offline DISM and SFC repairs
- Repairs boot sectors (MBR/GPT)
- Rebuilds BCD (Boot Configuration Data)
- Restores Windows Boot Manager
- Supports both UEFI and Legacy BIOS
- Works with Windows 10 and 11 (all versions)

## Data Safety — Nothing Is Lost

Before touching anything on your system, the script creates **three independent safety nets**:

| Safety Step | What it creates | How to restore |
|---|---|---|
| **System Restore Point** | A Windows snapshot of system files and the registry | *Settings → System → Recovery → Open System Restore* |
| **User file backup** | A Robocopy of your Desktop, Documents, Downloads, Music, Pictures, and Videos | Browse to the backup folder and copy files back |
| **Registry backup** | Full export of `HKLM` and `HKCU` as `.reg` files | Double-click the `.reg` file to restore |

All three are created **before any repair step runs**, so there is always a way back.

## Online Mode Repair Steps

After the safety backups, the script runs the following in order:

| Step | Tool | What it fixes |
|------|------|---------------|
| 1 | **DISM** `RestoreHealth` | Repairs the Windows component store / image |
| 2 | **SFC** `scannow` | Scans and restores corrupted protected system files |
| 3 | **Check Disk** `chkdsk /f` | Schedules a filesystem error fix on next reboot (`/r` bad-sector scan is opt-in) |
| 4 | **Temp file cleanup** | Clears `%TEMP%`, Windows Temp, SoftwareDistribution downloads, and Prefetch |
| 5 | **Network stack reset** | Resets Winsock, TCP/IP, flushes DNS cache, and clears WinHTTP proxy |
| 6 | **Windows Update scan** | Triggers a Windows Update scan via `usoclient` |

> **Note:** Steps 1–2 (DISM and SFC) only repair Windows system files — they never touch your personal files.  
> Step 4 only clears system/app temporary folders — your Documents, Desktop, Pictures, etc. are never deleted.

## Requirements

### Online Mode Requirements

- Windows 10 or Windows 11
- **Administrator privileges** (right-click → *Run as administrator*)
- A second drive or folder with enough free space for the user-file backup
- Internet connection recommended for DISM (downloads repair files from Windows Update if needed)

### Offline Mode Requirements (Bootable Media)

- Windows 10 ADK or Windows 11 ADK (for building bootable media)
- USB drive 8GB+ or blank DVD (for bootable media)
- **Administrator privileges** on the computer used to build the media
- Target computer with Windows 10 or Windows 11 installed (any build)

## Online Mode Usage

1. Download or clone this repository.
2. Right-click **`winrepair.bat`** and choose **Run as administrator**.
3. Read the safety warning and press **Y** to continue.
4. Enter a backup destination path (e.g. `D:\WinRepairBackup`). If you leave it blank, a `backup\` folder is created next to the script.
5. Wait for the safety backups to complete (user files may take a while depending on size).
6. Wait for DISM and SFC to finish — each can take 10–30 minutes.
7. When prompted for Check Disk, choose **N** (default, fast) for filesystem errors only, or **Y** for a full bad-sector scan (1–8 hours).
8. When prompted, choose **Y** to reboot (recommended) or **N** to reboot later.

## Offline Mode Usage (For Non-Booting Windows)

### Step 1: Build Bootable Media

**Before you can use offline mode, you must create bootable USB or ISO media.**

#### Option A: Create Bootable USB

1. On a **working Windows computer**, download or clone this repository
2. Insert a USB drive (8GB+ recommended) — **all data will be erased!**
3. Right-click `build/build_winpe_usb.bat` → **Run as administrator**
4. Follow the prompts to select your USB drive
5. Wait for build to complete (10-20 minutes)

#### Option B: Create Bootable ISO

1. On a **working Windows computer**, download or clone this repository
2. Right-click `build/build_winpe_iso.bat` → **Run as administrator**
3. Wait for build to complete (10-20 minutes)
4. Find ISO in `output/` directory
5. Burn to DVD or create USB using Rufus (https://rufus.ie/)

**Detailed build instructions:** See `build/README_BUILD.md`

### Step 2: Boot from Media

1. Insert bootable USB drive or DVD into the **non-booting computer**
2. Restart the computer
3. **Enter BIOS/UEFI** (usually press F2, F12, Del, or Esc during startup)
4. Change boot order to boot from USB/DVD first
5. Save and exit BIOS
6. Computer will boot into Windows PE

### Step 3: Run Repairs

1. Windows PE will boot and show a **menu** with options:
   ```
   [1] Run Automatic Offline Repair (Recommended)
   [2] Open Command Prompt (Manual Repair)
   [3] Reboot Computer
   [4] Power Off Computer
   ```

2. **Select option 1** for automatic repair

3. The script will:
   - Scan all drives for Windows installations
   - Display found installations (if multiple)
   - Ask you to confirm which Windows to repair

4. **Confirm repairs** when prompted

5. Wait for repairs to complete:
   - BCD backup (instant)
   - Offline DISM repair (15-45 minutes)
   - Offline SFC scan (15-30 minutes)
   - Boot sector repair (1-2 minutes)
   - BCD rebuild (1-2 minutes)
   - Boot Manager restoration (instant)

6. **Remove USB/DVD** when complete

7. **Restart** the computer

8. Windows should now boot normally

### Step 4: If Windows Still Won't Boot

If Windows still fails to boot after offline repair:

1. **Check the log file** on the WinPE USB at `X:\RepairLogs\`
2. **Try Safe Mode**: Repeatedly press F8 during boot to access Advanced Boot Options
3. **Restore BCD backup**: Boot back to WinPE and copy BCD backup files back from logs folder
4. **Try manual repair**: Select option 2 from WinPE menu for command prompt access
5. **Consider reinstallation**: If all else fails, backup data and perform clean Windows install

## Output Structure

### Online Mode Output

```
<backup destination>\
└── winrepair_<date>_<time>\
    ├── UserFiles\
    │   ├── Desktop\
    │   ├── Documents\
    │   ├── Downloads\
    │   ├── Music\
    │   ├── Pictures\
    │   └── Videos\
    └── Registry\
        ├── HKLM.reg
        └── HKCU.reg

<script folder>\
└── logs\
    └── winrepair_<date>_<time>.log
```

### Offline Mode Output

```
X:\RepairLogs\  (on WinPE USB/media)
├── winrepair_offline_<date>_<time>.log
└── BCD_backup_<date>_<time>\
    ├── BCD_Legacy  (if present)
    ├── BCD_UEFI    (if present)
    └── BCD_export.bcd
```

## Restoring Your Files

If anything goes wrong after running the script you have three options:

1. **System Restore** — *Settings → System → Recovery → Open System Restore* and pick the restore point labelled *WinRepair Script - pre-repair*.
2. **File restore** — browse to `<backup destination>\winrepair_<date>_<time>\UserFiles\` and copy the files you need back to their original locations.
3. **Registry restore** — double-click `HKLM.reg` or `HKCU.reg` in the `Registry\` folder and confirm the import.

## Example Log Output

```
[04/10/2026 13:32:00.00] Windows Automatic Repair Script started at 04/10/2026 13:32:00.00
[04/10/2026 13:32:05.00] --- SAFETY A: Create System Restore Point ---
[04/10/2026 13:32:18.00] [OK] System Restore Point created successfully.
[04/10/2026 13:32:18.00] --- SAFETY B: Back Up User Files ---
[04/10/2026 13:35:42.00] [OK] Documents backed up to D:\WinRepairBackup\winrepair_..\UserFiles\Documents
[04/10/2026 13:38:10.00] [OK] User file backup complete.
[04/10/2026 13:38:10.00] --- SAFETY C: Back Up Windows Registry ---
[04/10/2026 13:39:55.00] [OK] HKLM exported.
[04/10/2026 13:39:58.00] [OK] HKCU exported.
[04/10/2026 13:39:58.00] --- STEP 1: DISM - Restore Windows Image Health ---
[04/10/2026 13:52:10.00] [OK] DISM RestoreHealth completed successfully.
...
```


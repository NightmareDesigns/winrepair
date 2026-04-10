# winrepair

A Windows automatic repair batch script that **backs up your files first**, then runs common Windows repair tools in sequence. All output is logged to a timestamped log file.

## Data Safety — Nothing Is Lost

Before touching anything on your system, the script creates **three independent safety nets**:

| Safety Step | What it creates | How to restore |
|---|---|---|
| **System Restore Point** | A Windows snapshot of system files and the registry | *Settings → System → Recovery → Open System Restore* |
| **User file backup** | A Robocopy of your Desktop, Documents, Downloads, Music, Pictures, and Videos | Browse to the backup folder and copy files back |
| **Registry backup** | Full export of `HKLM` and `HKCU` as `.reg` files | Double-click the `.reg` file to restore |

All three are created **before any repair step runs**, so there is always a way back.

## Repair Steps

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

- Windows 10 or Windows 11
- **Administrator privileges** (right-click → *Run as administrator*)
- A second drive or folder with enough free space for the user-file backup
- Internet connection recommended for DISM (downloads repair files from Windows Update if needed)

## Usage

1. Download or clone this repository.
2. Right-click **`winrepair.bat`** and choose **Run as administrator**.
3. Read the safety warning and press **Y** to continue.
4. Enter a backup destination path (e.g. `D:\WinRepairBackup`). If you leave it blank, a `backup\` folder is created next to the script.
5. Wait for the safety backups to complete (user files may take a while depending on size).
6. Wait for DISM and SFC to finish — each can take 10–30 minutes.
7. When prompted for Check Disk, choose **N** (default, fast) for filesystem errors only, or **Y** for a full bad-sector scan (1–8 hours).
8. When prompted, choose **Y** to reboot (recommended) or **N** to reboot later.

## Output Structure

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


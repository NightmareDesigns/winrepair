# winrepair

A two-mode Windows repair toolkit that keeps your personal data safe.

| Mode | When to use | Script |
|------|-------------|--------|
| **Online** | Windows still boots — run repairs from inside your live session | `winrepair.bat` |
| **Offline** | Windows will not boot, or you want the deepest possible repair | Boot from USB/ISO → `winrepair_offline.bat` |

Both modes back up your personal files **before** making any change.

---

## Contents

```
winrepair\
├── winrepair.bat              Online repair (run inside Windows as Administrator)
├── winrepair_offline.bat      Offline repair (auto-launched from the bootable USB/ISO)
├── winpe\
│   └── startnet.cmd           WinPE startup hook — injected into the boot image by the build scripts
└── build\
    ├── build_winpe_usb.bat    Build a bootable repair USB drive
    └── build_winpe_iso.bat    Build a bootable repair ISO (burn to DVD or flash with Rufus)
```

---

## Quick Start — Online Mode (Windows boots normally)

1. Download or clone this repository.
2. Right-click **`winrepair.bat`** → *Run as administrator*.
3. Read the safety warning and press **Y**.
4. Enter a backup destination (e.g. `D:\WinRepairBackup`).  Leave blank to use `backup\` next to the script.
5. Wait for DISM and SFC to finish (10–30 min each).
6. Reboot when prompted.

---

## Quick Start — Offline Mode (Windows will not boot)

### Step 1 — Create the bootable repair USB

Do this on a **working Windows PC** (not the broken one).

**Prerequisites — install both on the working PC:**
- [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install)
- Windows PE add-on for the ADK (same download page — click *"Download Windows PE add-on for the Windows ADK"*)

**Build the USB:**
1. Plug in a USB flash drive (**2 GB minimum — it will be erased**).
2. Right-click **`build\build_winpe_usb.bat`** → *Run as administrator*.
3. Follow the prompts: choose `amd64` architecture (for most PCs), confirm the USB drive letter, type `YES`.
4. The script creates a bootable WinPE drive with the repair tools embedded.

> **Want an ISO instead?** Run **`build\build_winpe_iso.bat`** — it produces `winrepair_amd64.iso`.  
> Flash it to USB with [Rufus](https://rufus.ie) (ISO Image mode) or burn it to a DVD.

### Build ISO in GitHub Actions

You can also build the ISO from this repository in GitHub:

1. Open the **Actions** tab.
2. Run **Build WinPE ISO**.
3. Choose `amd64` or `arm64`.
4. Download the generated ISO from the workflow artifacts.

---

### Step 2 — Boot the broken PC from the USB

1. Insert the repair USB into the broken PC.
2. Power on and enter the **boot device selection menu**:
   - Common keys: **F12**, **F11**, **F10**, **ESC**, **DEL** (varies by manufacturer — watch the POST screen).
   - On Surface devices: hold the **Volume Down** button while pressing the power button.
3. Select the USB drive from the menu.
4. WinPE loads (blue screen with no icons — this is normal).

---

### Step 3 — The repair tool starts automatically

The script auto-launches after WinPE boots.  It will:

1. **Detect** all Windows installations on attached drives and list them.
2. **Ask you to select** which installation to repair (or auto-select if only one is found).
3. **Ask you to select** a backup destination drive (external USB, second disk — *not* the drive being repaired).
4. Create safety backups **before any repair step runs**.
5. Run all repair steps in sequence.
6. Offer to reboot when done.

---

## Data Safety — Nothing Is Lost

### Online mode

| Safety step | What is created | How to restore |
|-------------|-----------------|----------------|
| **System Restore Point** | Windows snapshot of system files + registry | *Settings → System → Recovery → Open System Restore* |
| **User file backup** | Robocopy of Desktop, Documents, Downloads, Music, Pictures, Videos | Browse backup folder, copy files back |
| **Registry backup** | Full export of `HKLM` and `HKCU` as `.reg` files | Double-click the `.reg` file |

### Offline mode

| Safety step | What is created | How to restore |
|-------------|-----------------|----------------|
| **User profile backup** | Robocopy of all non-system user profiles from the offline drive | Copy files back once Windows boots |
| **Registry hive backup** | Raw copy of `SOFTWARE`, `SYSTEM`, `SAM`, `SECURITY`, `DEFAULT` from `Windows\System32\config` | Load in regedit or use for forensic recovery |

All backups are created **before the first repair step runs**.

> **Your Documents, Desktop, Pictures, Music, Videos, and Downloads are never deleted or modified by either script.**

---

## Repair Steps

### Online mode (`winrepair.bat`)

| # | Tool | What it does |
|---|------|--------------|
| A | System Restore Point | Safety snapshot before anything changes |
| B | User file backup | Robocopy of personal folders to backup drive |
| C | Registry export | Full `.reg` backup of HKLM and HKCU |
| 1 | **DISM** `RestoreHealth` | Repairs the Windows component store / image |
| 2 | **SFC** `scannow` | Scans and restores corrupted protected system files |
| 3 | **CHKDSK** `/f` | Schedules a filesystem check (runs on next reboot) |
| 4 | Temp cleanup | Clears `%TEMP%`, Windows Temp, SoftwareDistribution, Prefetch |
| 5 | Network reset | Resets Winsock, TCP/IP, DNS cache, WinHTTP proxy |
| 6 | Windows Update scan | Triggers a Windows Update scan via `usoclient` |

### Offline mode (`winrepair_offline.bat`)

| # | Tool | What it does |
|---|------|--------------|
| A | User profile backup | Robocopy of all user profiles from offline drive |
| B | Registry hive backup | Raw copy of hive files from `Windows\System32\config` |
| 1 | **DISM** `/Image:` | Repairs the offline Windows image (no reboot needed) |
| 2 | **SFC** `/offwindir:` | Scans and repairs offline system files |
| 3 | **CHKDSK** `/f` (or `/r`) | Fixes filesystem errors immediately (drive is not in use) |
| 4 | **bootrec** | Rebuilds MBR, boot sector, and BCD — fixes most boot failures |
| 5 | Temp cleanup | Clears Windows Temp, SoftwareDistribution, Prefetch, and user Temp |

---

## Output Structure

### Online mode

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

<script folder>\logs\winrepair_<date>_<time>.log
```

### Offline mode

```
<backup drive>\WinRepairBackup\
└── winrepair_offline_<date>_<time>\
    ├── Users\
    │   ├── <username1>\   (full profile copy, excluding AppData\Local\Temp)
    │   └── <username2>\
    ├── Registry\
    │   ├── SOFTWARE
    │   ├── SYSTEM
    │   ├── SAM
    │   ├── SECURITY
    │   └── DEFAULT
    └── Logs\
        └── winrepair_offline_<date>_<time>.log
```

---

## Restoring Your Files

### Online mode — three ways back

1. **System Restore** — *Settings → System → Recovery → Open System Restore* → pick *WinRepair Script - pre-repair*.
2. **File restore** — browse to `<backup>\winrepair_<date>_<time>\UserFiles\` and copy files back.
3. **Registry restore** — double-click `HKLM.reg` or `HKCU.reg` and confirm the import.

### Offline mode — two ways back

1. **File restore** — after Windows boots, copy folders from `<backup drive>\WinRepairBackup\...\Users\<username>` back to `C:\Users\<username>`.
2. **Registry restore** — in the WinPE command prompt, load the hive files with `reg load` or take them to a working PC and use `regedit`.

---

## Requirements

### Online mode (`winrepair.bat`)

- Windows 10 or Windows 11
- Administrator privileges (right-click → *Run as administrator*)
- A second drive or folder with enough free space for the user-file backup
- Internet connection recommended (DISM downloads repair files from Windows Update if needed)

### Offline mode — repair USB build

- A working Windows 10 or Windows 11 PC to build the USB
- [Windows ADK](https://learn.microsoft.com/windows-hardware/get-started/adk-install) + Windows PE add-on
- Administrator privileges on the build PC
- A USB flash drive with at least 2 GB capacity (erased during build)

### Offline mode — running the repair

- A second drive or USB stick for backups (not the drive being repaired)
- The broken PC must be able to boot from USB (UEFI or BIOS both supported)

---

## Troubleshooting

| Symptom | Likely cause | What to try |
|---------|-------------|-------------|
| DISM offline fails with errors | Severe image corruption or no network in WinPE | Re-run DISM with `/Source:wim:D:\sources\install.wim:1 /LimitAccess` where `D:` is a Windows 11 installation USB |
| `bootrec /fixboot` → "Access is denied" | UEFI/GPT system (expected) | Ignore this; `bootrec /rebuildbcd` is the important step on UEFI |
| Windows still won't boot after repair | BCD is missing or EFI partition is corrupt | Run `bcdboot C:\Windows /s S: /f UEFI` where `S:` is the EFI System Partition (use `diskpart` to find it) |
| No Windows installation detected | Drive not connected, or WinPE enumeration still in progress | Wait 30 s, close the script, and run `winrepair_offline.bat` again from `D:\winrepair\` |
| USB drive not detected by BIOS | Secure Boot or Fast Boot blocking USB | Disable Fast Boot and/or Secure Boot temporarily in UEFI firmware settings |

---

## Test Matrix

The following scenarios have been designed for validation.  
Personal data must remain intact across all runs.

| Scenario | Condition | Expected outcome |
|----------|-----------|-----------------|
| Healthy Windows 11 (online) | All files intact | No errors; all repair tools report success |
| Corrupted system files (online) | `sfc /verifyonly` reports errors before run | SFC and DISM restore corrupted files; no personal data affected |
| Corrupted system files (offline) | ntoskrnl.exe or DLL replaced with zeroed file | Offline DISM + SFC restore the file; Windows boots after repair |
| Unbootable — BCD missing | `bcdedit /delete {bootmgr}` | `bootrec /rebuildbcd` recreates BCD; Windows boots |
| Unbootable — MBR corrupt (MBR/BIOS system) | MBR overwritten with zeros | `bootrec /fixmbr` restores MBR; Windows boots |
| Disk errors | `chkdsk C: /scan` reports errors | CHKDSK offline fixes errors immediately; filesystem clean |
| Multiple Windows installs | Two Windows partitions on one disk | Script lists both; user selects one; only selected partition is repaired |
| Dual-drive setup | Windows on C:, backup on E: | User profiles backed up to E:; repair runs on C:; E: untouched |
| Large profile (50 GB+) | User has 50 GB of documents | Robocopy completes without timeout; no files missing from backup |

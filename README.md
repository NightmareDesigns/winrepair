# winrepair

A Windows automatic repair batch script that runs common Windows repair tools in sequence and logs all output to a timestamped log file.

## What It Does

The script executes the following repair steps in order:

| Step | Tool | What it fixes |
|------|------|---------------|
| 1 | **DISM** `RestoreHealth` | Repairs the Windows component store / image |
| 2 | **SFC** `scannow` | Scans and repairs protected system files |
| 3 | **Check Disk** `chkdsk /f /r` | Schedules a disk error and bad-sector check on next reboot |
| 4 | **Temp file cleanup** | Clears `%TEMP%`, Windows Temp, SoftwareDistribution downloads, and Prefetch |
| 5 | **Network stack reset** | Resets Winsock, TCP/IP, flushes DNS cache, and clears WinHTTP proxy |
| 6 | **Windows Update scan** | Triggers a Windows Update scan via `usoclient` |

After all steps complete, the script offers to reboot immediately so that Check Disk and any pending Windows Updates can finish.

## Requirements

- Windows 10 or Windows 11
- **Administrator privileges** (right-click → *Run as administrator*)
- Internet connection recommended for DISM (it downloads repair files from Windows Update if needed)

## Usage

1. Download or clone this repository.
2. Right-click **`winrepair.bat`** and choose **Run as administrator**.
3. Wait for all steps to complete — DISM and SFC can each take 10–30 minutes.
4. When prompted, choose **Y** to reboot (recommended) or **N** to reboot later.

A full log is saved to the `logs\` folder next to the script:

```
logs\winrepair_<date>_<time>.log
```

## Example Log Output

```
[04/10/2026 13:32:00.00] Windows Automatic Repair Script started at 04/10/2026 13:32:00.00
[04/10/2026 13:32:00.00] --- STEP 1: DISM - Restore Windows Image Health ---
[04/10/2026 13:45:12.00] [OK] DISM RestoreHealth completed successfully.
[04/10/2026 13:45:12.00] --- STEP 2: SFC - System File Checker ---
[04/10/2026 13:52:33.00] [OK] SFC scan completed successfully.
...
```

## Notes

- **Check Disk** is scheduled, not run immediately, because it requires exclusive access to the system drive. It will run automatically on the next reboot.
- The **DISM** step requires an internet connection (or a mounted Windows ISO) to download repair files when the local image is corrupted.
- The network reset in Step 5 may temporarily disconnect active network sessions.

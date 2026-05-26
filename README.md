# Scrub

[![Português](https://img.shields.io/badge/lang-Portugu%C3%AAs-green)](README.pt.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.md)

> Windows disk maintenance tool — safe by default, powerful when you need it.

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-blue?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Version](https://img.shields.io/badge/version-1.0.0-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

Scrub is a PowerShell-based maintenance tool for Windows with an interactive TUI menu.  
It runs in **dry-run mode by default** — nothing is deleted without explicit confirmation.

---

## Features

- **Smart routine** — runs only what's overdue based on configurable schedules
- **Health Score** — 0–100 score tracking disk space, SMART status, event log errors, drivers, and pending updates
- **22 modules** — temp cleaner, browser cache, large file finder, duplicate finder, startup manager, system repair, and more
- **Interactive folder analyzer** — visual disk space explorer
- **History & charts** — sparkline progress tracking across runs
- **Bilingual** — English and Portuguese UI
- **No admin required** for most operations; no external dependencies; no telemetry

---

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or higher (built-in on Windows)

---

## Installation

Download the latest [release](https://github.com/BrMeloCC/scrub/releases), extract to any folder, then run:

```powershell
.\Install-Scrub.ps1
```

The installer (no admin required):
1. Creates `scrub.cmd` launcher in the tool directory
2. Adds the directory to your user PATH (`HKCU\Environment`)
3. Registers the PowerShell module via junction
4. Creates a Start Menu shortcut

Open a **new terminal** after installing, then just type `scrub`.

**To uninstall:**

```powershell
.\Install-Scrub.ps1 -Uninstall
```

> The tool directory is **not deleted** on uninstall — only shortcuts and PATH entries are removed.

---

## Usage

### Interactive menu (default)

```
scrub
```

### CLI flags (no menu)

```powershell
.\Run-Scrub.ps1 -NoMenu             # silent dry-run, generates report
.\Run-Scrub.ps1 -Live               # live mode (asks confirmation before deleting)
.\Run-Scrub.ps1 -ReportOnly         # full analysis, opens HTML report
.\Run-Scrub.ps1 -Watch              # real-time disk monitor (Ctrl+C to exit)
.\Run-Scrub.ps1 -Watch -WatchInterval 60
.\Run-Scrub.ps1 -ConfigPath C:\my.json
```

### PowerShell module

```powershell
Import-Module .\scrub.psd1

Invoke-Scrub                   # dry-run
Invoke-Scrub -DryRun:$false    # live mode
Get-ScrubReport                # analysis only
New-ScrubConfig                # reset config to defaults
```

---

## Menu

```
  Score: 82  ↑   Preset: Custom   P = switch

  [1]  Smart routine          runs only what is needed, estimates time
  [2]  Full routine           dry-run -- analyzes, deletes nothing
  [3]  Full routine LIVE      actually deletes (asks for confirmation)
  [4]  Specific routine       choose which modules to run

  [5]  Diagnose               disk, health, logs and startup (read-only)
  [6]  Manage startup         enable/disable startup entries
  [7]  Folder analyzer        interactive disk usage explorer
  [8]  History                progress charts and score over time

  [9]  Configure modules      enable/disable, frequency and estimated time
  [A]  Schedule daily run
  [B]  Uninstall
  [I]  Idioma / Language      switch between Portuguese and English
  [0]  Exit
```

### Health Score

Displayed at the top of the menu. Calculated after each run:

| Dimension | Points |
|---|---|
| Free space on main drive | 25 |
| Disk health (SMART) | 20 |
| Event Log errors (last 24h) | 20 |
| Pending reboot | 10 |
| Pending Windows Updates | 15 |
| Problematic drivers | 10 |

Trend arrow (↑↓→) shows change from the previous measurement. History stored in `health_history.json` (last 90 measurements).

---

## Modules

| Module | Default | Description |
|---|---|---|
| `temp_cleaner` | ✅ | Cleans `%TEMP%` and `C:\Windows\Temp` |
| `recycle_bin` | ✅ | Removes old items from Recycle Bin |
| `disk_report` | ✅ | Disk usage report per drive (always active) |
| `health_check` | ✅ | Disk health via SMART/WMI (always active) |
| `driver_audit` | ✅ | Devices with errors; PnP rescan in live mode |
| `browser_cache` | ✅ | Chrome, Edge, and Firefox cache |
| `large_file_finder` | ✅ | Lists files above threshold (report only) |
| `downloads_audit` | ✅ | Old files in Downloads folder (report only) |
| `event_log_scan` | ✅ | Critical/Error events in System and Application logs |
| `startup_audit` | ✅ | Programs and tasks that start with Windows |
| `system_log_clean` | ✅ | CBS logs, minidumps, WER reports, MEMORY.DMP |
| `node_cache_clean` | ✅ | npm, yarn, and pnpm caches |
| `restore_point` | ✅ | Creates a restore point before live cleanup |
| `disk_optimize` | ✅ | TRIM on SSDs, defrag on HDDs |
| `windows_update_check` | ✅ | Checks and triggers pending Windows Updates |
| `software_audit` | ✅ | Recently installed software (report only) |
| `duplicate_finder` | ❌ | SHA256 duplicate finder (slow; set `scan_paths` first) |
| `hiberfil_cleaner` | ❌ | Disables hibernation and Fast Startup (permanent) |
| `system_repair` | ❌ | SFC + DISM (30–60 min; requires admin) |
| `windows_update_cache` | ❌ | Clears Windows Update cache (requires admin) |
| `dev_project_clean` | ❌ | Build/deps folders in inactive dev projects |

---

## Configuration

Edit `config.json` to customize behavior. Key options:

```json
{
  "dry_run": true,
  "size_threshold_mb": 100,
  "alert_disk_usage_pct": 85,
  "min_age_days": {
    "temp_files": 3,
    "recycle_bin": 30,
    "browser_cache": 7
  },
  "browser_cache": { "chrome": true, "edge": true, "firefox": true },
  "dev_cleanup": {
    "scan_paths": ["C:\\DEV"],
    "min_age_days": 30,
    "targets": ["node_modules", ".venv", "target", "dist", "build", ...]
  },
  "schedule": {
    "temp_cleaner": { "freq_days": 1, "est_secs": 10 },
    "browser_cache": { "freq_days": 7, "est_secs": 15 }
  }
}
```

---

## Security

- Dry-run is the default in every module
- Live mode requires explicit text confirmation (`yes` / `sim`) before deleting
- All cleanup paths are hardcoded whitelists — config cannot point to arbitrary folders
- `dev_project_clean` only deletes folders matching the `targets` list, never the project root
- Never touches: Documents, Desktop, Pictures, Music, Videos, OneDrive
- Admin-required operations are detected and reported — never fail silently
- Install modifies only the **user** PATH (`HKCU`) — never the system PATH
- No telemetry, no network connections

---

## Project Structure

```
scrub/
├── Run-Scrub.ps1          # Entry point / interactive menu
├── Install-Scrub.ps1      # User-level installer / uninstaller
├── scrub.psm1             # Main module / orchestrator
├── scrub.psd1             # Module manifest
├── scrub.cmd              # Terminal launcher
├── config.json            # Default configuration
├── strings/
│   ├── en.ps1             # English strings
│   └── pt.ps1             # Portuguese strings
└── modules/               # 22 independent PS1 modules
```

---

## License

MIT — free to use, modify, and distribute.

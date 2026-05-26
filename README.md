<div align="center">

[![Português](https://img.shields.io/badge/lang-Portugu%C3%AAs-green)](README.pt.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.md)

# Scrub

**Windows disk maintenance — safe by default, powerful when you need it.**

[![Platform](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)](https://github.com/BrMeloCC/scrub)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-012456?logo=powershell&logoColor=white)](https://github.com/BrMeloCC/scrub)
[![Version](https://img.shields.io/github/v/release/BrMeloCC/scrub?color=brightgreen&label=release)](https://github.com/BrMeloCC/scrub/releases)
[![License](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

</div>

---

Scrub is a PowerShell-based maintenance tool for Windows with an interactive TUI menu.  
It runs in **dry-run mode by default** — nothing is deleted without explicit confirmation.

```
scrub              # dry run — analyzes, deletes nothing
scrub -Live        # live mode — asks confirmation before deleting
scrub -ReportOnly  # analysis only, opens HTML report
```

---

## Quick Start

**1. Download** the latest [release](https://github.com/BrMeloCC/scrub/releases) and extract it anywhere.

**2. Install** by double-clicking `setup.cmd` — no admin required.

Open a **new terminal** after installing, then:

```
scrub              # dry run — analyzes, deletes nothing
scrub -Live        # live mode — asks confirmation before deleting
scrub -ReportOnly  # analysis only, opens HTML report
```

To uninstall: `setup.cmd -Uninstall`

> **Run without installing:** double-click `scrub.cmd` directly, or:
> ```powershell
> .\Run-Scrub.ps1 -NoMenu
> .\Run-Scrub.ps1 -Live
> ```

---

## Features

| | |
|---|---|
| Smart routine | Runs only overdue modules based on configurable schedules |
| Health Score | 0–100 score: disk space, SMART, event log, drivers, pending updates |
| 22 modules | Temp, browser cache, duplicates, startup manager, system repair and more |
| Folder analyzer | Interactive visual disk space explorer |
| History & charts | Sparkline progress tracking across runs |
| Bilingual | English and Portuguese UI |
| Safe | No admin needed for most ops · No telemetry · No network |

---

## Menu

```
  Score: 82 ↑   Preset: Custom   P = switch

  [1]  Smart routine          runs only what is needed, estimates time
  [2]  Full routine           dry-run — analyzes, deletes nothing
  [3]  Full routine LIVE      actually deletes (asks for confirmation)
  [4]  Specific routine       choose which modules to run

  [5]  Diagnose               health-focused scan — disk, SMART, logs, drivers (read-only)
  [6]  Manage startup         enable/disable startup entries
  [7]  Folder analyzer        interactive disk usage explorer
  [8]  History                progress charts and score over time

  [9]  Configure modules      enable/disable with last-run info and estimated time
  [A]  Schedule daily run
  [B]  Uninstall
  [I]  Idioma / Language      switch between Portuguese and English
  [0]  Exit
```

### Preset manager

Press `P` from the main menu to cycle through presets: **Custom**, **Diagnostics**, and **Cleanup**. Each preset activates a predefined set of modules.

From **Configure modules [9]**, press `p` to open the preset manager where you can:

- Save the current module selection as a named preset
- Load or delete previously saved user presets

### Diagnose [5]

Runs a read-only health scan in roughly 30 seconds. Only health-focused modules execute: disk space, SMART status, event log errors, driver issues, startup entries, and pending updates. Results appear as a color-coded panel showing `XX/YY pts` per dimension — nothing is modified.

### Health Score

Displayed at the top of every run. Trend arrow (↑↓→) shows change from the previous measurement.

| Dimension | Points |
|---|:---:|
| Free space on main drive | 25 |
| Disk health (SMART) | 20 |
| Event Log errors (last 24h) | 20 |
| Pending Windows Updates | 15 |
| Pending reboot | 10 |
| Problematic drivers | 10 |

### Module Selection

The **Specific routine [4]** and **Configure modules [9]** menus share a common module picker:

- Type a number to toggle a module on/off
- Type multiple numbers separated by spaces to toggle several at once — e.g. `2 3 5`
- `a` marks all modules, `n` unmarks all
- Estimated total run time updates in real time as you select

**Configure modules [9]** additionally shows the last run timestamp for each module and marks unsaved changes with `*`. Extra keys available here:

- `r` — save and run immediately without returning to the main menu
- `d` — discard unsaved changes
- `p` — open the preset manager

### Post-run summary

After every routine a summary table is shown with freed space (live mode) or would-free space (dry-run) per module, plus a total at the bottom.

---

## Modules

<details>
<summary><strong>Enabled by default</strong></summary>

| Module | Description |
|---|---|
| `temp_cleaner` | Cleans `%TEMP%` and `C:\Windows\Temp` |
| `recycle_bin` | Removes old items from the Recycle Bin |
| `disk_report` | Disk usage report per drive (always active) |
| `health_check` | Disk SMART health via WMI (always active) |
| `driver_audit` | Devices with errors; PnP rescan in live mode |
| `browser_cache` | Chrome, Edge and Firefox cache |
| `large_file_finder` | Lists files above size threshold (report only) |
| `downloads_audit` | Old files in the Downloads folder (report only) |
| `event_log_scan` | Critical/Error events from System and Application logs |
| `startup_audit` | Programs and tasks that start with Windows |
| `system_log_clean` | CBS logs, minidumps, WER reports, MEMORY.DMP |
| `node_cache_clean` | npm, yarn and pnpm caches |
| `restore_point` | Creates a restore point before live cleanup |
| `disk_optimize` | TRIM on SSDs, defrag on HDDs |
| `windows_update_check` | Checks and triggers pending Windows Updates |
| `software_audit` | Recently installed software (report only) |

</details>

<details>
<summary><strong>Disabled by default</strong></summary>

| Module | Description |
|---|---|
| `duplicate_finder` | SHA256 duplicate finder — slow, set `scan_paths` first |
| `hiberfil_cleaner` | Disables hibernation and Fast Startup permanently |
| `system_repair` | SFC + DISM — 30–60 min, requires admin |
| `windows_update_cache` | Clears Windows Update cache — requires admin |
| `dev_project_clean` | Removes build/deps from inactive dev projects |

</details>

---

## Configuration

Edit `config.json` to customize behavior:

<details>
<summary><strong>Show full config reference</strong></summary>

```json
{
  "dry_run": true,
  "size_threshold_mb": 100,
  "alert_disk_usage_pct": 85,
  "min_age_days": {
    "temp_files": 3,
    "recycle_bin": 30,
    "browser_cache": 7,
    "downloads_report": 60,
    "event_log_scan": 7,
    "software_audit": 30
  },
  "browser_cache": { "chrome": true, "edge": true, "firefox": true },
  "duplicate_finder": { "scan_paths": [], "min_size_kb": 100 },
  "dev_cleanup": {
    "scan_paths": ["C:\\DEV"],
    "min_age_days": 30,
    "targets": ["node_modules", ".venv", "target", "dist", "build", ".next", ".gradle"]
  },
  "excluded_paths": [],
  "schedule": {
    "temp_cleaner":         { "freq_days": 1,  "est_secs": 10   },
    "recycle_bin":          { "freq_days": 1,  "est_secs": 5    },
    "browser_cache":        { "freq_days": 7,  "est_secs": 15   },
    "large_file_finder":    { "freq_days": 7,  "est_secs": 30   },
    "duplicate_finder":     { "freq_days": 30, "est_secs": 300  },
    "system_repair":        { "freq_days": 30, "est_secs": 1800 }
  }
}
```

</details>

---

## Security

- Dry-run is the **default** in every module
- Live mode requires typing `yes` / `sim` to confirm before any deletion
- All cleanup paths are **hardcoded whitelists** — config cannot point to arbitrary folders
- `dev_project_clean` only deletes folders matching the `targets` list, never the project root
- Never touches: Documents, Desktop, Pictures, Music, Videos, OneDrive
- Modifies only the **user** PATH (`HKCU`) — never the system PATH
- No telemetry · No network connections

---

## Project Structure

```
scrub/
├── Run-Scrub.ps1          # Entry point / interactive menu
├── Install-Scrub.ps1      # User-level installer / uninstaller
├── setup.cmd              # One-click installer
├── scrub.psm1             # Main module / orchestrator
├── scrub.psd1             # Module manifest
├── scrub.cmd              # Terminal launcher
├── config.json            # Default configuration
├── strings/
│   ├── en.ps1             # English UI strings
│   └── pt.ps1             # Portuguese UI strings
├── screens/               # UI screen files (12 files)
└── modules/               # 22 independent PS1 modules
```

---

## License

MIT — free to use, modify and distribute.

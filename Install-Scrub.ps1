#Requires -Version 5.1
<#
.SYNOPSIS
    Install or uninstall Scrub for system-wide terminal access.
.DESCRIPTION
    No admin required. User-level install only:
      - Creates scrub.cmd in the tool directory
      - Adds the tool directory to the user PATH (HKCU registry)
      - Registers the module so Import-Module Scrub works anywhere
      - Creates a Start Menu shortcut

    After install, open a NEW terminal and type:
        scrub              -- dry run (safe, nothing deleted)
        scrub -Live        -- live mode (asks confirmation before deleting)
        scrub -ReportOnly  -- analysis only, opens report

.PARAMETER Uninstall
    Remove all installed components (PATH entry, shortcut, module registration).
    Does NOT delete the tool directory itself.
#>
param([switch] $Uninstall)

$ErrorActionPreference = "Stop"

$installRoot   = $PSScriptRoot
$moduleTarget  = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules\Scrub"
$launcherPath  = Join-Path $installRoot "scrub.cmd"
$startMenuPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Scrub.lnk"

function Write-Ok([string]$msg)   { Write-Host "  [OK] $msg" -ForegroundColor Green  }
function Write-Skip([string]$msg) { Write-Host "  [--] $msg" -ForegroundColor DarkGray }
function Write-Warn([string]$msg) { Write-Host "  [!!] $msg" -ForegroundColor Yellow }

# ── Uninstall ─────────────────────────────────────────────────────────────────
if ($Uninstall) {
    Write-Host "`n Scrub - Uninstall`n" -ForegroundColor Yellow

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -like "*$installRoot*") {
        $cleaned = ($userPath -split ";" | Where-Object { $_.Trim() -and $_ -ne $installRoot }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $cleaned, "User")
        Write-Ok "Removed from user PATH"
    } else {
        Write-Skip "Not in user PATH"
    }

    if (Test-Path $launcherPath) {
        Remove-Item $launcherPath -Force
        Write-Ok "Removed scrub.cmd"
    } else {
        Write-Skip "scrub.cmd not found"
    }

    if (Test-Path $startMenuPath) {
        Remove-Item $startMenuPath -Force
        Write-Ok "Removed Start Menu shortcut"
    } else {
        Write-Skip "Start Menu shortcut not found"
    }

    if (Test-Path $moduleTarget) {
        Remove-Item $moduleTarget -Recurse -Force
        Write-Ok "Removed PS module registration"
    } else {
        Write-Skip "PS module not registered"
    }

    Write-Host "`n Done. Open a new terminal to apply PATH changes.`n" -ForegroundColor Yellow
    return
}

# ── Install ───────────────────────────────────────────────────────────────────
Write-Host "`n Scrub - Install`n" -ForegroundColor Cyan

# 1. Create scrub.cmd launcher in the tool directory
$cmdLines = @(
    "@echo off"
    "powershell.exe -NoLogo -ExecutionPolicy RemoteSigned -File `"%~dp0Run-Scrub.ps1`" %*"
)
[System.IO.File]::WriteAllLines($launcherPath, $cmdLines, [System.Text.Encoding]::ASCII)
Write-Ok "Created launcher: $launcherPath"

# 2. Add tool directory to user PATH if not already present
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }

if ($userPath -notlike "*$installRoot*") {
    $separator = if ($userPath -and -not $userPath.EndsWith(";")) { ";" } else { "" }
    [Environment]::SetEnvironmentVariable("Path", "$userPath$separator$installRoot", "User")
    Write-Ok "Added to user PATH -- open a new terminal to use 'scrub'"
} else {
    Write-Skip "Already in user PATH"
}

# 3. Register the PS module via directory junction (no-copy, always up-to-date)
$modulesDir = Split-Path $moduleTarget
if (-not (Test-Path $modulesDir)) {
    New-Item -ItemType Directory -Force -Path $modulesDir | Out-Null
}

if (Test-Path $moduleTarget) {
    Write-Skip "PS module already registered at: $moduleTarget"
} else {
    try {
        New-Item -ItemType Junction -Path $moduleTarget -Target $installRoot | Out-Null
        Write-Ok "PS module registered (junction): $moduleTarget"
    } catch {
        Write-Warn "Junction failed, falling back to copy: $($_.Exception.Message)"
        try {
            Copy-Item -Path $installRoot -Destination $moduleTarget -Recurse -Force
            Write-Ok "PS module registered (copy): $moduleTarget"
        } catch {
            Write-Warn "Module registration skipped: $($_.Exception.Message)"
        }
    }
}

# 4. Create Start Menu shortcut via WScript.Shell COM
try {
    $wsh = New-Object -ComObject WScript.Shell
    $lnk = $wsh.CreateShortcut($startMenuPath)
    $lnk.TargetPath       = "powershell.exe"
    $lnk.Arguments        = "-NoLogo -ExecutionPolicy RemoteSigned -File `"$installRoot\Run-Scrub.ps1`""
    $lnk.WorkingDirectory = $installRoot
    $lnk.Description      = "Scrub - Disk Maintenance"
    $lnk.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
    Write-Ok "Start Menu shortcut created"
} catch {
    Write-Warn "Start Menu shortcut failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host " Done! Open a new terminal and type:" -ForegroundColor Green
Write-Host "   scrub              " -NoNewline; Write-Host "# dry run" -ForegroundColor DarkGray
Write-Host "   scrub -Live        " -NoNewline; Write-Host "# live mode (confirms before deleting)" -ForegroundColor DarkGray
Write-Host "   scrub -ReportOnly  " -NoNewline; Write-Host "# analysis only, opens report" -ForegroundColor DarkGray
Write-Host ""

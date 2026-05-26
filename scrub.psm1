#Requires -Version 5.1

$MODULE_ROOT = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# Load all sub-modules
foreach ($mod in @("TempCleaner", "RecycleBin", "DiskReport", "BrowserCache", "LargeFileFinder", "DuplicateFinder", "EventLogScan", "HibernationClean", "StartupAudit", "SystemLogClean", "NodeCacheClean", "DriverAudit", "SystemRepair", "DiskOptimize", "WindowsUpdateCheck", "WindowsUpdateCacheClean", "RestorePoint", "PendingReboot", "HtmlReport", "SoftwareAudit", "HealthScore", "DevProjectClean", "FolderSizeAnalyzer")) {
    . (Join-Path $MODULE_ROOT "modules\$mod.ps1")
}

# -- Internal helpers ----------------------------------------------------------

function Write-ScrubLog {
    param([string] $LogPath, [object] $Entry)
    if (-not $LogPath -or -not (Test-Path (Split-Path $LogPath))) { return }
    $line = [PSCustomObject]@{
        timestamp = (Get-Date -Format "o")
        module    = $Entry.Module
        data      = $Entry
    } | ConvertTo-Json -Depth 10 -Compress
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function ConvertTo-ScrubBytes {
    param([long] $Bytes)
    if ($Bytes -ge 1GB) { return "$([math]::Round($Bytes/1GB,2)) GB" }
    if ($Bytes -ge 1MB) { return "$([math]::Round($Bytes/1MB,1)) MB" }
    if ($Bytes -ge 1KB) { return "$([math]::Round($Bytes/1KB,0)) KB" }
    return "$Bytes B"
}

function Import-ScrubConfig {
    param([string] $ConfigPath)
    $defaults = ConvertFrom-Json -InputObject (Get-Content (Join-Path $MODULE_ROOT "config.json") -Raw)
    if ($ConfigPath -and (Test-Path $ConfigPath)) {
        $custom = ConvertFrom-Json -InputObject (Get-Content $ConfigPath -Raw)
        foreach ($prop in $custom.PSObject.Properties) {
            $defaults | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
        }
    }
    return $defaults
}

# -- Public API ----------------------------------------------------------------

<#
.SYNOPSIS
    Run the full Scrub disk maintenance routine.
.DESCRIPTION
    Orchestrates all enabled modules according to config.json.
    Dry-run is ON by default -- nothing is deleted unless you pass -DryRun:$false.
.PARAMETER ConfigPath
    Optional path to a custom config.json. Falls back to the built-in config.
.PARAMETER DryRun
    Simulate all destructive operations. Defaults to $true.
.EXAMPLE
    Invoke-Scrub
.EXAMPLE
    Invoke-Scrub -DryRun:$false
.EXAMPLE
    Invoke-Scrub -ConfigPath "C:\MyConfig\scrub.json" -NoReport
#>
function Invoke-Scrub {
    [CmdletBinding()]
    param(
        [string] $ConfigPath = "",
        [bool]   $DryRun     = $true,
        [switch] $NoReport
    )

    $cfg    = Import-ScrubConfig -ConfigPath $ConfigPath
    $logDir = if ($cfg.log_dir)    { $cfg.log_dir }    else { Join-Path $MODULE_ROOT "logs" }
    $repDir = if ($cfg.report_dir) { $cfg.report_dir } else { Join-Path $MODULE_ROOT "reports" }

    New-Item -ItemType Directory -Force -Path $logDir  | Out-Null
    New-Item -ItemType Directory -Force -Path $repDir  | Out-Null

    $logPath = Join-Path $logDir "scrub_$(Get-Date -Format 'yyyyMMdd_HHmmss').jsonl"
    $results = [ordered]@{}

    $modeLabel = if ($DryRun) { "[DRY RUN]" } else { "[LIVE]" }
    Write-Host ""
    Write-Host " Scrub $modeLabel -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
    Write-Host (" " + ("-" * 55)) -ForegroundColor DarkGray

    # -- Core: Pending Reboot (always) --
    Write-Host "  Pending reboot..." -NoNewline
    $r = Get-PendingRebootCheck -LogPath $logPath
    $results["PendingReboot"] = $r
    if ($r.RebootRequired) {
        Write-Host " REBOOT REQUIRED: $($r.Reasons -join ', ')" -ForegroundColor Red
    } else {
        Write-Host " none" -ForegroundColor Gray
    }

    # -- Core: Disk Report --
    Write-Host "  Disk report..." -NoNewline
    $r = Get-DiskReport -AlertUsagePct $cfg.alert_disk_usage_pct -LogPath $logPath
    $results["DiskReport"] = $r
    Write-Host " $($r.Drives.Count) drives" -ForegroundColor Gray
    foreach ($alert in $r.Alerts) { Write-Host "  !! $alert" -ForegroundColor Yellow }

    # -- Core: Health Check --
    Write-Host "  Health check..." -NoNewline
    $r = Get-DiskHealth -LogPath $logPath
    $results["HealthCheck"] = $r
    Write-Host " $($r.Disks.Count) disks" -ForegroundColor Gray
    foreach ($alert in $r.Alerts) { Write-Host "  !! $alert" -ForegroundColor Red }

    # -- Opt-in: Driver Audit --
    if ($cfg.modules.driver_audit) {
        Write-Host "  Driver audit..." -NoNewline
        $r = Get-DriverAudit -DryRun $DryRun -LogPath $logPath
        $results["DriverAudit"] = $r
        if ($r.ProblematicCount -gt 0) {
            Write-Host " $($r.TotalDevices) devices -- " -ForegroundColor Gray -NoNewline
            Write-Host "$($r.ProblematicCount) problematic" -ForegroundColor Yellow
        } else {
            Write-Host " $($r.TotalDevices) devices -- all OK" -ForegroundColor Gray
        }
        if ($r.ScannedForUpdates) { Write-Host "    driver rescan triggered" -ForegroundColor DarkGray }
    }

    # -- Opt-in: Hiberfil.sys --
    if ($cfg.modules.hiberfil_cleaner) {
        Write-Host "  Hiberfil.sys..." -NoNewline
        $r = Invoke-HibernationClean -DryRun $DryRun -LogPath $logPath
        $results["HiberfileCleaner"] = $r
        if ($r.Disabled) {
            Write-Host " disabled -- $(ConvertTo-ScrubBytes $r.FileSizeBytes) freed" -ForegroundColor Green
        } elseif ($r.HibernateEnabled -or $r.FastStartupOn -or $r.FileSizeBytes -gt 0) {
            $flags = @()
            if ($r.HibernateEnabled) { $flags += "hibernate" }
            if ($r.FastStartupOn)    { $flags += "fast startup" }
            Write-Host " active ($($flags -join ' + ')) -- $(ConvertTo-ScrubBytes $r.FileSizeBytes) recoverable" -ForegroundColor Yellow
            foreach ($err in $r.Errors) { Write-Host "    $err" -ForegroundColor DarkGray }
        } else {
            Write-Host " already off" -ForegroundColor Gray
        }
    }

    # -- Opt-in: System Restore Point --
    if ($cfg.modules.restore_point) {
        Write-Host "  Restore point..." -NoNewline
        $r = Invoke-RestorePoint -DryRun $DryRun -LogPath $logPath
        $results["RestorePoint"] = $r
        if ($r.Created) {
            Write-Host " created: $($r.PointName)" -ForegroundColor Green
        } elseif ($DryRun) {
            $latest = if ($r.LatestExisting) { " (latest: $($r.LatestExisting))" } else { "" }
            Write-Host " skipped (dry-run)$latest" -ForegroundColor DarkGray
        } elseif ($r.PointName) {
            Write-Host " $($r.PointName)" -ForegroundColor DarkGray
        } elseif ($r.Errors.Count -gt 0) {
            $firstErr = $r.Errors[0]
            if ($firstErr -eq "REQUIRES_ADMIN") {
                Write-Host " requires admin" -ForegroundColor Yellow
            } else {
                Write-Host " $firstErr" -ForegroundColor Yellow
            }
        }
    }

    # -- Core: Temp Files --
    if ($cfg.modules.temp_cleaner) {
        Write-Host "  Temp files..." -NoNewline
        $r = Invoke-TempCleaner -MinAgeDays $cfg.min_age_days.temp_files -DryRun $DryRun -LogPath $logPath
        $results["TempCleaner"] = $r
        $sz = 0L; foreach ($item in $r.Items) { $sz += $item.SizeBytes }
        $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
        Write-Host " $($r.FilesFound) files -- $label" -ForegroundColor Gray
    }

    # -- Core: Recycle Bin --
    if ($cfg.modules.recycle_bin) {
        Write-Host "  Recycle Bin..." -NoNewline
        $r = Invoke-RecycleBinCleaner -MinAgeDays $cfg.min_age_days.recycle_bin -DryRun $DryRun -LogPath $logPath
        $results["RecycleBin"] = $r
        $label = if ($DryRun) { "would remove $($r.FilesFound) old items" } else { "removed $($r.FilesDeleted) items" }
        Write-Host " $label" -ForegroundColor Gray
    }

    # -- Opt-in: Browser Cache --
    if ($cfg.modules.browser_cache) {
        Write-Host "  Browser cache..." -NoNewline
        $browsers = @{
            chrome  = [bool]$cfg.browser_cache.chrome
            edge    = [bool]$cfg.browser_cache.edge
            firefox = [bool]$cfg.browser_cache.firefox
        }
        $r = Invoke-BrowserCacheClean -Browsers $browsers -MinAgeDays $cfg.min_age_days.browser_cache -DryRun $DryRun -LogPath $logPath
        $results["BrowserCache"] = $r
        $sz = 0L; foreach ($item in $r.Items) { $sz += $item.SizeBytes }
        $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
        Write-Host " $($r.FilesFound) files -- $label" -ForegroundColor Gray
    }

    # -- Opt-in: Large File Finder --
    if ($cfg.modules.large_file_finder) {
        Write-Host "  Large files..."
        $r = Get-LargeFiles -ThresholdMB $cfg.size_threshold_mb -Limit $cfg.large_file_report_limit -LogPath $logPath
        $results["LargeFiles"] = $r
        Write-Host " $($r.FilesFound) files over $($r.ThresholdMB) MB ($($r.TotalSizeGB) GB)" -ForegroundColor Gray
    }

    # -- Opt-in: Downloads Audit --
    if ($cfg.modules.downloads_audit) {
        Write-Host "  Downloads audit..."
        $r = Get-DownloadsAudit -ReportAgeDays $cfg.min_age_days.downloads_report -LogPath $logPath
        $results["DownloadsAudit"] = $r
        Write-Host " $($r.FilesOld) files older than $($cfg.min_age_days.downloads_report) days ($($r.OldSizeMB) MB)" -ForegroundColor Gray
    }

    # -- Opt-in: Duplicate Finder --
    if ($cfg.modules.duplicate_finder) {
        Write-Host "  Duplicates..."
        $paths = @($cfg.duplicate_finder.scan_paths)
        $r = Get-DuplicateFiles -ScanPaths $paths -MinSizeKB $cfg.duplicate_finder.min_size_kb -LogPath $logPath
        $results["DuplicateFinder"] = $r
        if ($r.Errors.Count -gt 0 -and $r.DuplicateSets -eq 0) {
            Write-Host " $($r.Errors[0])" -ForegroundColor Yellow
        } else {
            Write-Host " $($r.DuplicateSets) sets, wasting $([math]::Round($r.WastedBytes/1MB,1)) MB" -ForegroundColor Gray
        }
    }

    # -- Opt-in: Event Log Scan --
    if ($cfg.modules.event_log_scan) {
        Write-Host "  Event log..." -NoNewline
        $r = Get-EventLogScan -LastDays $cfg.min_age_days.event_log_scan -LogPath $logPath
        $results["EventLogScan"] = $r
        $critCount = 0; foreach ($g in $r.Groups) { if ($g.Level -eq "Critical") { $critCount++ } }
        $label     = "$($r.TotalErrors) events, $($r.Groups.Count) unique sources"
        if ($critCount -gt 0) {
            Write-Host " $label" -ForegroundColor Gray -NoNewline
            Write-Host " ($critCount critical)" -ForegroundColor Red
        } else {
            Write-Host " $label" -ForegroundColor Gray
        }
    }

    # -- Opt-in: Startup Audit --
    if ($cfg.modules.startup_audit) {
        Write-Host "  Startup items..." -NoNewline
        $r = Get-StartupAudit -LogPath $logPath
        $results["StartupAudit"] = $r
        $taskCount = 0; $regCount = 0
        foreach ($item in $r.Items) {
            if     ($item.Type -eq "Scheduled Task") { $taskCount++ }
            elseif ($item.Type -eq "Registry")       { $regCount++  }
        }
        Write-Host " $($r.Items.Count) entries ($regCount registry, $taskCount tasks)" -ForegroundColor Gray
    }

    # -- Opt-in: System Logs & Crash Dumps --
    if ($cfg.modules.system_log_clean) {
        Write-Host "  System logs/dumps..." -NoNewline
        $r = Invoke-SystemLogClean -DryRun $DryRun -LogPath $logPath
        $results["SystemLogClean"] = $r
        $sz = 0L; foreach ($item in $r.Items) { $sz += $item.SizeBytes }
        $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
        Write-Host " $($r.FilesFound) files -- $label" -ForegroundColor Gray
        $adminErrors = $r.Errors | Where-Object { $_ -like "REQUIRES_ADMIN*" } | Select-Object -First 1
        if ($adminErrors) { Write-Host "    (some files need admin)" -ForegroundColor DarkGray }
    }

    # -- Opt-in: Node.js Package Manager Caches --
    if ($cfg.modules.node_cache_clean) {
        Write-Host "  Node.js caches..." -NoNewline
        $r = Invoke-NodeCacheClean -DryRun $DryRun -LogPath $logPath
        $results["NodeCacheClean"] = $r
        if ($r.Items.Count -eq 0) {
            Write-Host " none found (npm/yarn/pnpm not installed)" -ForegroundColor DarkGray
        } else {
            $sz = 0L; foreach ($item in $r.Items) { $sz += $item.SizeBytes }
            $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
            Write-Host " $($r.Items.Count) manager(s) -- $label" -ForegroundColor Gray
        }
    }

    # -- Opt-in: System Repair (SFC + DISM) --
    if ($cfg.modules.system_repair) {
        $repairLabel = if ($DryRun) { "DISM check" } else { "SFC + DISM repair -- may take 10-30 min" }
        Write-Host "  System repair ($repairLabel)..."
        $r = Invoke-SystemRepair -DryRun $DryRun -LogPath $logPath
        $results["SystemRepair"] = $r
        if ($r.Errors -contains "REQUIRES_ADMIN") {
            Write-Host " requires admin" -ForegroundColor Yellow
        } else {
            $parts = @()
            if ($r.SfcStatus  -ne "SKIPPED") { $parts += "SFC: $($r.SfcStatus)" }
            if ($r.DismStatus -ne "SKIPPED") { $parts += "DISM: $($r.DismStatus)" }
            $col = if ($r.SfcStatus -match "ISSUES|ERROR" -or $r.DismStatus -match "ISSUES|ERROR") { "Yellow" } else { "Gray" }
            Write-Host " $($parts -join '  ')" -ForegroundColor $col
        }
    }

    # -- Opt-in: Disk Optimization --
    if ($cfg.modules.disk_optimize) {
        Write-Host "  Disk optimize..." -NoNewline
        $r = Invoke-DiskOptimize -DryRun $DryRun -LogPath $logPath
        $results["DiskOptimize"] = $r
        if ($r.Items.Count -eq 0) {
            Write-Host " no fixed volumes found" -ForegroundColor DarkGray
        } else {
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $r.Items) { $parts.Add("$($item.DriveLetter): $($item.MediaType)/$($item.Action)") }
            $summary = $parts -join "  "
            Write-Host " $summary" -ForegroundColor Gray
        }
    }

    # -- Opt-in: Windows Update Check --
    if ($cfg.modules.windows_update_check) {
        Write-Host "  Windows Update..."
        $r = Invoke-WindowsUpdateCheck -DryRun $DryRun -LogPath $logPath
        $results["WindowsUpdateCheck"] = $r
        if ($r.Errors.Count -gt 0 -and $r.PendingCount -eq 0) {
            Write-Host " $($r.Errors[0])" -ForegroundColor Yellow
        } elseif ($r.PendingCount -eq 0) {
            Write-Host " up to date" -ForegroundColor Green
        } else {
            Write-Host " $($r.PendingCount) updates pending" -ForegroundColor Yellow
            if ($r.Triggered) { Write-Host "    update process triggered in background" -ForegroundColor DarkGray }
        }
    }

    # -- Opt-in: Dev Project Cleanup --
    if ($cfg.modules.dev_project_clean) {
        Write-Host "  Dev project cleanup..." -NoNewline
        $devCfg   = if ($cfg.dev_cleanup) { $cfg.dev_cleanup } else { $null }
        $scanPaths = if ($devCfg -and $devCfg.scan_paths) { @($devCfg.scan_paths) } else { @() }
        $minAge    = if ($devCfg -and $devCfg.min_age_days) { [int]$devCfg.min_age_days } else { 30 }
        $targets   = if ($devCfg -and $devCfg.targets) { @($devCfg.targets) } else { $null }
        $devParams = @{ ScanPaths = $scanPaths; MinAgeDays = $minAge; DryRun = $DryRun; LogPath = $logPath }
        if ($targets) { $devParams["Targets"] = $targets }
        $r = Invoke-DevProjectClean @devParams
        $results["DevProjectClean"] = $r
        if ($scanPaths.Count -eq 0) {
            Write-Host " nenhum scan_path configurado" -ForegroundColor DarkGray
        } else {
            $due = $r.Projects | Where-Object { $_.IsDue }
            $sz = 0L; foreach ($proj in $due) { $sz += $proj.HeavyBytes }
            $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
            Write-Host " $($r.Projects.Count) projetos, $($due.Count) devidos -- $label" -ForegroundColor Gray
        }
    }

    # -- Opt-in: Software Audit --
    if ($cfg.modules.software_audit) {
        Write-Host "  Software audit..."
        $swDays = if ($cfg.min_age_days -and $cfg.min_age_days.software_audit) { [int]$cfg.min_age_days.software_audit } else { 30 }
        $r = Get-SoftwareAudit -LastDays $swDays -LogPath $logPath
        $results["SoftwareAudit"] = $r
        Write-Host "  $($r.Items.Count) installed in last $swDays days" -ForegroundColor Gray
    }

    # -- Opt-in: Windows Update Cache (admin only) --
    if ($cfg.modules.windows_update_cache) {
        Write-Host "  Windows Update cache..." -NoNewline
        $r = Invoke-WindowsUpdateCacheClean -DryRun $DryRun -LogPath $logPath
        $results["WindowsUpdateCache"] = $r
        if ($r.Errors.Count -gt 0) {
            Write-Host " $($r.Errors[0])" -ForegroundColor Yellow
        } else {
            $sz = 0L; foreach ($item in $r.Items) { $sz += $item.SizeBytes }
            $label = if ($DryRun) { "would free $(ConvertTo-ScrubBytes $sz)" } else { "freed $(ConvertTo-ScrubBytes $r.BytesFreed)" }
            Write-Host " $label" -ForegroundColor Gray
        }
    }

    Write-Host (" " + ("-" * 55)) -ForegroundColor DarkGray
    Write-Host "  Log: $logPath" -ForegroundColor DarkGray

    # -- Health Score --
    $hsResult = Get-HealthScore `
        -DiskReport    ($results["DiskReport"])   `
        -DiskHealth    ($results["HealthCheck"])  `
        -EventLog      ($results["EventLogScan"]) `
        -PendingReboot ($results["PendingReboot"]) `
        -DriverAudit   ($results["DriverAudit"])
    $results["HealthScore"] = $hsResult
    Save-HealthScore -HistoryPath (Join-Path $MODULE_ROOT "health_history.json") -ScoreResult $hsResult

    # -- HTML Report --
    if (-not $NoReport) {
        $reportPath = Join-Path $repDir "report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
        Write-ScrubHtmlReport -Results $results -ReportPath $reportPath -DryRun $DryRun
    }

    Write-Host ""
    return $results
}

<#
.SYNOPSIS
    Run only the read-only analysis (no deletions, always safe).
#>
function Get-ScrubReport {
    [CmdletBinding()]
    param(
        [string] $ConfigPath = "",
        [switch] $NoReport
    )
    Invoke-Scrub -ConfigPath $ConfigPath -DryRun $true -NoReport:$NoReport
}

<#
.SYNOPSIS
    Create or reset the config.json for this project.
#>
function New-ScrubConfig {
    [CmdletBinding()]
    param(
        [string] $OutputPath = ""
    )
    $src = Join-Path $MODULE_ROOT "config.json"
    $dst = if ($OutputPath) { $OutputPath } else { $src }
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "Config written to: $dst" -ForegroundColor Green
}

if ($MyInvocation.MyCommand.ModuleName) { Export-ModuleMember -Function * }

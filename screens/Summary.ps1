function Show-RunSummary {
    param([object] $Results, [bool] $DryRun)
    if (-not $Results) { return }

    $labels = @{
        TempCleaner        = "Temp files"
        RecycleBin         = "Recycle Bin"
        BrowserCache       = "Browser cache"
        SystemLogClean     = "System logs"
        NodeCacheClean     = "Node cache"
        HiberfileCleaner   = "Hiberfil"
        DiskOptimize       = "Disk optimize"
        DevProjectClean    = "Dev cleanup"
        WindowsUpdateCache = "WU cache"
        LargeFiles         = "Large files"
        DownloadsAudit     = "Downloads"
        DuplicateFinder    = "Duplicates"
        EventLogScan       = "Event log"
        StartupAudit       = "Startup"
        DriverAudit        = "Drivers"
        WindowsUpdateCheck = "Windows Update"
        SoftwareAudit      = "Software"
        RestorePoint       = "Restore point"
        SystemRepair       = "System repair"
        PendingReboot      = "Pending reboot"
        HealthScore        = "Health score"
    }

    $totalFreed = 0L
    $lines      = [System.Collections.Generic.List[object]]::new()

    foreach ($key in $Results.Keys) {
        if ($key -eq "DiskReport" -or $key -eq "HealthCheck") { continue }
        $r     = $Results[$key]
        $label = if ($labels[$key]) { $labels[$key] } else { $key }

        if ($key -eq "HealthScore") {
            $sCol = Format-ScoreColor -Score $r.Score
            $lines.Add([PSCustomObject]@{ Label = $label; Text = "score: $($r.Score)"; Color = $sCol })
            continue
        }
        if ($key -eq "PendingReboot") {
            $lines.Add([PSCustomObject]@{ Label = $label; Text = if ($r.RebootRequired) { "REQUIRED" } else { "none" }; Color = if ($r.RebootRequired) { "Red" } else { "DarkGray" } })
            continue
        }

        $freed  = if ($r.PSObject.Properties["BytesFreed"])  { [long]$r.BytesFreed  } else { 0L }
        $errors = if ($r.PSObject.Properties["Errors"])       { @($r.Errors).Count   } else { 0  }

        if (-not $DryRun -and $freed -gt 0) {
            $totalFreed += $freed
            $lines.Add([PSCustomObject]@{ Label = $label; Text = "$($script:ScrubStr.SUM_FREED) $(ConvertTo-ScrubBytes $freed)"; Color = "Green" })
        } else {
            $potential = 0L
            if ($r.PSObject.Properties["Items"]) {
                foreach ($item in $r.Items) {
                    if ($item.PSObject.Properties["SizeBytes"]) { $potential += [long]$item.SizeBytes }
                }
            }
            if ($DryRun -and $potential -gt 0) {
                $totalFreed += $potential
                $lines.Add([PSCustomObject]@{ Label = $label; Text = "$($script:ScrubStr.SUM_POTENTIAL) $(ConvertTo-ScrubBytes $potential)"; Color = "DarkGray" })
            } elseif ($errors -gt 0) {
                $firstErr = if ($r.PSObject.Properties["Errors"] -and $r.Errors.Count -gt 0) { $r.Errors[0] } else { "" }
                if ($firstErr -eq "REQUIRES_ADMIN") {
                    $lines.Add([PSCustomObject]@{ Label = $label; Text = $script:ScrubStr.ADMIN_NEEDS; Color = "DarkGray" })
                } else {
                    $lines.Add([PSCustomObject]@{ Label = $label; Text = "$errors error(s)"; Color = "Yellow" })
                }
            } else {
                $lines.Add([PSCustomObject]@{ Label = $label; Text = $script:ScrubStr.SUM_NOTHING; Color = "DarkGray" })
            }
        }
    }

    Write-Host ""
    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host "  $($script:ScrubStr.SUM_TITLE)" -ForegroundColor White
    Write-Host ""
    foreach ($l in $lines) {
        Write-Host ("  " + $l.Label.PadRight(18)) -NoNewline
        Write-Host $l.Text -ForegroundColor $l.Color
    }
    Write-Host ""
    Write-Host "  $($script:ScrubStr.SUM_TOTAL) " -NoNewline
    if ($totalFreed -gt 0) {
        $verb = if ($DryRun) { $script:ScrubStr.SUM_POTENTIAL } else { $script:ScrubStr.SUM_FREED }
        Write-Host "$verb $(ConvertTo-ScrubBytes $totalFreed)" -ForegroundColor $(if ($DryRun) { "Cyan" } else { "Green" })
    } else {
        Write-Host $script:ScrubStr.SUM_NOTHING -ForegroundColor DarkGray
    }
    Write-Host ""

    if (-not $DryRun -and $Results) {
        $logLines = [System.Collections.Generic.List[string]]::new()
        $modLabels = @{
            TempCleaner="Temp Files"; RecycleBin="Recycle Bin"; BrowserCache="Browser Cache"
            SystemLogClean="System Logs"; NodeCacheClean="Node Cache"
            HiberfileCleaner="Hiberfil"; DevProjectClean="Dev Cleanup"
            WindowsUpdateCache="WU Cache"
        }
        foreach ($key in $Results.Keys) {
            $r = $Results[$key]
            if (-not $r.PSObject.Properties["Items"]) { continue }
            $deleted = @($r.Items | Where-Object { $_.PSObject.Properties["Deleted"] -and $_.Deleted -eq $true })
            if ($deleted.Count -eq 0) { continue }
            $lbl = if ($modLabels[$key]) { $modLabels[$key] } else { $key }
            $logLines.Add("# $lbl")
            foreach ($item in $deleted) {
                $p = if ($item.PSObject.Properties["Path"]) { $item.Path } elseif ($item.PSObject.Properties["Name"]) { $item.Name } else { "?" }
                $s = if ($item.PSObject.Properties["SizeBytes"] -and $item.SizeBytes) { " ($([math]::Round($item.SizeBytes/1KB,0)) KB)" } else { "" }
                $logLines.Add("$p$s")
            }
            $logLines.Add("")
        }
        if ($logLines.Count -gt 0) {
            $rDir = Join-Path $moduleRoot "reports"
            if (-not (Test-Path $rDir)) { New-Item -ItemType Directory $rDir | Out-Null }
            $lp = Join-Path $rDir "deleted-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').txt"
            $logLines | Set-Content $lp -Encoding UTF8
            Write-Host "  Deletion log: $lp" -ForegroundColor DarkGray
            Write-Host ""
        }
    }
}

function Show-WatchMode {
    param([int]$IntervalSecs = 30)
    Write-Host ""
    Write-Host "  $($script:ScrubStr.WATCH_STARTED -f $IntervalSecs)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 1

    while ($true) {
        $diskResult    = Get-DiskReport -AlertUsagePct (Read-ScrubConfig).alert_disk_usage_pct
        $rebootResult  = Get-PendingRebootCheck
        $cached        = Get-CachedHealthScore

        Clear-Host
        Write-Host ""
        Write-Host "  $($script:ScrubStr.WATCH_TITLE)" -ForegroundColor Cyan -NoNewline
        Write-Host "  --  $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor DarkGray
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host ""

        if ($cached) {
            $col = Format-ScoreColor -Score $cached.Score
            Write-Host "  Health Score: " -NoNewline
            Write-Host "$($cached.Score)/100" -ForegroundColor $col -NoNewline
            if ($cached.Trend) { Write-Host "  $($cached.Trend)" -ForegroundColor DarkGray -NoNewline }
            Write-Host ""
            Write-Host ""
        }

        foreach ($d in $diskResult.Drives) {
            $pct    = [int]$d.UsedPct
            $filled = [int][math]::Round(20 * $pct / 100)
            $bar    = ([string][char]9608 * $filled) + ([string][char]9617 * (20 - $filled))
            $barCol = switch ($d.AlertLevel) { "WARNING" { "Red" } "NOTICE" { "Yellow" } default { "Cyan" } }
            Write-Host ("  " + $d.Drive.PadRight(4)) -NoNewline
            Write-Host $bar -ForegroundColor $barCol -NoNewline
            Write-Host ("  " + "$pct%".PadLeft(4) + "  $($script:ScrubStr.WATCH_USED)  ") -ForegroundColor DarkGray -NoNewline
            Write-Host "$($d.FreeGB) $($script:ScrubStr.WATCH_FREE_GB)" -ForegroundColor White
        }
        Write-Host ""

        if ($rebootResult.RebootRequired) {
            Write-Host "  Reboot: " -NoNewline
            Write-Host $script:ScrubStr.WATCH_PENDING -ForegroundColor Red -NoNewline
            Write-Host "  ($($rebootResult.Reasons -join ', '))" -ForegroundColor DarkGray
        } else {
            Write-Host "  Reboot: " -NoNewline
            Write-Host "OK" -ForegroundColor Green
        }

        $hist    = Get-ScrubHistory
        $now     = Get-Date
        $lastRun = $null
        foreach ($m in $script:CATALOG) {
            $t = $hist.last_runs.($m.Key)
            if ($t) {
                $dt = [datetime]$t
                if ($null -eq $lastRun -or $dt -gt $lastRun) { $lastRun = $dt }
            }
        }
        if ($lastRun) {
            $ago = $now - $lastRun
            $agoStr = if ($ago.TotalHours -lt 24) { $script:ScrubStr.DAYS_AGO_H -f [int]$ago.TotalHours } else { $script:ScrubStr.DAYS_AGO_D -f [int]$ago.TotalDays }
            Write-Host "  $($script:ScrubStr.WATCH_LAST) " -NoNewline
            Write-Host $agoStr -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.WATCH_UPDATE -f $IntervalSecs)  " -ForegroundColor DarkGray -NoNewline
        Write-Host "Ctrl+C" -ForegroundColor DarkGray -NoNewline
        Write-Host " $($script:ScrubStr.WATCH_EXIT)" -ForegroundColor DarkGray

        Start-Sleep -Seconds $IntervalSecs
    }
}

function Show-DiagnosticsSummary {
    param([object] $Results)
    if (-not $Results) { return }

    $SCORE_MAX = @{ disk_space=25; disk_health=20; event_log=20; pending_reboot=10; windows_updates=15; drivers=10 }
    $bd = if ($Results["HealthScore"] -and $Results["HealthScore"].Breakdown) { $Results["HealthScore"].Breakdown } else { $null }

    function _DRow([string]$label, [string]$val, [string]$color, [string]$bdKey = "") {
        Write-Host ("  {0,-28}" -f $label) -NoNewline -ForegroundColor DarkGray
        Write-Host ("{0,-24}" -f $val) -NoNewline -ForegroundColor $color
        if ($bdKey -and $bd -and $null -ne $bd[$bdKey]) {
            Write-Host "$($bd[$bdKey])/$($SCORE_MAX[$bdKey]) $($script:ScrubStr.DIAG_PTS)" -ForegroundColor DarkGray
        } else { Write-Host "" }
    }

    Write-Host ""
    Write-Host "  ── $($script:ScrubStr.DIAG_TITLE) " -NoNewline -ForegroundColor White
    Write-Host ("─" * 38) -ForegroundColor DarkGray
    Write-Host ""

    if ($Results["DiskReport"]) {
        $dr = $Results["DiskReport"]
        $primary = $dr.Drives | Where-Object { $_.Drive -eq "C:\" } | Select-Object -First 1
        if (-not $primary) { $primary = $dr.Drives | Select-Object -First 1 }
        if ($primary) {
            $col = if ($primary.UsedPct -ge 90) { "Red" } elseif ($primary.UsedPct -ge 75) { "Yellow" } else { "Green" }
            _DRow $script:ScrubStr.DIAG_DISK_SPACE "$($primary.FreeGB) GB $($script:ScrubStr.DIAG_FREE) ($($primary.UsedPct)% $($script:ScrubStr.DIAG_USED))" $col "disk_space"
        }
    }

    if ($Results["HealthCheck"]) {
        $hc = $Results["HealthCheck"]
        $bad = $hc.Disks | Where-Object { $_.AlertLevel -eq "CRITICAL" }
        if ($bad) {
            _DRow $script:ScrubStr.DIAG_DISK_HEALTH "$($hc.Disks.Count) $($script:ScrubStr.DIAG_DISKS) — $($bad.Count) CRITICAL" "Red" "disk_health"
        } else {
            _DRow $script:ScrubStr.DIAG_DISK_HEALTH "$($hc.Disks.Count) $($script:ScrubStr.DIAG_DISKS) OK" "Green" "disk_health"
        }
    }

    if ($Results["PendingReboot"]) {
        $pr = $Results["PendingReboot"]
        if ($pr.RebootRequired) {
            _DRow $script:ScrubStr.DIAG_REBOOT $script:ScrubStr.DIAG_REBOOT_YES "Yellow" "pending_reboot"
        } else {
            _DRow $script:ScrubStr.DIAG_REBOOT $script:ScrubStr.DIAG_REBOOT_NO "Green" "pending_reboot"
        }
    }

    if ($Results["EventLogScan"]) {
        $el = $Results["EventLogScan"]
        $critCount = ($el.Groups | Where-Object { $_.Level -eq "Critical" } | Measure-Object).Count
        if ($critCount -gt 0) {
            _DRow $script:ScrubStr.DIAG_EVENT_LOG "$($el.TotalErrors) $($script:ScrubStr.DIAG_ERRORS) ($critCount critical)" "Red" "event_log"
        } elseif ($el.TotalErrors -gt 0) {
            _DRow $script:ScrubStr.DIAG_EVENT_LOG "$($el.TotalErrors) $($script:ScrubStr.DIAG_ERRORS)" "Yellow" "event_log"
        } else {
            _DRow $script:ScrubStr.DIAG_EVENT_LOG $script:ScrubStr.DIAG_NO_ERRORS "Green" "event_log"
        }
    }

    if ($Results["DriverAudit"]) {
        $da = $Results["DriverAudit"]
        if ($da.ProblematicCount -gt 0) {
            _DRow $script:ScrubStr.DIAG_DRIVERS "$($da.TotalDevices) $($script:ScrubStr.DIAG_DEVICES) — $($da.ProblematicCount) $($script:ScrubStr.DIAG_PROBLEMS)" "Yellow" "drivers"
        } else {
            _DRow $script:ScrubStr.DIAG_DRIVERS "$($da.TotalDevices) $($script:ScrubStr.DIAG_DEVICES) OK" "Green" "drivers"
        }
    }

    if ($Results["StartupAudit"]) {
        $sa = $Results["StartupAudit"]
        _DRow $script:ScrubStr.DIAG_STARTUP "$($sa.Items.Count) $($script:ScrubStr.DIAG_ENTRIES)" "Gray"
    }

    if ($Results["WindowsUpdateCheck"]) {
        $wu = $Results["WindowsUpdateCheck"]
        if ($wu.Errors.Count -gt 0) {
            _DRow $script:ScrubStr.DIAG_UPDATES $script:ScrubStr.DIAG_UPDATE_ERR "DarkGray" "windows_updates"
        } elseif ($wu.PendingCount -gt 0) {
            _DRow $script:ScrubStr.DIAG_UPDATES "$($wu.PendingCount) $($script:ScrubStr.DIAG_PENDING)" "Yellow" "windows_updates"
        } else {
            _DRow $script:ScrubStr.DIAG_UPDATES $script:ScrubStr.DIAG_UP_TO_DATE "Green" "windows_updates"
        }
    }

    if ($Results["HealthScore"]) {
        $hs = $Results["HealthScore"]
        $col = Format-ScoreColor -Score $hs.Score
        Write-Host ""
        Write-Host ("  {0,-28}" -f $script:ScrubStr.DIAG_SCORE) -NoNewline -ForegroundColor DarkGray
        Write-Host $hs.Score -ForegroundColor $col
    }

    Write-Host ""
    Write-Host ("  " + ("─" * 52)) -ForegroundColor DarkGray
}

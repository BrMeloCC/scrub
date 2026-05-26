function Get-HealthScore {
    param(
        [PSCustomObject] $DiskReport  = $null,
        [PSCustomObject] $DiskHealth  = $null,
        [PSCustomObject] $EventLog    = $null,
        [PSCustomObject] $PendingReboot = $null,
        [PSCustomObject] $DriverAudit = $null
    )

    $breakdown = [ordered]@{}
    $total     = 0

    # ── Disk space (25 pts) ───────────────────────────────────────────────────
    # Primary drive = first drive with a Windows path or highest-used drive
    $pts = 25
    if ($DiskReport -and $DiskReport.Drives.Count -gt 0) {
        $primary = $DiskReport.Drives | Where-Object { $_.Drive -eq "C:\" } | Select-Object -First 1
        if (-not $primary) { $primary = $DiskReport.Drives | Sort-Object UsedPct -Descending | Select-Object -First 1 }
        if ($primary) {
            # 0% used = 25, 90%+ used = 0, linear between 50% and 90%
            $pct = $primary.UsedPct
            if ($pct -le 50)     { $pts = 25 }
            elseif ($pct -ge 90) { $pts = 0  }
            else                 { $pts = [int][math]::Round(25 * (90 - $pct) / 40) }
        }
    }
    $breakdown["disk_space"] = $pts
    $total += $pts

    # ── Disk health (20 pts) ──────────────────────────────────────────────────
    $pts = 20
    if ($DiskHealth -and $DiskHealth.Disks.Count -gt 0) {
        $critical = $DiskHealth.Disks | Where-Object { $_.AlertLevel -eq "CRITICAL" }
        if ($critical) { $pts = 0 }
        elseif ($DiskHealth.Alerts.Count -gt 0) { $pts = 5 }
    }
    $breakdown["disk_health"] = $pts
    $total += $pts

    # ── Event Log errors last 24h (20 pts) ────────────────────────────────────
    $pts = 20
    if ($EventLog) {
        $errCount = $EventLog.TotalErrors
        if ($errCount -ge 20)    { $pts = 0  }
        elseif ($errCount -gt 0) { $pts = [int][math]::Round(20 * (1 - ($errCount / 20))) }
    }
    $breakdown["event_log"] = $pts
    $total += $pts

    # ── Pending reboot (10 pts) ───────────────────────────────────────────────
    $pts = 10
    if ($PendingReboot -and $PendingReboot.RebootRequired) { $pts = 0 }
    $breakdown["pending_reboot"] = $pts
    $total += $pts

    # ── Windows updates (15 pts) ──────────────────────────────────────────────
    # We don't run WU check here -- read from last log entry instead
    # Default to full score if no data; HtmlReport passes it in via last log
    $pts = 15
    $breakdown["windows_updates"] = $pts
    $total += $pts

    # ── Driver issues (10 pts) ────────────────────────────────────────────────
    $pts = 10
    if ($DriverAudit -and $DriverAudit.Devices.Count -gt 0) {
        $bad = $DriverAudit.Devices | Where-Object { $_.Status -ne "OK" }
        if ($bad) { $pts = 0 }
    }
    $breakdown["drivers"] = $pts
    $total += $pts

    return [PSCustomObject]@{
        Score     = $total
        Breakdown = $breakdown
    }
}

function Save-HealthScore {
    param(
        [string]         $HistoryPath,
        [PSCustomObject] $ScoreResult
    )

    $history = if (Test-Path $HistoryPath) {
        try { Get-Content $HistoryPath -Raw | ConvertFrom-Json } catch { [PSCustomObject]@{ entries = @() } }
    } else {
        [PSCustomObject]@{ entries = @() }
    }

    if (-not $history.entries) { $history.entries = @() }

    $entry = [PSCustomObject]@{
        date      = (Get-Date -Format "o")
        score     = $ScoreResult.Score
        breakdown = $ScoreResult.Breakdown
    }

    $newEntries = @($history.entries) + @($entry) | Select-Object -Last 90

    [PSCustomObject]@{ entries = $newEntries } |
        ConvertTo-Json -Depth 10 |
        Set-Content $HistoryPath -Encoding UTF8
}

function Get-HealthHistory {
    param([string] $HistoryPath)

    if (-not (Test-Path $HistoryPath)) { return @() }
    try {
        $h = Get-Content $HistoryPath -Raw | ConvertFrom-Json
        if ($h.entries) { return @($h.entries) } else { return @() }
    } catch { return @() }
}

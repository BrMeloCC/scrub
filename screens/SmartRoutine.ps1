function Show-SmartRoutine {
    $cfg      = Read-ScrubConfig
    $toggles  = Get-ActiveToggles
    $history  = Get-ScrubHistory
    $now      = Get-Date

    $due  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $skip = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($m in $script:CATALOG) {
        if (-not $toggles[$m.Key]) { continue }

        $sched       = Get-EffectiveSchedule -Key $m.Key -Cfg $cfg -CatalogEntry $m
        $lastRunRaw  = $history.last_runs.($m.Key)
        $isDue       = $true
        $lastDisplay = $script:ScrubStr.NEVER
        $agoDisplay  = ""

        if ($lastRunRaw) {
            $lastDt      = [datetime]$lastRunRaw
            $elapsedH    = ($now - $lastDt).TotalHours
            $elapsedD    = ($now - $lastDt).TotalDays
            $lastDisplay = $lastDt.ToString("dd/MM HH:mm")
            $agoDisplay  = if ($elapsedH -lt 24) { $script:ScrubStr.DAYS_AGO_H -f [int]$elapsedH } else { $script:ScrubStr.DAYS_AGO_D -f [int]$elapsedD }
            $isDue       = $elapsedD -ge $sched.FreqDays
        }

        $entry = [PSCustomObject]@{
            Module      = $m
            FreqLabel   = Get-FreqLabel $sched.FreqDays
            EstSecs     = $sched.EstSecs
            LastDisplay = $lastDisplay
            AgoDisplay  = $agoDisplay
            IsDue       = $isDue
        }
        if ($isDue) { $due.Add($entry) } else { $skip.Add($entry) }
    }

    $dueSecs = 0; foreach ($e in $due) { $dueSecs += $e.EstSecs }; [int]$dueSecs = $dueSecs

    $forceAll = $false
    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.SMART_TITLE)" -ForegroundColor White
        Write-Host ""

        # ── Nada a fazer ──
        if ($due.Count -eq 0 -and -not $forceAll) {
            Write-Host "  $($script:ScrubStr.SMART_ALL_DONE)" -ForegroundColor Green
            $latest = Get-ChildItem (Join-Path $moduleRoot "reports") -Filter "*.html" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                Write-Host "  $($script:ScrubStr.SMART_LAST_RPT) $($latest.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))" -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
            Write-Host "  " -NoNewline; Write-Host "V" -ForegroundColor Cyan -NoNewline
            Write-Host " = $($script:ScrubStr.SMART_V)   " -NoNewline
            Write-Host "R" -ForegroundColor Yellow -NoNewline
            Write-Host " = $($script:ScrubStr.SMART_R)   " -NoNewline
            Write-Host "C" -ForegroundColor DarkGray -NoNewline
            Write-Host " = $($script:ScrubStr.BACK)"
            Write-Host ""
            $raw = (Read-Host "  >").Trim().ToUpper()
            if ($raw -eq "V") { Open-LatestReport; continue }
            if ($raw -eq "R") { $forceAll = $true; continue }
            return
        }

        # ── Lista de modulos devidos ──
        if ($forceAll) {
            Write-Host "  $($script:ScrubStr.SMART_FORCED)" -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Host "  $($script:ScrubStr.SMART_READY)" -ForegroundColor White
            Write-Host ""
            foreach ($e in $due) {
                $t   = (Format-EstSecs $e.EstSecs).PadRight(7)
                $ago = if ($e.AgoDisplay) { $e.AgoDisplay } else { $script:ScrubStr.NEVER_RUN }
                Write-Host ("    " + $e.Module.Label.PadRight(18)) -ForegroundColor Cyan -NoNewline
                Write-Host ($e.FreqLabel.PadRight(10)) -ForegroundColor DarkGray -NoNewline
                Write-Host $t -ForegroundColor White -NoNewline
                Write-Host "$($script:ScrubStr.LAST_RUN) $ago" -ForegroundColor DarkGray
            }
            if ($skip.Count -gt 0) {
                Write-Host ""
                Write-Host "  $($script:ScrubStr.SMART_SKIP -f $skip.Count)" -ForegroundColor DarkGray
                foreach ($e in $skip) {
                    Write-Host ("    " + $e.Module.Label.PadRight(18)) -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($script:ScrubStr.NEXT_IN) $($e.FreqLabel)  $($script:ScrubStr.LAST_RUN) $($e.AgoDisplay)" -ForegroundColor DarkGray
                }
            }
        }

        # ── Estimativa de tempo ──
        Write-Host ""
        if ($forceAll) {
            $dispSecs = 0
            foreach ($m in $script:CATALOG) { if ($toggles[$m.Key]) { $dispSecs += $m.EstSecs } }
            [int]$dispSecs = $dispSecs
        } else {
            $dispSecs = $dueSecs
        }
        $estLabel = Format-EstSecs $dispSecs
        Write-Host "  $($script:ScrubStr.SMART_EST) " -NoNewline
        Write-Host $estLabel -ForegroundColor $(if ($dispSecs -gt 600) { "Yellow" } else { "Green" })
        if ($dispSecs -gt 1200) {
            Write-Host "  $($script:ScrubStr.SMART_LONG_WARN)" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  " -NoNewline; Write-Host "E" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.SMART_E)   " -NoNewline
        Write-Host "L" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.SMART_L)   " -NoNewline
        Write-Host "V" -ForegroundColor White -NoNewline
        Write-Host " = $($script:ScrubStr.SMART_V)   " -NoNewline
        Write-Host "C" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToUpper()
        if ($raw -eq "C") { return }
        if ($raw -eq "V") { Open-LatestReport; continue }
        if ($raw -ne "E" -and $raw -ne "L") { continue }

        $dryRun = ($raw -ne "L")
        if (-not $dryRun) {
            $c = Read-Host "  $($script:ScrubStr.CONFIRM_LIVE -f $script:ScrubStr.CONFIRM_WORD)"
            if ($c -ne $script:ScrubStr.CONFIRM_WORD) {
                Write-Host "  $($script:ScrubStr.CANCELED)" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
        }

        Write-ScrubHeader
        $runToggles = if ($forceAll) { $toggles } else {
            $t = @{}
            foreach ($m in $script:CATALOG) { $t[$m.Key] = $false }
            foreach ($e in $due)             { $t[$e.Module.Key] = $true }
            $t
        }
        $ac = Get-AdminConflicts -Toggles $runToggles
        if ($ac) { Show-AdminPrompt -Conflicts $ac }

        if ($forceAll) {
            $res = Invoke-ScrubCustom -Toggles $toggles -DryRun $dryRun
            $hist = Get-ScrubHistory
            Save-ScrubHistory -History $hist -Keys ($toggles.Keys | Where-Object { $toggles[$_] })
        } else {
            $toggles = $runToggles
            $res = Invoke-ScrubCustom -Toggles $toggles -DryRun $dryRun
            $hist = Get-ScrubHistory
            Save-ScrubHistory -History $hist -Keys ($due | ForEach-Object { $_.Module.Key })
        }

        Show-RunSummary -Results $res -DryRun $dryRun
        Open-LatestReport
        $Host.UI.RawUI.FlushInputBuffer()
        Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
        return
    }
}

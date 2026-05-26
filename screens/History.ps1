function Show-History {
    $logDir  = Join-Path $moduleRoot "logs"
    $hsPath  = Join-Path $moduleRoot "health_history.json"

    Write-ScrubHeader
    Write-Host "  $($script:ScrubStr.HIST_TITLE)  " -ForegroundColor White -NoNewline
    Write-Host $script:ScrubStr.LOADING -ForegroundColor DarkGray

    # ── Parse logs ──
    $executions = [System.Collections.Generic.List[object]]::new()

    if (Test-Path $logDir) {
        $allFiles = @(Get-ChildItem $logDir -Filter "*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
        $logFiles = if ($allFiles.Count -gt 30) { $allFiles[($allFiles.Count - 30)..($allFiles.Count - 1)] } else { $allFiles }
        foreach ($lf in $logFiles) {
            $execData = @{ Date = $lf.LastWriteTime; FreeGB = $null; FreedBytes = 0L; Errors = 0 }
            try {
                $lines = [System.IO.File]::ReadAllLines($lf.FullName)
                foreach ($line in $lines) {
                    if (-not $line) { continue }
                    try {
                        $entry = ConvertFrom-Json -InputObject $line
                        switch ($entry.module) {
                            "DiskReport" {
                                $cDrive = $entry.data.Drives | Where-Object { $_.Drive -eq "C:\" } | Select-Object -First 1
                                if (-not $cDrive) { $cDrive = $entry.data.Drives | Select-Object -First 1 }
                                if ($cDrive) { $execData.FreeGB = [double]$cDrive.FreeGB }
                            }
                            { $_ -in @("TempCleaner","RecycleBin","BrowserCache","SystemLogClean","NodeCacheClean") } {
                                $b = $entry.data.BytesFreed
                                if ($b) { $execData.FreedBytes += [long]$b }
                            }
                            "EventLogScan" {
                                $execData.Errors = [int]$entry.data.TotalErrors
                            }
                        }
                    } catch {}
                }
            } catch {}
            if ($null -ne $execData.FreeGB -or $execData.FreedBytes -gt 0) {
                $executions.Add([PSCustomObject]$execData)
            }
        }
    }

    # ── Health history ──
    $hsHist = Get-HealthHistory -HistoryPath $hsPath

    Clear-Host
    Write-ScrubHeader
    Write-Host "  $($script:ScrubStr.HIST_TITLE)" -ForegroundColor White
    Write-Host ""

    # ── Health Score chart ──
    if ($hsHist.Count -gt 0) {
        $scores  = @($hsHist | ForEach-Object { [double]$_.score })
        $spark   = ConvertTo-Sparkline -Values $scores -Width 12
        $last    = [int]$scores[-1]
        $scoreCol = Format-ScoreColor -Score $last
        Write-Host "  Health Score: " -NoNewline
        Write-Host "$last/100" -ForegroundColor $scoreCol -NoNewline
        Write-Host "  $spark  " -ForegroundColor Cyan -NoNewline
        Write-Host "($($hsHist.Count) $($script:ScrubStr.HIST_MEASURES))" -ForegroundColor DarkGray
        Write-Host ""
    }

    # ── Free space trend ──
    $withFree = @($executions | Where-Object { $null -ne $_.FreeGB })
    if ($withFree.Count -ge 2) {
        Write-Host "  $($script:ScrubStr.HIST_FREE -f [math]::Min($withFree.Count,10))" -ForegroundColor White
        $slice = if ($withFree.Count -gt 10) { $withFree[($withFree.Count-10)..($withFree.Count-1)] } else { $withFree }
        $maxFree = ($slice | Measure-Object -Property FreeGB -Maximum).Maximum
        $barW    = 30
        foreach ($ex in $slice) {
            $filled = if ($maxFree -gt 0) { [int][math]::Round($barW * $ex.FreeGB / $maxFree) } else { 0 }
            $bar    = ([string][char]9608 * $filled) + ([string][char]9617 * ($barW - $filled))
            $label  = $ex.Date.ToString("dd/MM")
            Write-Host ("  " + $label + "  ") -ForegroundColor DarkGray -NoNewline
            Write-Host $bar -ForegroundColor Cyan -NoNewline
            Write-Host ("  " + "$([math]::Round($ex.FreeGB,1)) GB") -ForegroundColor White
        }
        Write-Host ""
    }

    # ── Freed per execution ──
    $withFreed = @($executions | Where-Object { $_.FreedBytes -gt 0 })
    if ($withFreed.Count -ge 1) {
        Write-Host "  $($script:ScrubStr.HIST_FREED -f [math]::Min($withFreed.Count,8))" -ForegroundColor White
        $slice   = if ($withFreed.Count -gt 8) { $withFreed[($withFreed.Count-8)..($withFreed.Count-1)] } else { $withFreed }
        $maxFreed = ($slice | Measure-Object -Property FreedBytes -Maximum).Maximum
        $barW    = 30
        foreach ($ex in $slice) {
            $filled = if ($maxFreed -gt 0) { [int][math]::Round($barW * $ex.FreedBytes / $maxFreed) } else { 0 }
            $bar    = ([string][char]9608 * $filled) + ([string][char]9617 * ($barW - $filled))
            $label  = $ex.Date.ToString("dd/MM")
            Write-Host ("  " + $label + "  ") -ForegroundColor DarkGray -NoNewline
            Write-Host $bar -ForegroundColor Yellow -NoNewline
            Write-Host ("  " + (ConvertTo-ScrubBytes $ex.FreedBytes)) -ForegroundColor White
        }
        Write-Host ""
    }

    if ($executions.Count -eq 0 -and $hsHist.Count -eq 0) {
        Write-Host "  $($script:ScrubStr.HIST_NO_DATA)" -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.HIST_NO_DATA2)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  $($script:ScrubStr.PRESS_ENTER)" | Out-Null
}

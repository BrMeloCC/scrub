function Show-ModuleSelector {
    $toggles = @{}
    foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $false }

    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.MOD_TITLE)" -ForegroundColor White
        Write-Host "  $($script:ScrubStr.MOD_ALWAYS)" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $script:CATALOG.Count; $i++) {
            $m    = $script:CATALOG[$i]
            $on   = $toggles[$m.Key]
            $box  = if ($on) { "[X]" } else { "[ ]" }
            $col  = if ($on) { "Green" } else { "DarkGray" }
            $risk = if ($m.Risk) { "[!]" } else { "   " }
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + " ") -NoNewline
            Write-Host $box -ForegroundColor $col -NoNewline
            Write-Host " $risk " -ForegroundColor Yellow -NoNewline
            Write-Host ($m.Label.PadRight(16)) -ForegroundColor White -NoNewline
            Write-Host $m.Desc -ForegroundColor DarkGray
        }

        $estSecs = 0
        foreach ($m in $script:CATALOG) { if ($toggles[$m.Key]) { $estSecs += $m.EstSecs } }
        $estCol = if ($estSecs -eq 0) { "DarkGray" } elseif ($estSecs -gt 600) { "Yellow" } else { "Green" }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MOD_EST) " -NoNewline
        Write-Host (Format-EstSecs $estSecs) -ForegroundColor $estCol
        Write-Host "  $($script:ScrubStr.NUM) = $($script:ScrubStr.TOGGLE)   " -NoNewline
        Write-Host "a" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_ALL)   " -NoNewline
        Write-Host "n" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_NONE)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.CONFIRM_ACT)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "ok") { return $toggles }
        if ($raw -eq "c")  { return $null }
        if ($raw -eq "a")  { foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $true  }; continue }
        if ($raw -eq "n")  { foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $false }; continue }
        foreach ($part in ($raw -split '\s+')) {
            $n = 0
            if ([int]::TryParse($part, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
                $toggles[$script:CATALOG[$n - 1].Key] = -not $toggles[$script:CATALOG[$n - 1].Key]
            }
        }
    }
}

# ── Configuracao de frequencia e tempo ────────────────────────────────────────

function Show-FreqConfig {
    $cfgPath = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    $cfg     = ConvertFrom-Json -InputObject (Get-Content $cfgPath -Raw)
    if (-not $cfg.schedule) {
        $cfg | Add-Member -MemberType NoteProperty -Name "schedule" -Value ([PSCustomObject]@{}) -Force
    }

    $sched = @{}
    foreach ($m in $script:CATALOG) {
        $s = $cfg.schedule.($m.Key)
        $sched[$m.Key] = @{
            FreqDays = if ($s -and $null -ne $s.freq_days) { [int]$s.freq_days } else { $m.FreqDays }
            EstSecs  = if ($s -and $null -ne $s.est_secs)  { [int]$s.est_secs  } else { $m.EstSecs  }
        }
    }

    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.CFG_FREQ_TITLE)" -ForegroundColor White
        Write-Host "  $($script:ScrubStr.CFG_FREQ_DESC)" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $script:CATALOG.Count; $i++) {
            $m      = $script:CATALOG[$i]
            $s      = $sched[$m.Key]
            $fLabel = (Get-FreqLabel $s.FreqDays).PadRight(9)
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
            Write-Host ($m.Label.PadRight(18)) -ForegroundColor White -NoNewline
            Write-Host $fLabel -ForegroundColor Cyan -NoNewline
            Write-Host "  est: $(Format-EstSecs $s.EstSecs)" -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.CFG_NUM_EDIT)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.SAVE)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host "  $($script:ScrubStr.CFG_FREQ_DEFS)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "ok") {
            foreach ($key in $sched.Keys) {
                $entry = [PSCustomObject]@{ freq_days = $sched[$key].FreqDays; est_secs = $sched[$key].EstSecs }
                $cfg.schedule | Add-Member -MemberType NoteProperty -Name $key -Value $entry -Force
            }
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
            Write-Host "  $($script:ScrubStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        if ($raw -eq "c") { return }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
            $key   = $script:CATALOG[$n - 1].Key
            $label = $script:CATALOG[$n - 1].Label
            Write-Host ""
            Write-Host "  $($script:ScrubStr.CFG_EDITING) $label" -ForegroundColor Cyan
            Write-Host "  $($script:ScrubStr.CFG_FREQ_CUR) $($sched[$key].FreqDays) $($script:ScrubStr.DAYS)" -ForegroundColor DarkGray
            $fRaw = (Read-Host "  $($script:ScrubStr.CFG_FREQ_NEW)").Trim()
            $fVal = 0
            if ([int]::TryParse($fRaw, [ref]$fVal) -and $fVal -ge 1) { $sched[$key].FreqDays = $fVal }
            Write-Host "  $($script:ScrubStr.CFG_EST_CUR) $(Format-EstSecs $sched[$key].EstSecs)" -ForegroundColor DarkGray
            $eRaw = (Read-Host "  $($script:ScrubStr.CFG_EST_NEW)").Trim()
            $eVal = 0
            if ($eRaw -ne "" -and [int]::TryParse($eRaw, [ref]$eVal) -and $eVal -ge 1) { $sched[$key].EstSecs = $eVal }
        }
    }
}

# ── Configuracao de limites de idade ──────────────────────────────────────────

function Show-ThresholdsConfig {
    $cfgPath = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    $cfg     = ConvertFrom-Json -InputObject (Get-Content $cfgPath -Raw)
    if (-not $cfg.min_age_days) {
        $cfg | Add-Member -MemberType NoteProperty -Name "min_age_days" -Value ([PSCustomObject]@{}) -Force
    }

    $LABELS = [ordered]@{
        temp_files        = "Temp files"
        recycle_bin       = "Recycle Bin"
        downloads_report  = "Downloads report"
        browser_cache     = "Browser cache"
        event_log_scan    = "Event log scan"
        software_audit    = "Software audit"
    }
    $DEFAULTS = @{ temp_files = 3; recycle_bin = 30; downloads_report = 60; browser_cache = 7; event_log_scan = 7; software_audit = 30 }

    $thresholds = @{}
    foreach ($key in $LABELS.Keys) {
        $v = $cfg.min_age_days.$key
        $thresholds[$key] = if ($null -ne $v) { [int]$v } else { $DEFAULTS[$key] }
    }
    $keys = @($LABELS.Keys)

    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.THR_TITLE)" -ForegroundColor White
        Write-Host "  $($script:ScrubStr.THR_DESC)" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k = $keys[$i]
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
            Write-Host ($LABELS[$k].PadRight(22)) -ForegroundColor White -NoNewline
            Write-Host "$($thresholds[$k]) $($script:ScrubStr.DAYS)" -ForegroundColor Cyan
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.THR_NUM_EDIT)" -ForegroundColor DarkGray
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "ok") {
            foreach ($key in $thresholds.Keys) {
                $cfg.min_age_days | Add-Member -MemberType NoteProperty -Name $key -Value $thresholds[$key] -Force
            }
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
            Write-Host "  $($script:ScrubStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        if ($raw -eq "c") { return }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) {
            $key = $keys[$n - 1]
            Write-Host ""
            Write-Host "  $($script:ScrubStr.THR_EDITING) $($LABELS[$key])" -ForegroundColor Cyan
            Write-Host "  $($script:ScrubStr.THR_CURRENT) $($thresholds[$key]) $($script:ScrubStr.DAYS)" -ForegroundColor DarkGray
            $vRaw = (Read-Host "  $($script:ScrubStr.THR_PROMPT)").Trim()
            $vVal = 0
            if ($vRaw -ne "" -and [int]::TryParse($vRaw, [ref]$vVal) -and $vVal -ge 1) { $thresholds[$key] = $vVal }
        }
    }
}

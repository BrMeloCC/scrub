function Show-ModuleConfig {
    $cfgPath = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    $cfg     = ConvertFrom-Json -InputObject (Get-Content $cfgPath -Raw)
    $history = Get-ScrubHistory

    $toggles  = @{}
    $original = @{}
    foreach ($m in $script:CATALOG) {
        $v = $cfg.modules.($m.Key)
        $toggles[$m.Key]  = if ($null -eq $v) { $false } else { [bool]$v }
        $original[$m.Key] = $toggles[$m.Key]
    }

    function Save-Config {
        foreach ($key in $toggles.Keys) {
            $cfg.modules | Add-Member -MemberType NoteProperty -Name $key -Value $toggles[$key] -Force
        }
        $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
    }

    while ($true) {
        $dirty = $false
        foreach ($key in $toggles.Keys) { if ($toggles[$key] -ne $original[$key]) { $dirty = $true; break } }

        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.CFG_MOD_TITLE)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.CFG_MOD_SUB -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.CFG_MOD_ALWAYS)" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $script:CATALOG.Count; $i++) {
            $m       = $script:CATALOG[$i]
            $on      = $toggles[$m.Key]
            $box     = if ($on) { "[X]" } else { "[ ]" }
            $col     = if ($on) { "Green" } else { "DarkGray" }
            $risk    = if ($m.Risk) { "[!]" } else { "   " }
            $lastRaw = $history.last_runs.($m.Key)
            $ago     = if ($lastRaw) {
                $elapsed = (Get-Date) - [datetime]$lastRaw
                if ($elapsed.TotalHours -lt 24) { $script:ScrubStr.DAYS_AGO_H -f [int]$elapsed.TotalHours }
                else { $script:ScrubStr.DAYS_AGO_D -f [int]$elapsed.TotalDays }
            } else { $script:ScrubStr.NEVER }

            Write-Host ("  " + "$($i + 1)".PadLeft(2) + " ") -NoNewline
            Write-Host $box -ForegroundColor $col -NoNewline
            Write-Host " $risk " -ForegroundColor Yellow -NoNewline
            Write-Host ($m.Label.PadRight(16)) -ForegroundColor White -NoNewline
            Write-Host ($ago.PadRight(10)) -ForegroundColor DarkGray -NoNewline
            Write-Host $m.Detail -ForegroundColor DarkGray
        }

        $estSecs = 0
        foreach ($m in $script:CATALOG) { if ($toggles[$m.Key]) { $estSecs += $m.EstSecs } }
        $estCol = if ($estSecs -eq 0) { "DarkGray" } elseif ($estSecs -gt 600) { "Yellow" } else { "Green" }

        Write-Host ""
        Write-Host ("  " + ("-" * 62)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MOD_EST) " -NoNewline
        Write-Host (Format-EstSecs $estSecs) -ForegroundColor $estCol -NoNewline
        if ($dirty) { Write-Host "  *" -ForegroundColor Yellow -NoNewline }
        Write-Host ""
        Write-Host "  $($script:ScrubStr.NUM) = $($script:ScrubStr.TOGGLE)   " -NoNewline
        Write-Host "a" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_ALL)   " -NoNewline
        Write-Host "n" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_NONE)   " -NoNewline
        Write-Host "d" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_RESET)   " -NoNewline
        Write-Host "p" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.PRESET_MANAGE)"
        Write-Host "  " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.SAVE)   " -NoNewline
        Write-Host "r" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.MOD_RUN_NOW)   " -NoNewline
        Write-Host "f" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.CFG_F_FREQ)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)   " -NoNewline
        Write-Host "[!]" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.CFG_CAUTION_LBL)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "ok") {
            Save-Config
            foreach ($key in $toggles.Keys) { $original[$key] = $toggles[$key] }
            Write-Host "  $($script:ScrubStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            continue
        }

        if ($raw -eq "r") {
            Save-Config
            foreach ($key in $toggles.Keys) { $original[$key] = $toggles[$key] }
            Write-ScrubHeader
            Write-Host "  $($script:ScrubStr.SPEC_DRY)" -ForegroundColor White
            Write-Host "  $($script:ScrubStr.SPEC_LIVE)" -ForegroundColor Yellow
            Write-Host "  $($script:ScrubStr.SPEC_CANCEL)"
            Write-Host ""
            $mode = (Read-Host "  $($script:ScrubStr.SPEC_MODE)").Trim().ToUpper()
            if ($mode -eq $script:ScrubStr.SPEC_CANCEL_CHR) { continue }
            $dry = ($mode -ne "L")
            if (-not $dry) {
                $c = Read-Host "  $($script:ScrubStr.CONFIRM_LIVE -f $script:ScrubStr.CONFIRM_WORD)"
                if ($c -ne $script:ScrubStr.CONFIRM_WORD) {
                    Write-Host "  $($script:ScrubStr.CANCELED)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
            }
            Write-ScrubHeader
            $res = Invoke-ScrubCustom -Toggles $toggles -DryRun $dry
            $hist = Get-ScrubHistory
            Save-ScrubHistory -History $hist -Keys ($toggles.Keys | Where-Object { $toggles[$_] })
            $history = Get-ScrubHistory
            Show-RunSummary -Results $res -DryRun $dry
            Open-LatestReport
            $Host.UI.RawUI.FlushInputBuffer()
            Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
            continue
        }

        if ($raw -eq "a")  { foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $true  }; continue }
        if ($raw -eq "n")  { foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $false }; continue }
        if ($raw -eq "d")  { foreach ($key in $original.Keys) { $toggles[$key] = $original[$key] }; continue }
        if ($raw -eq "p")  { Show-PresetManager -CurrentToggles $toggles; continue }

        if ($raw -eq "f") { Show-FreqConfig; continue }

        if ($raw -eq "c") {
            if ($dirty) {
                Write-Host "  $($script:ScrubStr.MOD_UNSAVED)" -ForegroundColor Yellow
                $confirm = (Read-Host "  >").Trim().ToLower()
                if ($confirm -ne "y" -and $confirm -ne "s") { continue }
            }
            return
        }

        foreach ($part in ($raw -split '\s+')) {
            $n = 0
            if ([int]::TryParse($part, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
                $toggles[$script:CATALOG[$n - 1].Key] = -not $toggles[$script:CATALOG[$n - 1].Key]
            }
        }
    }
}

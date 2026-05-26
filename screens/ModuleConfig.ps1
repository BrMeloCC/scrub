function Show-BrowserConfig {
    param([string] $CfgPath, [PSCustomObject] $Cfg)
    $browsers = [ordered]@{
        chrome  = [bool]$Cfg.browser_cache.chrome
        edge    = [bool]$Cfg.browser_cache.edge
        firefox = [bool]$Cfg.browser_cache.firefox
    }
    $installed = @{
        chrome  = Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
        edge    = Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
        firefox = Test-Path "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    }
    $labels = [ordered]@{ chrome = "Chrome"; edge = "Edge"; firefox = "Firefox" }
    $keys   = @("chrome", "edge", "firefox")

    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.BROWSER_TITLE)" -ForegroundColor White
        Write-Host ""
        for ($i = 0; $i -lt $keys.Count; $i++) {
            $k    = $keys[$i]
            $on   = $browsers[$k]
            $box  = if ($on) { "[X]" } else { "[ ]" }
            $col  = if ($on) { "Green" } else { "DarkGray" }
            $inst = if ($installed[$k]) { $script:ScrubStr.BROWSER_INST } else { $script:ScrubStr.BROWSER_NA }
            $instCol = if ($installed[$k]) { "DarkGray" } else { "DarkGray" }
            Write-Host ("  " + "$($i + 1)  ") -NoNewline
            Write-Host $box -ForegroundColor $col -NoNewline
            Write-Host ("  " + $labels[$k].PadRight(10)) -ForegroundColor White -NoNewline
            Write-Host $inst -ForegroundColor $instCol
        }
        Write-Host ""
        Write-Host ("  " + ("-" * 40)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.BROWSER_HINT)" -ForegroundColor DarkGray
        Write-Host ""
        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "ok") {
            $Cfg.browser_cache | Add-Member -MemberType NoteProperty -Name "chrome"  -Value $browsers["chrome"]  -Force
            $Cfg.browser_cache | Add-Member -MemberType NoteProperty -Name "edge"    -Value $browsers["edge"]    -Force
            $Cfg.browser_cache | Add-Member -MemberType NoteProperty -Name "firefox" -Value $browsers["firefox"] -Force
            $Cfg | ConvertTo-Json -Depth 10 | Set-Content $CfgPath -Encoding UTF8
            return
        }
        if ($raw -eq "c") { return }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $keys.Count) {
            $k = $keys[$n - 1]
            $browsers[$k] = -not $browsers[$k]
        }
    }
}

function Show-DevScanPaths {
    param([string] $CfgPath, [PSCustomObject] $Cfg)
    if (-not $Cfg.dev_cleanup) {
        $Cfg | Add-Member -MemberType NoteProperty -Name "dev_cleanup" -Value ([PSCustomObject]@{ scan_paths = @(); min_age_days = 30 }) -Force
    }
    $paths  = [System.Collections.Generic.List[string]]::new()
    $srcPaths = @($Cfg.dev_cleanup.scan_paths)
    foreach ($p in $srcPaths) { if ($p) { $paths.Add($p) } }
    $minAge = if ($Cfg.dev_cleanup.min_age_days) { [int]$Cfg.dev_cleanup.min_age_days } else { 30 }

    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.DEV_PATHS_TITLE)" -ForegroundColor White
        Write-Host ""
        if ($paths.Count -eq 0) {
            Write-Host "  $($script:ScrubStr.DEV_PATHS_NONE)" -ForegroundColor DarkGray
        } else {
            for ($i = 0; $i -lt $paths.Count; $i++) {
                Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
                Write-Host $paths[$i] -ForegroundColor White
            }
        }
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.DEV_PATHS_AGE) " -NoNewline
        Write-Host $minAge -ForegroundColor Cyan -NoNewline
        Write-Host "  (e = edit)"
        Write-Host "  $($script:ScrubStr.DEV_PATHS_ADD)   " -NoNewline
        Write-Host "$($script:ScrubStr.DEV_PATHS_REMOVE)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.SAVE)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "ok") {
            $Cfg.dev_cleanup | Add-Member -MemberType NoteProperty -Name "scan_paths"   -Value @($paths) -Force
            $Cfg.dev_cleanup | Add-Member -MemberType NoteProperty -Name "min_age_days" -Value $minAge   -Force
            $Cfg | ConvertTo-Json -Depth 10 | Set-Content $CfgPath -Encoding UTF8
            Write-Host "  $($script:ScrubStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Milliseconds 700
            return
        }
        if ($raw -eq "c") { return }
        if ($raw -eq "a") {
            $newPath = (Read-Host "  $($script:ScrubStr.DEV_PATHS_PATH_P)").Trim()
            if ($newPath -and (Test-Path $newPath)) {
                $paths.Add($newPath)
            } elseif ($newPath) {
                Write-Host "  $($script:ScrubStr.NOT_FOUND)" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 700
            }
            continue
        }
        if ($raw -eq "e") {
            $ageRaw = (Read-Host "  $($script:ScrubStr.DEV_PATHS_AGE_P)").Trim()
            $ageVal = 0
            if ($ageRaw -ne "" -and [int]::TryParse($ageRaw, [ref]$ageVal) -and $ageVal -ge 1) { $minAge = $ageVal }
            continue
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $paths.Count) {
            $target = $paths[$n - 1]
            Write-Host "  $($script:ScrubStr.SPEC_CANCEL)? (s/N) " -NoNewline
            $conf = (Read-Host "  '$target'").Trim().ToLower()
            if ($conf -eq "s" -or $conf -eq "y") { $paths.RemoveAt($n - 1) }
        }
    }
}

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
        Write-Host "b" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.BROWSER_TITLE)   " -NoNewline
        Write-Host "v" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.DEV_PATHS_TITLE)   " -NoNewline
        Write-Host "t" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.THR_TITLE)   " -NoNewline
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

        if ($raw -eq "b") { Show-BrowserConfig -CfgPath $cfgPath -Cfg $cfg; continue }

        if ($raw -eq "v") { Show-DevScanPaths -CfgPath $cfgPath -Cfg $cfg; continue }

        if ($raw -eq "t") { Show-ThresholdsConfig; continue }

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

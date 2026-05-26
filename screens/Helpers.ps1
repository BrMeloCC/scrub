function Set-ScrubLanguage {
    param([string]$Lang)
    $langFile = Join-Path $moduleRoot "strings\$Lang.ps1"
    if (Test-Path $langFile) {
        $script:ScrubLang = $Lang
        . $langFile
        Set-Content $script:ScrubLangFile -Value $Lang -Encoding UTF8
        Write-Host "  $($script:ScrubStr.LANG_SWITCHED)" -ForegroundColor Green
        Start-Sleep -Milliseconds 700
    }
}

function Switch-ScrubLanguage {
    $next = if ($script:ScrubLang -eq "pt") { "en" } else { "pt" }
    Set-ScrubLanguage -Lang $next
}

# ── Utilitarios ───────────────────────────────────────────────────────────────

function Write-ScrubHeader {
    Clear-Host
    Write-Host ""
    Write-Host "  $($script:ScrubStr.APP_NAME)" -ForegroundColor Cyan -NoNewline
    Write-Host "  --  $($script:ScrubStr.APP_TAGLINE)" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host ""
}

function Open-LatestReport {
    $dir = Join-Path $moduleRoot "reports"
    $f = Get-ChildItem $dir -Filter "*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { Start-Process $f.FullName }
}

function Read-ScrubConfig {
    $path = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    return (ConvertFrom-Json -InputObject (Get-Content $path -Raw))
}

function Format-EstSecs {
    param([int] $Secs)
    if ($Secs -lt 60)   { return "~${Secs}s" }
    if ($Secs -lt 3600) { return "~$([int][Math]::Ceiling($Secs / 60))min" }
    return "~$([math]::Round($Secs / 3600, 1))h"
}

function Get-ScrubHistory {
    $p = Join-Path $moduleRoot "run_history.json"
    if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) }
    return [PSCustomObject]@{ last_runs = [PSCustomObject]@{} }
}

function Save-ScrubHistory {
    param([PSCustomObject] $History, [string[]] $Keys)
    $now = (Get-Date -Format "o")
    foreach ($k in $Keys) {
        $History.last_runs | Add-Member -MemberType NoteProperty -Name $k -Value $now -Force
    }
    $History | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $moduleRoot "run_history.json") -Encoding UTF8
}

function Get-EffectiveSchedule {
    param([string] $Key, [PSCustomObject] $Cfg, [PSCustomObject] $CatalogEntry)
    $s = if ($Cfg.schedule) { $Cfg.schedule.$Key } else { $null }
    [int]$freqDays = if ($s -and $null -ne $s.freq_days) { $s.freq_days } else { $CatalogEntry.FreqDays }
    [int]$estSecs  = if ($s -and $null -ne $s.est_secs)  { $s.est_secs  } else { $CatalogEntry.EstSecs  }
    return @{ FreqDays = $freqDays; EstSecs = $estSecs }
}

function Get-FreqLabel {
    param([int] $Days)
    switch ($Days) {
        1   { return $script:ScrubStr.FREQ_DAILY }
        7   { return $script:ScrubStr.FREQ_WEEKLY }
        30  { return $script:ScrubStr.FREQ_MONTHLY }
        180 { return $script:ScrubStr.FREQ_BIANNUAL }
        default { return "${Days}d" }
    }
}

function Get-ActiveToggles {
    if ($script:ActivePreset -eq "customizado") {
        $cfg = Read-ScrubConfig
        $t = @{}
        foreach ($m in $script:CATALOG) {
            $v = $cfg.modules.($m.Key)
            $t[$m.Key] = if ($null -eq $v) { $false } else { [bool]$v }
        }
        return $t
    }
    return $script:PRESETS[$script:ActivePreset]
}

function Get-PresetLabel { return $script:ActivePreset.Substring(0,1).ToUpper() + $script:ActivePreset.Substring(1) }

function Step-ActivePreset {
    $keys = @($script:PRESETS.Keys)
    $idx  = [Array]::IndexOf($keys, $script:ActivePreset)
    $script:ActivePreset = $keys[($idx + 1) % $keys.Count]
}

# ── Run com selecao de modulos ─────────────────────────────────────────────────

function Invoke-ScrubCustom {
    param([hashtable] $Toggles, [bool] $DryRun)
    $cfg = Read-ScrubConfig
    foreach ($key in $Toggles.Keys) {
        $cfg.modules | Add-Member -MemberType NoteProperty -Name $key -Value $Toggles[$key] -Force
    }
    $tmp = Join-Path $env:TEMP "scrub_$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8
    try   { return Invoke-Scrub -ConfigPath $tmp -DryRun $DryRun }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

# ── Admin elevation helpers ───────────────────────────────────────────────────

$script:ADMIN_MODULES = @("system_repair", "windows_update_cache")

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Get-AdminConflicts {
    param([hashtable] $Toggles)
    if (Test-IsAdmin) { return @() }
    return @($script:ADMIN_MODULES | Where-Object { $Toggles[$_] -eq $true })
}

function Show-AdminPrompt {
    param([string[]] $Conflicts)
    Write-Host ""
    Write-Host "  [!] $($script:ScrubStr.ADMIN_WARN): " -NoNewline -ForegroundColor Yellow
    Write-Host ($Conflicts -join ", ") -ForegroundColor White
    Write-Host ""
    Write-Host "  [R] $($script:ScrubStr.ADMIN_RELAUNCH)" -ForegroundColor Cyan
    Write-Host "  [C] $($script:ScrubStr.ADMIN_CONTINUE)" -ForegroundColor DarkGray
    Write-Host ""
    $k = (Read-Host "  [R/C]").Trim().ToUpper()
    if ($k -eq "R") {
        Start-Process powershell.exe -Verb RunAs `
            -ArgumentList "-NoLogo -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`""
        exit
    }
}

function Get-CachedHealthScore {
    $p = Join-Path $moduleRoot "health_history.json"
    $hist = Get-HealthHistory -HistoryPath $p
    if ($hist.Count -eq 0) { return $null }
    $last = $hist[-1]
    $prev = if ($hist.Count -ge 2) { $hist[-2] } else { $null }
    $trend = if ($prev) {
        $delta = $last.score - $prev.score
        if     ($delta -gt 2)  { [char]8593 }   # ↑
        elseif ($delta -lt -2) { [char]8595 }   # ↓
        else                   { [char]8594 }   # →
    } else { "" }
    return [PSCustomObject]@{ Score = [int]$last.score; Trend = $trend }
}

function Format-ScoreColor {
    param([int]$Score)
    if ($Score -ge 80) { return "Green"  }
    if ($Score -ge 60) { return "Yellow" }
    return "Red"
}

function ConvertTo-Sparkline {
    param([double[]]$Values, [int]$Width = 8)
    $blocks = [char[]](0x2581,0x2582,0x2583,0x2584,0x2585,0x2586,0x2587,0x2588)
    if ($Values.Count -eq 0) { return " " * $Width }
    $slice = if ($Values.Count -gt $Width) { $Values[($Values.Count - $Width)..($Values.Count - 1)] } else { $Values }
    $min  = ($slice | Measure-Object -Minimum).Minimum
    $max  = ($slice | Measure-Object -Maximum).Maximum
    $range = $max - $min
    $line = ""
    foreach ($v in $slice) {
        $idx  = if ($range -gt 0) { [int][math]::Floor(($v - $min) / $range * 7) } else { 4 }
        $idx  = [math]::Max(0, [math]::Min(7, $idx))
        $line += $blocks[$idx]
    }
    while ($line.Length -lt $Width) { $line = " " + $line }
    return $line
}

function Format-SizeBar {
    param([long]$Bytes, [long]$Total, [int]$Width = 20)
    if ($Total -le 0) { return " " * $Width }
    $filled = [int][math]::Round($Width * $Bytes / $Total)
    $filled = [math]::Max(0, [math]::Min($Width, $filled))
    return ([string][char]9608 * $filled) + ([string][char]9617 * ($Width - $filled))
}

function Invoke-DrivePickerMenu {
    $drives = @([System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady })
    Clear-Host
    Write-ScrubHeader
    Write-Host "  $($script:ScrubStr.DRV_TITLE)" -ForegroundColor White
    Write-Host ""
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d        = $drives[$i]
        $freeStr  = ConvertTo-ScrubBytes $d.AvailableFreeSpace
        $totalStr = ConvertTo-ScrubBytes $d.TotalSize
        Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
        Write-Host $d.Name.TrimEnd('\').PadRight(6) -ForegroundColor White -NoNewline
        Write-Host "$freeStr $($script:ScrubStr.DRV_FREE_OF) $totalStr" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host "  [1-$($drives.Count)] escolher   " -NoNewline
    Write-Host "0" -ForegroundColor DarkGray -NoNewline
    Write-Host " = cancelar"
    Write-Host ""
    $sel  = (Read-Host "  >").Trim()
    $selN = 0
    if ($sel -ne "0" -and [int]::TryParse($sel, [ref]$selN) -and $selN -ge 1 -and $selN -le $drives.Count) {
        return $drives[$selN - 1].RootDirectory.FullName
    }
    return $null
}

#Requires -Version 5.1
<#
.SYNOPSIS
    Entry point para o Scrub. Sem flags exibe um menu interativo.
.DESCRIPTION
    Modo script (flags diretos, sem menu):
      .\Run-Scrub.ps1 -NoMenu              # dry-run silencioso
      .\Run-Scrub.ps1 -Live                # deleta de verdade
      .\Run-Scrub.ps1 -ReportOnly          # so analise, abre relatorio
      .\Run-Scrub.ps1 -ConfigPath C:\x.json
#>
param(
    [switch] $Live,
    [switch] $ReportOnly,
    [string] $ConfigPath = "",
    [switch] $NoMenu,
    [switch] $Watch,
    [int]    $WatchInterval = 30
)

$ErrorActionPreference = "Stop"
$moduleRoot = $PSScriptRoot
Import-Module (Join-Path $moduleRoot "scrub.psd1") -Force

# ── Idioma ────────────────────────────────────────────────────────────────────

$script:FaxLangFile = Join-Path $moduleRoot "lang.txt"
$script:FaxLang = if (Test-Path $script:FaxLangFile) { (Get-Content $script:FaxLangFile -Raw).Trim() } else { "pt" }
. (Join-Path $moduleRoot "strings\$script:FaxLang.ps1")

function Set-FaxLanguage {
    param([string]$Lang)
    $langFile = Join-Path $moduleRoot "strings\$Lang.ps1"
    if (Test-Path $langFile) {
        $script:FaxLang = $Lang
        . $langFile
        Set-Content $script:FaxLangFile -Value $Lang -Encoding UTF8
        Write-Host "  $($script:FaxStr.LANG_SWITCHED)" -ForegroundColor Green
        Start-Sleep -Milliseconds 700
    }
}

function Switch-FaxLanguage {
    $next = if ($script:FaxLang -eq "pt") { "en" } else { "pt" }
    Set-FaxLanguage -Lang $next
}

# ── Utilitarios ───────────────────────────────────────────────────────────────

function Write-FaxHeader {
    Clear-Host
    Write-Host ""
    Write-Host "  $($script:FaxStr.APP_NAME)" -ForegroundColor Cyan -NoNewline
    Write-Host "  --  $($script:FaxStr.APP_TAGLINE)" -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host ""
}

function Open-LatestReport {
    $dir = Join-Path $moduleRoot "reports"
    $f = Get-ChildItem $dir -Filter "*.html" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { Start-Process $f.FullName }
}

function Read-FaxConfig {
    $path = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    return (ConvertFrom-Json -InputObject (Get-Content $path -Raw))
}

function Format-EstSecs {
    param([int] $Secs)
    if ($Secs -lt 60)   { return "~${Secs}s" }
    if ($Secs -lt 3600) { return "~$([int][Math]::Ceiling($Secs / 60))min" }
    return "~$([math]::Round($Secs / 3600, 1))h"
}

function Get-FaxHistory {
    $p = Join-Path $moduleRoot "run_history.json"
    if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) }
    return [PSCustomObject]@{ last_runs = [PSCustomObject]@{} }
}

function Save-FaxHistory {
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
        1   { return $script:FaxStr.FREQ_DAILY }
        7   { return $script:FaxStr.FREQ_WEEKLY }
        30  { return $script:FaxStr.FREQ_MONTHLY }
        180 { return $script:FaxStr.FREQ_BIANNUAL }
        default { return "${Days}d" }
    }
}

# ── Catalogo de modulos ───────────────────────────────────────────────────────
# Disco e saude do disco sempre rodam -- nao estao aqui.

$script:CATALOG = @(
    [PSCustomObject]@{ Key = "temp_cleaner";         Label = "Temp Cleaner";    Risk = $false; FreqDays = 1;   EstSecs = 10;   Desc = "arquivos temporarios (%TEMP%, C:\Windows\Temp)";        Detail = "Apaga arquivos com +3 dias em %TEMP% e C:\Windows\Temp. Rapido e seguro." }
    [PSCustomObject]@{ Key = "recycle_bin";          Label = "Recycle Bin";     Risk = $false; FreqDays = 1;   EstSecs = 5;    Desc = "itens antigos da Lixeira";                               Detail = "Remove da Lixeira itens com +30 dias. Apenas do usuario atual." }
    [PSCustomObject]@{ Key = "hiberfil_cleaner";     Label = "Hiberfil";        Risk = $true;  FreqDays = 30;  EstSecs = 2;    Desc = "hibernacao e Fast Startup (hiberfil.sys)";               Detail = "Desativa hibernacao e Fast Startup permanentemente. Libera 4-16GB. Boot ~5s mais lento." }
    [PSCustomObject]@{ Key = "restore_point";        Label = "Restore Point";   Risk = $false; FreqDays = 1;   EstSecs = 5;    Desc = "cria ponto de restauracao antes da limpeza (live)";      Detail = "Cria ponto de restauracao do sistema antes de limpar (live). Limite: 1 por dia." }
    [PSCustomObject]@{ Key = "browser_cache";        Label = "Browser Cache";   Risk = $false; FreqDays = 7;   EstSecs = 15;   Desc = "cache do Chrome, Edge e Firefox";                        Detail = "Limpa cache de paginas do Chrome, Edge e Firefox (+7 dias). Logins preservados." }
    [PSCustomObject]@{ Key = "large_file_finder";    Label = "Large Files";     Risk = $false; FreqDays = 7;   EstSecs = 30;   Desc = "arquivos grandes acima de 100MB (so relatorio)";         Detail = "Lista os 50 maiores arquivos do disco (acima de 100MB). Apenas leitura." }
    [PSCustomObject]@{ Key = "downloads_audit";      Label = "Downloads Audit"; Risk = $false; FreqDays = 7;   EstSecs = 10;   Desc = "downloads antigos sem uso (so relatorio)";               Detail = "Lista arquivos em Downloads com +60 dias sem acesso. Apenas relatorio." }
    [PSCustomObject]@{ Key = "duplicate_finder";     Label = "Dupl. Finder";    Risk = $true;  FreqDays = 30;  EstSecs = 300;  Desc = "duplicatas por hash SHA256 (lento)";                     Detail = "Encontra arquivos identicos por SHA256. Muito lento em discos grandes. Apenas relatorio." }
    [PSCustomObject]@{ Key = "driver_audit";         Label = "Driver Audit";    Risk = $false; FreqDays = 7;   EstSecs = 15;   Desc = "dispositivos com problema, rescan de drivers (live)";    Detail = "Verifica dispositivos com erro ou driver ausente. Live: dispara rescan do PnP." }
    [PSCustomObject]@{ Key = "event_log_scan";       Label = "Event Log Scan";  Risk = $false; FreqDays = 1;   EstSecs = 10;   Desc = "erros criticos no log do Windows (ultimos 7 dias)";      Detail = "Busca erros criticos nos logs do sistema dos ultimos 7 dias. Apenas leitura." }
    [PSCustomObject]@{ Key = "startup_audit";        Label = "Startup Audit";   Risk = $false; FreqDays = 7;   EstSecs = 5;    Desc = "programas e tarefas de inicializacao";                   Detail = "Lista programas e tarefas que iniciam com o Windows. Apenas relatorio." }
    [PSCustomObject]@{ Key = "system_log_clean";     Label = "System Logs";     Risk = $false; FreqDays = 7;   EstSecs = 5;    Desc = "logs CBS, minidumps, WER, MEMORY.DMP";                   Detail = "Remove logs de instalacao (CBS), minidumps de BSOD e arquivos WER. Seguro." }
    [PSCustomObject]@{ Key = "node_cache_clean";     Label = "Node Cache";      Risk = $false; FreqDays = 7;   EstSecs = 5;    Desc = "cache npm, yarn e pnpm";                                  Detail = "Limpa cache do npm, yarn e pnpm. Recriado automaticamente no proximo install." }
    [PSCustomObject]@{ Key = "system_repair";        Label = "System Repair";   Risk = $true;  FreqDays = 30;  EstSecs = 1800; Desc = "SFC + DISM health check/repair (admin, lento)";          Detail = "SFC + DISM: repara arquivos do sistema corrompidos. 30-60 min. Requer admin." }
    [PSCustomObject]@{ Key = "disk_optimize";        Label = "Disk Optimize";   Risk = $false; FreqDays = 7;   EstSecs = 30;   Desc = "TRIM em SSDs, desfragmentacao em HDDs";                  Detail = "TRIM em SSDs (preserva vida util), desfragmentacao em HDDs. Dry-run so relata." }
    [PSCustomObject]@{ Key = "windows_update_check"; Label = "Windows Update";  Risk = $false; FreqDays = 1;   EstSecs = 20;   Desc = "verifica e dispara atualizacoes pendentes";               Detail = "Consulta atualizacoes pendentes. Live: inicia download em background via UsoClient." }
    [PSCustomObject]@{ Key = "windows_update_cache"; Label = "WU Cache";        Risk = $false; FreqDays = 30;  EstSecs = 15;   Desc = "cache do Windows Update (requer admin)";                  Detail = "Para servico WU, apaga cache SoftwareDistribution e reinicia. Requer admin." }
    [PSCustomObject]@{ Key = "dev_project_clean";    Label = "Dev Cleanup";     Risk = $false; FreqDays = 7;   EstSecs = 60;   Desc = "pastas de build/deps de projetos dev inativos";           Detail = "Apaga node_modules, .venv, target/, bin/obj etc. de projetos sem uso. Configure scan_paths." }
    [PSCustomObject]@{ Key = "software_audit";       Label = "Software Audit";  Risk = $false; FreqDays = 7;   EstSecs = 5;    Desc = "software instalado recentemente (so relatorio)";          Detail = "Lista software instalado nos ultimos 30 dias via registro. Apenas relatorio." }
)

# ── Presets de modulos ────────────────────────────────────────────────────────

$script:ActivePreset = "customizado"

$script:PRESETS = [ordered]@{
    customizado = $null
    diagnostico = @{
        large_file_finder = $true; downloads_audit = $true; event_log_scan = $true
        startup_audit = $true; driver_audit = $true; disk_optimize = $true
        windows_update_check = $true; software_audit = $true
        duplicate_finder = $false; dev_project_clean = $false
        temp_cleaner = $false; recycle_bin = $false; browser_cache = $false
        system_log_clean = $false; node_cache_clean = $false
        windows_update_cache = $false; hiberfil_cleaner = $false
        system_repair = $false; restore_point = $false
    }
    limpeza = @{
        temp_cleaner = $true; recycle_bin = $true; browser_cache = $true
        system_log_clean = $true; node_cache_clean = $true; restore_point = $true
        disk_optimize = $true; windows_update_check = $true
        large_file_finder = $true; downloads_audit = $true; event_log_scan = $true
        startup_audit = $true; driver_audit = $true; dev_project_clean = $true
        software_audit = $false; duplicate_finder = $false
        hiberfil_cleaner = $false; system_repair = $false; windows_update_cache = $false
    }
}

function Get-ActiveToggles {
    if ($script:ActivePreset -eq "customizado") {
        $cfg = Read-FaxConfig
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

function Invoke-FaxCustom {
    param([hashtable] $Toggles, [bool] $DryRun)
    $cfg = Read-FaxConfig
    foreach ($key in $Toggles.Keys) {
        $cfg.modules | Add-Member -MemberType NoteProperty -Name $key -Value $Toggles[$key] -Force
    }
    $tmp = Join-Path $env:TEMP "scrub_$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $tmp -Encoding UTF8
    try   { Invoke-Scrub -ConfigPath $tmp -DryRun $DryRun }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

# ── Rotina inteligente ────────────────────────────────────────────────────────

function Show-SmartRoutine {
    $cfg      = Read-FaxConfig
    $toggles  = Get-ActiveToggles
    $history  = Get-FaxHistory
    $now      = Get-Date

    $due  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $skip = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($m in $script:CATALOG) {
        if (-not $toggles[$m.Key]) { continue }

        $sched       = Get-EffectiveSchedule -Key $m.Key -Cfg $cfg -CatalogEntry $m
        $lastRunRaw  = $history.last_runs.($m.Key)
        $isDue       = $true
        $lastDisplay = $script:FaxStr.NEVER
        $agoDisplay  = ""

        if ($lastRunRaw) {
            $lastDt      = [datetime]$lastRunRaw
            $elapsedH    = ($now - $lastDt).TotalHours
            $elapsedD    = ($now - $lastDt).TotalDays
            $lastDisplay = $lastDt.ToString("dd/MM HH:mm")
            $agoDisplay  = if ($elapsedH -lt 24) { $script:FaxStr.DAYS_AGO_H -f [int]$elapsedH } else { $script:FaxStr.DAYS_AGO_D -f [int]$elapsedD }
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
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.SMART_TITLE)" -ForegroundColor White
        Write-Host ""

        # ── Nada a fazer ──
        if ($due.Count -eq 0 -and -not $forceAll) {
            Write-Host "  $($script:FaxStr.SMART_ALL_DONE)" -ForegroundColor Green
            $latest = Get-ChildItem (Join-Path $moduleRoot "reports") -Filter "*.html" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                Write-Host "  $($script:FaxStr.SMART_LAST_RPT) $($latest.LastWriteTime.ToString('dd/MM/yyyy HH:mm'))" -ForegroundColor DarkGray
            }
            Write-Host ""
            Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
            Write-Host "  " -NoNewline; Write-Host "V" -ForegroundColor Cyan -NoNewline
            Write-Host " = $($script:FaxStr.SMART_V)   " -NoNewline
            Write-Host "R" -ForegroundColor Yellow -NoNewline
            Write-Host " = $($script:FaxStr.SMART_R)   " -NoNewline
            Write-Host "C" -ForegroundColor DarkGray -NoNewline
            Write-Host " = $($script:FaxStr.BACK)"
            Write-Host ""
            $raw = (Read-Host "  >").Trim().ToUpper()
            if ($raw -eq "V") { Open-LatestReport; continue }
            if ($raw -eq "R") { $forceAll = $true; continue }
            return
        }

        # ── Lista de modulos devidos ──
        if ($forceAll) {
            Write-Host "  $($script:FaxStr.SMART_FORCED)" -ForegroundColor Yellow
            Write-Host ""
        } else {
            Write-Host "  $($script:FaxStr.SMART_READY)" -ForegroundColor White
            Write-Host ""
            foreach ($e in $due) {
                $t   = (Format-EstSecs $e.EstSecs).PadRight(7)
                $ago = if ($e.AgoDisplay) { $e.AgoDisplay } else { $script:FaxStr.NEVER_RUN }
                Write-Host ("    " + $e.Module.Label.PadRight(18)) -ForegroundColor Cyan -NoNewline
                Write-Host ($e.FreqLabel.PadRight(10)) -ForegroundColor DarkGray -NoNewline
                Write-Host $t -ForegroundColor White -NoNewline
                Write-Host "$($script:FaxStr.LAST_RUN) $ago" -ForegroundColor DarkGray
            }
            if ($skip.Count -gt 0) {
                Write-Host ""
                Write-Host "  $($script:FaxStr.SMART_SKIP -f $skip.Count)" -ForegroundColor DarkGray
                foreach ($e in $skip) {
                    Write-Host ("    " + $e.Module.Label.PadRight(18)) -ForegroundColor DarkGray -NoNewline
                    Write-Host "$($script:FaxStr.NEXT_IN) $($e.FreqLabel)  $($script:FaxStr.LAST_RUN) $($e.AgoDisplay)" -ForegroundColor DarkGray
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
        Write-Host "  $($script:FaxStr.SMART_EST) " -NoNewline
        Write-Host $estLabel -ForegroundColor $(if ($dispSecs -gt 600) { "Yellow" } else { "Green" })
        if ($dispSecs -gt 1200) {
            Write-Host "  $($script:FaxStr.SMART_LONG_WARN)" -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  " -NoNewline; Write-Host "E" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:FaxStr.SMART_E)   " -NoNewline
        Write-Host "L" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.SMART_L)   " -NoNewline
        Write-Host "V" -ForegroundColor White -NoNewline
        Write-Host " = $($script:FaxStr.SMART_V)   " -NoNewline
        Write-Host "C" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToUpper()
        if ($raw -eq "C") { return }
        if ($raw -eq "V") { Open-LatestReport; continue }
        if ($raw -ne "E" -and $raw -ne "L") { continue }

        $dryRun = ($raw -ne "L")
        if (-not $dryRun) {
            $c = Read-Host "  $($script:FaxStr.CONFIRM_LIVE -f $script:FaxStr.CONFIRM_WORD)"
            if ($c -ne $script:FaxStr.CONFIRM_WORD) {
                Write-Host "  $($script:FaxStr.CANCELED)" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
        }

        Write-FaxHeader
        if ($forceAll) {
            Invoke-FaxCustom -Toggles $toggles -DryRun $dryRun
            $hist = Get-FaxHistory
            Save-FaxHistory -History $hist -Keys ($toggles.Keys | Where-Object { $toggles[$_] })
        } else {
            $toggles = @{}
            foreach ($m in $script:CATALOG) { $toggles[$m.Key] = $false }
            foreach ($e in $due)             { $toggles[$e.Module.Key] = $true }
            Invoke-FaxCustom -Toggles $toggles -DryRun $dryRun
            $hist = Get-FaxHistory
            Save-FaxHistory -History $hist -Keys ($due | ForEach-Object { $_.Module.Key })
        }

        Open-LatestReport
        Write-Host ""
        Read-Host "  $($script:FaxStr.PRESS_ENTER_MENU)" | Out-Null
        return
    }
}

# ── Submenu: selecao de modulos ────────────────────────────────────────────────

function Show-ModuleSelector {
    $src     = Get-ActiveToggles
    $toggles = @{}
    foreach ($key in $src.Keys) { $toggles[$key] = $src[$key] }

    while ($true) {
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.MOD_TITLE)" -ForegroundColor White
        Write-Host "  $($script:FaxStr.MOD_ALWAYS)" -ForegroundColor DarkGray
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

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.NUM) = $($script:FaxStr.TOGGLE)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:FaxStr.CONFIRM_ACT)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "ok") { return $toggles }
        if ($raw -eq "c")  { return $null }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
            $toggles[$script:CATALOG[$n - 1].Key] = -not $toggles[$script:CATALOG[$n - 1].Key]
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
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.CFG_FREQ_TITLE)" -ForegroundColor White
        Write-Host "  $($script:FaxStr.CFG_FREQ_DESC)" -ForegroundColor DarkGray
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
        Write-Host "  $($script:FaxStr.CFG_NUM_EDIT)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:FaxStr.SAVE)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host "  $($script:FaxStr.CFG_FREQ_DEFS)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "ok") {
            foreach ($key in $sched.Keys) {
                $entry = [PSCustomObject]@{ freq_days = $sched[$key].FreqDays; est_secs = $sched[$key].EstSecs }
                $cfg.schedule | Add-Member -MemberType NoteProperty -Name $key -Value $entry -Force
            }
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
            Write-Host "  $($script:FaxStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        if ($raw -eq "c") { return }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
            $key   = $script:CATALOG[$n - 1].Key
            $label = $script:CATALOG[$n - 1].Label
            Write-Host ""
            Write-Host "  $($script:FaxStr.CFG_EDITING) $label" -ForegroundColor Cyan
            Write-Host "  $($script:FaxStr.CFG_FREQ_CUR) $($sched[$key].FreqDays) $($script:FaxStr.DAYS)" -ForegroundColor DarkGray
            $fRaw = (Read-Host "  $($script:FaxStr.CFG_FREQ_NEW)").Trim()
            $fVal = 0
            if ([int]::TryParse($fRaw, [ref]$fVal) -and $fVal -ge 1) { $sched[$key].FreqDays = $fVal }
            Write-Host "  $($script:FaxStr.CFG_EST_CUR) $(Format-EstSecs $sched[$key].EstSecs)" -ForegroundColor DarkGray
            $eRaw = (Read-Host "  $($script:FaxStr.CFG_EST_NEW)").Trim()
            $eVal = 0
            if ($eRaw -ne "" -and [int]::TryParse($eRaw, [ref]$eVal) -and $eVal -ge 1) { $sched[$key].EstSecs = $eVal }
        }
    }
}

# ── Configuracao de modulos (ativar/desativar) ─────────────────────────────────

function Show-ModuleConfig {
    $cfgPath = if ($ConfigPath -and (Test-Path $ConfigPath)) { $ConfigPath } else { Join-Path $moduleRoot "config.json" }
    $cfg     = ConvertFrom-Json -InputObject (Get-Content $cfgPath -Raw)

    $toggles = @{}
    foreach ($m in $script:CATALOG) {
        $v = $cfg.modules.($m.Key)
        $toggles[$m.Key] = if ($null -eq $v) { $false } else { [bool]$v }
    }

    while ($true) {
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.CFG_MOD_TITLE)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.CFG_MOD_SUB -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.CFG_MOD_ALWAYS)" -ForegroundColor DarkGray
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
            Write-Host $m.Detail -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 62)) -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.NUM) = $($script:FaxStr.TOGGLE)   " -NoNewline
        Write-Host "ok" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:FaxStr.SAVE)   " -NoNewline
        Write-Host "f" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:FaxStr.CFG_F_FREQ)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.BACK)   " -NoNewline
        Write-Host "[!]" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.CFG_CAUTION_LBL)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "ok") {
            foreach ($key in $toggles.Keys) {
                $cfg.modules | Add-Member -MemberType NoteProperty -Name $key -Value $toggles[$key] -Force
            }
            $cfg | ConvertTo-Json -Depth 10 | Set-Content $cfgPath -Encoding UTF8
            Write-Host "  $($script:FaxStr.SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        if ($raw -eq "f") { Show-FreqConfig; continue }
        if ($raw -eq "c") { return }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $script:CATALOG.Count) {
            $toggles[$script:CATALOG[$n - 1].Key] = -not $toggles[$script:CATALOG[$n - 1].Key]
        }
    }
}

# ── Health score helpers ──────────────────────────────────────────────────────

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

# ── Gerenciador de Startup ────────────────────────────────────────────────────

function Show-StartupManager {
    while ($true) {
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.START_TITLE)" -ForegroundColor White
        Write-Host "  $($script:FaxStr.START_LOADING)" -ForegroundColor DarkGray
        $audit = Get-StartupAudit
        $items = @($audit.Items)

        if ($items.Count -eq 0) {
            Write-Host "  $($script:FaxStr.START_NONE)" -ForegroundColor DarkGray
            Write-Host ""
            Read-Host "  $($script:FaxStr.PRESS_ENTER)" | Out-Null
            return
        }

        Clear-Host
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.START_TITLE)  " -ForegroundColor White -NoNewline
        Write-Host "($($items.Count) $($script:FaxStr.START_ENTRIES))" -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $items.Count; $i++) {
            $it      = $items[$i]
            $enabled = $it.Enabled
            $box     = if ($enabled) { "[ON] " } else { "[OFF]" }
            $boxCol  = if ($enabled) { "Green" } else { "DarkGray" }
            $typeAbbr = switch ($it.Type) {
                "Registry"       { "REG" }
                "Scheduled Task" { "TSK" }
                "Startup Folder" { "DIR" }
                default          { "???" }
            }
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + " ") -NoNewline
            Write-Host $box -ForegroundColor $boxCol -NoNewline
            Write-Host " $typeAbbr " -ForegroundColor DarkGray -NoNewline
            Write-Host ($it.Name.PadRight(32)) -ForegroundColor White -NoNewline
            Write-Host $it.Scope -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.NUM) = $($script:FaxStr.TOGGLE)   " -NoNewline
        Write-Host "d" -ForegroundColor Cyan -NoNewline
        Write-Host "<N> = $($script:FaxStr.START_DETAIL)   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "0") { return }

        if ($raw -match '^d(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $items.Count) {
                $it = $items[$n - 1]
                Write-Host ""
                Write-Host "  $($script:FaxStr.START_NAME):    $($it.Name)"     -ForegroundColor White
                Write-Host "  $($script:FaxStr.START_TYPE):    $($it.Type)"     -ForegroundColor DarkGray
                Write-Host "  $($script:FaxStr.START_SCOPE):   $($it.Scope)"    -ForegroundColor DarkGray
                Write-Host "  $($script:FaxStr.START_CMD):  $($it.Command)"  -ForegroundColor DarkGray
                Write-Host "  $($script:FaxStr.START_LOC):   $($it.Location)" -ForegroundColor DarkGray
                Write-Host ""
                Read-Host "  $($script:FaxStr.PRESS_ENTER)" | Out-Null
            }
            continue
        }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
            $it = $items[$n - 1]
            if ($it.Enabled) {
                $c = Read-Host "  $($script:FaxStr.START_DISABLE -f $it.Name) ($($script:FaxStr.CONFIRM_WORD)/N)"
                if ($c -eq $script:FaxStr.CONFIRM_WORD) {
                    $res = Disable-StartupEntry -Entry $it
                    $col = if ($res.Success) { "Green" } else { "Red" }
                    Write-Host "  $($res.Message)" -ForegroundColor $col
                    Start-Sleep -Seconds 1
                }
            } else {
                $c = Read-Host "  $($script:FaxStr.START_ENABLE -f $it.Name) ($($script:FaxStr.CONFIRM_WORD)/N)"
                if ($c -eq $script:FaxStr.CONFIRM_WORD) {
                    $res = Enable-StartupEntry -Entry $it
                    $col = if ($res.Success) { "Green" } else { "Red" }
                    Write-Host "  $($res.Message)" -ForegroundColor $col
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

# ── Analisador de pastas ──────────────────────────────────────────────────────

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
    Write-FaxHeader
    Write-Host "  $($script:FaxStr.DRV_TITLE)" -ForegroundColor White
    Write-Host ""
    for ($i = 0; $i -lt $drives.Count; $i++) {
        $d        = $drives[$i]
        $freeStr  = ConvertTo-FaxBytes $d.AvailableFreeSpace
        $totalStr = ConvertTo-FaxBytes $d.TotalSize
        Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
        Write-Host $d.Name.TrimEnd('\').PadRight(6) -ForegroundColor White -NoNewline
        Write-Host "$freeStr $($script:FaxStr.DRV_FREE_OF) $totalStr" -ForegroundColor DarkGray
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

function Show-FolderAnalyzer {
    param([string]$StartPath = "")

    if (-not $StartPath) {
        Clear-Host
        Write-FaxHeader
        Write-Host "  $($script:FaxStr.FOLD_TITLE)" -ForegroundColor White
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "   1  " -NoNewline; Write-Host $script:FaxStr.FOLD_PROFILE -ForegroundColor White -NoNewline
        Write-Host "   $env:USERPROFILE" -ForegroundColor DarkGray
        Write-Host "   2  " -NoNewline; Write-Host $script:FaxStr.FOLD_DRIVE -ForegroundColor White
        Write-Host "   3  " -NoNewline; Write-Host $script:FaxStr.FOLD_TYPE_PATH -ForegroundColor White
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  [1-3]   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host ""
        $entry = (Read-Host "  >").Trim()
        switch ($entry) {
            "0" { return }
            "1" { $StartPath = $env:USERPROFILE }
            "2" {
                $picked = Invoke-DrivePickerMenu
                if (-not $picked) { return }
                $StartPath = $picked
            }
            "3" {
                $typed = (Read-Host "  $($script:FaxStr.FOLD_PATH_PROMPT)").Trim()
                if (Test-Path $typed -PathType Container) { $StartPath = $typed }
                else { Write-Host "  $($script:FaxStr.NOT_FOUND)" -ForegroundColor Yellow; Start-Sleep 1; return }
            }
            default { return }
        }
    }

    $currentPath = $StartPath
    $tree        = $null
    $page        = 0
    $pageSize    = 20

    while ($true) {
        if ($null -eq $tree) {
            Clear-Host
            Write-FaxHeader
            Write-Host "  $($script:FaxStr.FOLD_TITLE)  " -ForegroundColor White -NoNewline
            Write-Host $script:FaxStr.LOADING -ForegroundColor DarkGray
            $tree = Get-FolderTree -Path $currentPath
        }

        $children   = @($tree.Children)
        $totalPages = [math]::Max(1, [math]::Ceiling($children.Count / $pageSize))
        $page       = [math]::Min($page, $totalPages - 1)
        $pageStart  = $page * $pageSize
        $pageEnd    = [math]::Min($pageStart + $pageSize - 1, $children.Count - 1)
        $pageItems  = if ($children.Count -gt 0) { @($children[$pageStart..$pageEnd]) } else { @() }

        Clear-Host
        Write-Host "  $currentPath" -ForegroundColor Cyan
        $totalLabel = if ($tree.TotalBytes -gt 0) { "  $($script:FaxStr.FOLD_TOTAL) $(ConvertTo-FaxBytes $tree.TotalBytes)" } else { "" }
        Write-Host $totalLabel -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $pageItems.Count; $i++) {
            $c   = $pageItems[$i]
            $pct = if ($tree.TotalBytes -gt 0) { [int][math]::Round(100 * $c.SizeBytes / $tree.TotalBytes) } else { 0 }
            $bar = Format-SizeBar -Bytes $c.SizeBytes -Total $tree.TotalBytes
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
            Write-Host $bar -ForegroundColor Cyan -NoNewline
            Write-Host ("  " + "$pct%".PadLeft(4) + "  ") -ForegroundColor DarkGray -NoNewline
            Write-Host ($c.Name.PadRight(30)) -ForegroundColor White -NoNewline
            Write-Host (ConvertTo-FaxBytes $c.SizeBytes) -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        $canGoUp = (Split-Path $currentPath -Parent) -ne $currentPath -and (Split-Path $currentPath -Parent) -ne ""
        Write-Host "  [1-$($pageItems.Count)] $($script:FaxStr.FOLD_ENTER)   " -NoNewline
        if ($canGoUp) { Write-Host "U" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:FaxStr.FOLD_UP)   " -NoNewline }
        if ($totalPages -gt 1) {
            if ($page -lt $totalPages - 1) { Write-Host "N" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:FaxStr.FOLD_NEXT)   " -NoNewline }
            if ($page -gt 0)               { Write-Host "P" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:FaxStr.FOLD_PREV)   " -NoNewline }
            Write-Host "($($page+1)/$totalPages)" -ForegroundColor DarkGray -NoNewline
            Write-Host "   " -NoNewline
        }
        Write-Host "C" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:FaxStr.FOLD_PATH)   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:FaxStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "0") { return }
        if ($raw -eq "n" -and $page -lt $totalPages - 1) { $page++; continue }
        if ($raw -eq "p" -and $page -gt 0)               { $page--; continue }
        if ($raw -eq "u" -and $canGoUp) {
            $currentPath = Split-Path $currentPath -Parent
            $tree = $null; $page = 0; continue
        }
        if ($raw -eq "c") {
            $picked = Invoke-DrivePickerMenu
            if ($picked) { $currentPath = $picked; $tree = $null; $page = 0 }
            continue
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $pageItems.Count) {
            $currentPath = $pageItems[$n - 1].Path
            $tree = $null; $page = 0
        }
    }
}

# ── Historico e progresso ─────────────────────────────────────────────────────

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

function Show-History {
    $logDir  = Join-Path $moduleRoot "logs"
    $hsPath  = Join-Path $moduleRoot "health_history.json"

    Write-FaxHeader
    Write-Host "  $($script:FaxStr.HIST_TITLE)  " -ForegroundColor White -NoNewline
    Write-Host $script:FaxStr.LOADING -ForegroundColor DarkGray

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
    Write-FaxHeader
    Write-Host "  $($script:FaxStr.HIST_TITLE)" -ForegroundColor White
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
        Write-Host "($($hsHist.Count) $($script:FaxStr.HIST_MEASURES))" -ForegroundColor DarkGray
        Write-Host ""
    }

    # ── Free space trend ──
    $withFree = @($executions | Where-Object { $null -ne $_.FreeGB })
    if ($withFree.Count -ge 2) {
        Write-Host "  $($script:FaxStr.HIST_FREE -f [math]::Min($withFree.Count,10))" -ForegroundColor White
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
        Write-Host "  $($script:FaxStr.HIST_FREED -f [math]::Min($withFreed.Count,8))" -ForegroundColor White
        $slice   = if ($withFreed.Count -gt 8) { $withFreed[($withFreed.Count-8)..($withFreed.Count-1)] } else { $withFreed }
        $maxFreed = ($slice | Measure-Object -Property FreedBytes -Maximum).Maximum
        $barW    = 30
        foreach ($ex in $slice) {
            $filled = if ($maxFreed -gt 0) { [int][math]::Round($barW * $ex.FreedBytes / $maxFreed) } else { 0 }
            $bar    = ([string][char]9608 * $filled) + ([string][char]9617 * ($barW - $filled))
            $label  = $ex.Date.ToString("dd/MM")
            Write-Host ("  " + $label + "  ") -ForegroundColor DarkGray -NoNewline
            Write-Host $bar -ForegroundColor Yellow -NoNewline
            Write-Host ("  " + (ConvertTo-FaxBytes $ex.FreedBytes)) -ForegroundColor White
        }
        Write-Host ""
    }

    if ($executions.Count -eq 0 -and $hsHist.Count -eq 0) {
        Write-Host "  $($script:FaxStr.HIST_NO_DATA)" -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.HIST_NO_DATA2)" -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
    Write-Host ""
    Read-Host "  $($script:FaxStr.PRESS_ENTER)" | Out-Null
}

# ── Watch mode ────────────────────────────────────────────────────────────────

function Show-WatchMode {
    param([int]$IntervalSecs = 30)
    Write-Host ""
    Write-Host "  $($script:FaxStr.WATCH_STARTED -f $IntervalSecs)" -ForegroundColor DarkGray
    Start-Sleep -Seconds 1

    while ($true) {
        $diskResult    = Get-DiskReport -AlertUsagePct (Read-FaxConfig).alert_disk_usage_pct
        $rebootResult  = Get-PendingRebootCheck
        $cached        = Get-CachedHealthScore

        Clear-Host
        Write-Host ""
        Write-Host "  $($script:FaxStr.WATCH_TITLE)" -ForegroundColor Cyan -NoNewline
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
            Write-Host ("  " + "$pct%".PadLeft(4) + "  $($script:FaxStr.WATCH_USED)  ") -ForegroundColor DarkGray -NoNewline
            Write-Host "$($d.FreeGB) $($script:FaxStr.WATCH_FREE_GB)" -ForegroundColor White
        }
        Write-Host ""

        if ($rebootResult.RebootRequired) {
            Write-Host "  Reboot: " -NoNewline
            Write-Host $script:FaxStr.WATCH_PENDING -ForegroundColor Red -NoNewline
            Write-Host "  ($($rebootResult.Reasons -join ', '))" -ForegroundColor DarkGray
        } else {
            Write-Host "  Reboot: " -NoNewline
            Write-Host "OK" -ForegroundColor Green
        }

        $hist    = Get-FaxHistory
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
            $agoStr = if ($ago.TotalHours -lt 24) { $script:FaxStr.DAYS_AGO_H -f [int]$ago.TotalHours } else { $script:FaxStr.DAYS_AGO_D -f [int]$ago.TotalDays }
            Write-Host "  $($script:FaxStr.WATCH_LAST) " -NoNewline
            Write-Host $agoStr -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.WATCH_UPDATE -f $IntervalSecs)  " -ForegroundColor DarkGray -NoNewline
        Write-Host "Ctrl+C" -ForegroundColor DarkGray -NoNewline
        Write-Host " $($script:FaxStr.WATCH_EXIT)" -ForegroundColor DarkGray

        Start-Sleep -Seconds $IntervalSecs
    }
}

# ── Menu principal ─────────────────────────────────────────────────────────────

function Show-Menu {
    while ($true) {
        Write-FaxHeader
        $cached      = Get-CachedHealthScore
        $presetColor = switch ($script:ActivePreset) { "diagnostico" { "Cyan" } "limpeza" { "Yellow" } default { "White" } }

        if ($cached) {
            $sCol = Format-ScoreColor -Score $cached.Score
            Write-Host "  $($script:FaxStr.MENU_SCORE) " -NoNewline
            Write-Host "$($cached.Score)" -ForegroundColor $sCol -NoNewline
            if ($cached.Trend) { Write-Host "  $($cached.Trend)" -ForegroundColor DarkGray -NoNewline }
            Write-Host "     $($script:FaxStr.MENU_PRESET) " -NoNewline
        } else {
            Write-Host "  $($script:FaxStr.MENU_PRESET) " -NoNewline
        }
        Write-Host (Get-PresetLabel) -ForegroundColor $presetColor -NoNewline
        Write-Host "   " -NoNewline
        Write-Host "P" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:FaxStr.MENU_P_TOGGLE)" -ForegroundColor DarkGray
        Write-Host ""

        Write-Host "  $($script:FaxStr.MENU_1)" -ForegroundColor Cyan -NoNewline
        Write-Host $script:FaxStr.MENU_1_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_2)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_2_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_3)" -ForegroundColor Yellow -NoNewline
        Write-Host $script:FaxStr.MENU_3_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_4)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_4_DESC -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  $($script:FaxStr.MENU_5)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_5_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_6)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_6_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_7)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_7_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_8)" -ForegroundColor White -NoNewline
        Write-Host $script:FaxStr.MENU_8_DESC -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  $($script:FaxStr.MENU_9)" -ForegroundColor DarkGray -NoNewline
        Write-Host $script:FaxStr.MENU_9_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_A)" -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_B)" -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_I)" -ForegroundColor DarkGray -NoNewline
        Write-Host $script:FaxStr.MENU_I_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:FaxStr.MENU_0)"
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host ""

        switch ((Read-Host "  $($script:FaxStr.CHOOSE)").Trim().ToLower()) {

            "p" { Step-ActivePreset }

            "1" { Show-SmartRoutine }

            "2" {
                Write-FaxHeader
                $at = Get-ActiveToggles
                Invoke-FaxCustom -Toggles $at -DryRun $true
                $hist = Get-FaxHistory
                Save-FaxHistory -History $hist -Keys ($at.Keys | Where-Object { $at[$_] })
                Open-LatestReport
                Write-Host ""
                Read-Host "  $($script:FaxStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "3" {
                Write-FaxHeader
                $c = Read-Host "  $($script:FaxStr.CONFIRM_LIVE -f $script:FaxStr.CONFIRM_WORD)"
                if ($c -ne $script:FaxStr.CONFIRM_WORD) {
                    Write-Host "  $($script:FaxStr.CANCELED)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                Write-FaxHeader
                $at = Get-ActiveToggles
                Invoke-FaxCustom -Toggles $at -DryRun $false
                $hist = Get-FaxHistory
                Save-FaxHistory -History $hist -Keys ($at.Keys | Where-Object { $at[$_] })
                Open-LatestReport
                Write-Host ""
                Read-Host "  $($script:FaxStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "4" {
                $toggles = Show-ModuleSelector
                if ($null -eq $toggles) { continue }

                Write-FaxHeader
                Write-Host "  $($script:FaxStr.SPEC_DRY)" -ForegroundColor White
                Write-Host "  $($script:FaxStr.SPEC_LIVE)" -ForegroundColor Yellow
                Write-Host "  $($script:FaxStr.SPEC_CANCEL)"
                Write-Host ""

                $mode = (Read-Host "  $($script:FaxStr.SPEC_MODE)").Trim().ToUpper()
                if ($mode -eq $script:FaxStr.SPEC_CANCEL_CHR) { continue }

                $dry = ($mode -ne "L")
                if (-not $dry) {
                    $c = Read-Host "  $($script:FaxStr.CONFIRM_LIVE -f $script:FaxStr.CONFIRM_WORD)"
                    if ($c -ne $script:FaxStr.CONFIRM_WORD) {
                        Write-Host "  $($script:FaxStr.CANCELED)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }
                }

                Write-FaxHeader
                Invoke-FaxCustom -Toggles $toggles -DryRun $dry
                $hist = Get-FaxHistory
                Save-FaxHistory -History $hist -Keys ($toggles.Keys | Where-Object { $toggles[$_] })
                Open-LatestReport
                Write-Host ""
                Read-Host "  $($script:FaxStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "5" {
                $diag = @{}
                foreach ($m in $script:CATALOG) { $diag[$m.Key] = $false }
                $diag["driver_audit"]         = $true
                $diag["large_file_finder"]    = $true
                $diag["downloads_audit"]      = $true
                $diag["event_log_scan"]       = $true
                $diag["startup_audit"]        = $true
                $diag["hiberfil_cleaner"]     = $true
                $diag["windows_update_check"] = $true
                $diag["disk_optimize"]        = $true
                $diag["software_audit"]       = $true

                Write-FaxHeader
                Invoke-FaxCustom -Toggles $diag -DryRun $true
                Open-LatestReport
                Write-Host ""
                Read-Host "  $($script:FaxStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "6" { Show-StartupManager }

            "7" { Show-FolderAnalyzer }

            "8" { Show-History }

            "9" { Show-ModuleConfig }

            "i" { Switch-FaxLanguage }

            "a" {
                Write-FaxHeader
                $taskName = "Scrub_Daily"
                $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

                if ($existing) {
                    Write-Host "  $($script:FaxStr.SCHED_CURRENT) $taskName" -ForegroundColor White
                    Write-Host "  $($script:FaxStr.SCHED_STATUS) $($existing.State)  $($script:FaxStr.SCHED_NEXT_RUN) $((Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime)" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "  [R] $($script:FaxStr.SCHED_REMOVE)   [Q] $($script:FaxStr.BACK)"
                    Write-Host ""
                    $sub = (Read-Host "  >").Trim().ToUpper()
                    if ($sub -eq "R") {
                        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                        Write-Host "  $($script:FaxStr.SCHED_REMOVED)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                    }
                } else {
                    Write-Host "  $($script:FaxStr.SCHED_CREATE)" -ForegroundColor White
                    Write-Host "  $($script:FaxStr.SCHED_HINT)" -ForegroundColor DarkGray
                    Write-Host ""
                    $hora = (Read-Host "  $($script:FaxStr.SCHED_TIME_PROMPT)").Trim()
                    if ($hora -notmatch '^\d{2}:\d{2}$') {
                        Write-Host "  $($script:FaxStr.SCHED_TIME_ERR)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }
                    try {
                        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument "-NoLogo -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$moduleRoot\Run-Scrub.ps1`" -NoMenu"
                        $trigger  = New-ScheduledTaskTrigger -Daily -At $hora
                        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun:$false -RunOnlyIfNetworkAvailable:$false
                        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
                        Write-Host "  $($script:FaxStr.SCHED_OK -f $hora)" -ForegroundColor Green
                    } catch {
                        Write-Host "  $($script:FaxStr.SCHED_FAIL) $($_.Exception.Message)" -ForegroundColor Red
                    }
                    Start-Sleep -Seconds 2
                }
            }

            "b" {
                Write-FaxHeader
                $c = Read-Host "  $($script:FaxStr.UNINSTALL_CONFIRM) ($($script:FaxStr.CONFIRM_WORD)/N)"
                if ($c -ne $script:FaxStr.CONFIRM_WORD) {
                    Write-Host "  $($script:FaxStr.CANCELED)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                & powershell.exe -NoLogo -ExecutionPolicy RemoteSigned `
                    -File (Join-Path $moduleRoot "Install-Scrub.ps1") -Uninstall
                Write-Host ""
                Read-Host "  $($script:FaxStr.UNINSTALL_EXIT)" | Out-Null
                return
            }

            "0" { Write-Host ""; return }
        }
    }
}

# ── Ponto de entrada ───────────────────────────────────────────────────────────

if ($Watch.IsPresent) {
    Show-WatchMode -IntervalSecs $WatchInterval
} elseif ($Live.IsPresent -or $ReportOnly.IsPresent -or $NoMenu.IsPresent) {
    if ($ReportOnly) {
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $true
        Open-LatestReport
    } elseif ($Live) {
        $c = Read-Host "`n  $($script:FaxStr.CONFIRM_LIVE -f $script:FaxStr.CONFIRM_WORD)"
        if ($c -ne $script:FaxStr.CONFIRM_WORD) { Write-Host "  $($script:FaxStr.ABORTED)" -ForegroundColor Yellow; return }
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $false
        Open-LatestReport
    } else {
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $true
        Open-LatestReport
    }
    $hist = Get-FaxHistory
    Save-FaxHistory -History $hist -Keys ($script:CATALOG | Where-Object { [bool](Read-FaxConfig).modules.($_.Key) } | ForEach-Object { $_.Key })
} else {
    Show-Menu
}


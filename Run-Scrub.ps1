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

$script:ScrubLangFile = Join-Path $moduleRoot "lang.txt"
$script:ScrubLang = if (Test-Path $script:ScrubLangFile) { (Get-Content $script:ScrubLangFile -Raw).Trim() } else { "pt" }
. (Join-Path $moduleRoot "strings\$script:ScrubLang.ps1")

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

# Carrega presets salvos pelo usuario
$_userPresetsPath = Join-Path $moduleRoot "presets.json"
if (Test-Path $_userPresetsPath) {
    $_up = Get-Content $_userPresetsPath -Raw | ConvertFrom-Json
    foreach ($prop in $_up.PSObject.Properties) {
        $t = @{}
        foreach ($p2 in $prop.Value.PSObject.Properties) { $t[$p2.Name] = [bool]$p2.Value }
        $script:PRESETS[$prop.Name] = $t
    }
}

# ── Dot-source screen modules ─────────────────────────────────────────────────

. (Join-Path $PSScriptRoot "screens\Helpers.ps1")
. (Join-Path $PSScriptRoot "screens\Summary.ps1")
. (Join-Path $PSScriptRoot "screens\Diagnostics.ps1")
. (Join-Path $PSScriptRoot "screens\SmartRoutine.ps1")
. (Join-Path $PSScriptRoot "screens\ModuleSelector.ps1")
. (Join-Path $PSScriptRoot "screens\PresetManager.ps1")
. (Join-Path $PSScriptRoot "screens\ModuleConfig.ps1")
. (Join-Path $PSScriptRoot "screens\StartupManager.ps1")
. (Join-Path $PSScriptRoot "screens\FolderAnalyzer.ps1")
. (Join-Path $PSScriptRoot "screens\History.ps1")
. (Join-Path $PSScriptRoot "screens\WatchMode.ps1")
. (Join-Path $PSScriptRoot "screens\Menu.ps1")

# ── Ponto de entrada ───────────────────────────────────────────────────────────

if ($Watch.IsPresent) {
    Show-WatchMode -IntervalSecs $WatchInterval
} elseif ($Live.IsPresent -or $ReportOnly.IsPresent -or $NoMenu.IsPresent) {
    if ($ReportOnly) {
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $true
        Open-LatestReport
    } elseif ($Live) {
        $c = Read-Host "`n  $($script:ScrubStr.CONFIRM_LIVE -f $script:ScrubStr.CONFIRM_WORD)"
        if ($c -ne $script:ScrubStr.CONFIRM_WORD) { Write-Host "  $($script:ScrubStr.ABORTED)" -ForegroundColor Yellow; return }
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $false
        Open-LatestReport
    } else {
        Invoke-Scrub -ConfigPath $ConfigPath -DryRun $true
        Open-LatestReport
    }
    $hist = Get-ScrubHistory
    Save-ScrubHistory -History $hist -Keys ($script:CATALOG | Where-Object { [bool](Read-ScrubConfig).modules.($_.Key) } | ForEach-Object { $_.Key })
} else {
    Show-Menu
}

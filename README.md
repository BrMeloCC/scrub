# Scrub

Ferramenta de manutenção de disco para Windows, escrita em PowerShell 5.1.  
Roda em **dry-run por padrão** — nada é deletado sem confirmação explícita.

---

## Requisitos

- Windows 10 / 11
- PowerShell 5.1 ou superior (já incluído no Windows)
- Sem dependências externas; sem admin necessário para a maioria das operações

---

## Instalação

```powershell
.\Install-Scrub.ps1
```

O instalador (sem admin):

1. Cria `scrub.cmd` na pasta do projeto
2. Adiciona a pasta ao PATH do usuário (`HKCU\Environment`)
3. Registra o módulo PowerShell via junction (`~\Documents\WindowsPowerShell\Modules\Scrub`)
4. Cria atalho no Menu Iniciar

Após instalar, **abra um novo terminal** e use o comando `scrub`.

Para remover tudo:

```powershell
.\Install-Scrub.ps1 -Uninstall
```

> A pasta do projeto **não é deletada** pelo uninstall — apenas os atalhos e entradas de PATH.

---

## Uso

### Menu interativo (padrão)

```
scrub
.\Run-Scrub.ps1
```

### Via flags (sem menu)

```
.\Run-Scrub.ps1 -NoMenu              # dry-run silencioso, gera relatorio
.\Run-Scrub.ps1 -Live                # deleta de verdade (pede confirmacao)
.\Run-Scrub.ps1 -ReportOnly          # analise completa, abre relatorio HTML
.\Run-Scrub.ps1 -Watch               # monitor em tempo real (Ctrl+C para sair)
.\Run-Scrub.ps1 -Watch -WatchInterval 60   # intervalo em segundos (padrao: 30)
.\Run-Scrub.ps1 -ConfigPath C:\meu.json
```

### Via módulo PowerShell

```powershell
Import-Module .\scrub.psd1

Invoke-Scrub                      # dry-run completo
Invoke-Scrub -DryRun:$false       # live -- deleta de verdade
Get-ScrubReport                   # sempre dry-run, so analise
New-ScrubConfig                   # resetar config para os padroes
```

---

## Menu interativo

```
  Score: 78  ↑   Preset: Customizado   P = alternar

  [1]  Rotina inteligente     roda so o que e necessario, estima o tempo
  [2]  Rotina completa        dry-run -- analisa, nao deleta nada
  [3]  Rotina completa LIVE   deleta de verdade (pede confirmacao)
  [4]  Rotina especifica      escolha quais modulos rodar

  [5]  Diagnosticar           disco, saude, logs e inicializacao (so leitura)
  [6]  Gerenciar startup      ativar/desativar entradas de inicializacao
  [7]  Analisar pasta         uso de espaco interativo
  [8]  Historico              graficos de progresso e score ao longo do tempo

  [9]  Configurar modulos     ativar/desativar, frequencia e tempo estimado
  [A]  Agendar execucao diaria
  [B]  Desinstalar
  [I]  Idioma / Language      alternar entre portugues e ingles
  [0]  Sair
```

### Health Score

Exibido no topo do menu. Score de 0–100 calculado após cada execução com base em:

| Dimensão | Pts |
|---|---|
| Espaço livre no drive principal | 25 |
| Saúde dos discos (SMART) | 20 |
| Erros no Event Log (24h) | 20 |
| Reboot pendente | 10 |
| Windows Updates pendentes | 15 |
| Drivers com problema | 10 |

Seta ↑↓→ indica tendência em relação à medição anterior. Histórico armazenado em `health_history.json` (últimas 90 medições).

### Presets de módulos (`P` = alternar)

| Preset | Comportamento |
|---|---|
| **Customizado** | usa o que está configurado em `config.json` |
| **Diagnostico** | só módulos de leitura (sem deletar) |
| **Limpeza** | todos os módulos de limpeza ativos |

O preset ativo é exibido no topo e afeta as opções 1–4.

### [1] Rotina inteligente

Verifica `run_history.json` e determina quais módulos estão "devidos" com base na frequência configurada. Exibe o tempo estimado. Oferece dry-run ou LIVE.

Se nenhum módulo estiver devido, abre o último relatório e oferece forçar re-execução.

### [4] Rotina específica

Seletor com todos os módulos. Marque os que deseja, depois escolha dry-run ou LIVE.

### [5] Diagnosticar

Roda módulos de leitura em dry-run: disco, health check, drivers, arquivos grandes, downloads, event log, startup, hiberfil, Windows Update, disk optimize, software instalado.

### [6] Gerenciar startup

Lista todas as entradas de inicialização automática com status ON/OFF. Permite desabilitar ou reabilitar individualmente:

- **Registry** → backup em `HKCU:\Software\Scrub\DisabledStartup`, remove da chave `Run`
- **Scheduled Task** → `Disable-ScheduledTask` / `Enable-ScheduledTask`
- **Startup Folder** → renomeia `.lnk` para `.lnk.fax_disabled`

Use `d<N>` para ver detalhes de uma entrada antes de agir.

### [7] Analisar pasta

Browser interativo de uso de espaço em disco. Começa em `~` e mostra subpastas ordenadas por tamanho com barras de proporção. Navegue com número, `U` para subir, `C` para mudar o caminho raiz.

### [8] Histórico & Progresso

Lê os logs `.jsonl` e exibe:
- Sparkline do Health Score ao longo do tempo
- Barras de espaço livre no drive C: por execução
- Barras de bytes liberados por execução

### [9] Configurar módulos

Tela de ativação/desativação de módulos com descrição detalhada.  
Pressione `f` para abrir o editor de **frequência e tempo estimado**.

### [A] Agendar execução diária

Cria uma tarefa agendada (`Scrub_Daily`) que roda dry-run todos os dias no horário escolhido, gerando relatório HTML automaticamente.

### [I] Idioma / Language

Alterna entre português e inglês. A preferência é salva em `lang.txt` e restaurada automaticamente na próxima sessão.

### `-Watch` — Monitor em tempo real

```powershell
.\Run-Scrub.ps1 -Watch
.\Run-Scrub.ps1 -Watch -WatchInterval 60
```

Exibe no terminal: health score, uso de disco com barras, status de reboot e última execução. Atualiza a cada 30s por padrão. `Ctrl+C` para sair.

---

## Configuração

Edite `config.json` para personalizar o comportamento.

```json
{
  "dry_run": true,
  "log_dir": "",
  "report_dir": "",
  "min_age_days": {
    "temp_files": 3,
    "recycle_bin": 30,
    "downloads_report": 60,
    "browser_cache": 7,
    "event_log_scan": 7,
    "software_audit": 30
  },
  "size_threshold_mb": 100,
  "large_file_report_limit": 50,
  "modules": { ... },
  "browser_cache": { "chrome": true, "edge": true, "firefox": true },
  "duplicate_finder": { "scan_paths": [], "min_size_kb": 100 },
  "dev_cleanup": {
    "scan_paths": ["C:\\DEV"],
    "min_age_days": 30,
    "targets": ["node_modules", ".venv", "target", "bin", "obj", ...]
  },
  "excluded_paths": [],
  "alert_disk_usage_pct": 85,
  "schedule": { ... }
}
```

### Módulos

| Módulo | Padrão | Descrição |
|---|---|---|
| `temp_cleaner` | `true` | Limpa `%TEMP%` e `C:\Windows\Temp`. |
| `recycle_bin` | `true` | Remove itens antigos da Lixeira. |
| `disk_report` | `true` | Relatório de uso por drive (sempre ativo). |
| `health_check` | `true` | Saúde dos discos via WMI (sempre ativo). |
| `driver_audit` | `true` | Dispositivos com problema; rescan de drivers (live). |
| `browser_cache` | `true` | Cache do Chrome, Edge e Firefox. |
| `large_file_finder` | `true` | Lista arquivos acima de 100 MB (só relatório). |
| `downloads_audit` | `true` | Arquivos antigos na pasta Downloads (só relatório). |
| `event_log_scan` | `true` | Erros críticos no Event Log dos últimos 7 dias. |
| `startup_audit` | `true` | Programas e tarefas que iniciam com o Windows. |
| `system_log_clean` | `true` | Logs CBS, minidumps, WER, MEMORY.DMP. |
| `node_cache_clean` | `true` | Cache npm, yarn e pnpm. |
| `restore_point` | `true` | Cria ponto de restauração antes de limpar (live). |
| `disk_optimize` | `true` | TRIM em SSDs, desfragmentação em HDDs. |
| `windows_update_check` | `true` | Verifica e dispara atualizações pendentes. |
| `software_audit` | `true` | Software instalado recentemente (só relatório). |
| `duplicate_finder` | `false` | Duplicatas por hash SHA256 (lento; configure `scan_paths`). |
| `hiberfil_cleaner` | `false` | Desativa hibernação e Fast Startup permanentemente. |
| `system_repair` | `false` | SFC + DISM (30-60 min; requer admin). |
| `windows_update_cache` | `false` | Limpa cache do Windows Update (requer admin). |
| `dev_project_clean` | `false` | Pastas de build/deps de projetos dev inativos. |

### Seção `dev_cleanup`

```json
"dev_cleanup": {
  "scan_paths": ["C:\\Users\\user\\source", "C:\\DEV"],
  "min_age_days": 30,
  "targets": [
    "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache",
    "target", "bin", "obj",
    ".next", ".nuxt", ".svelte-kit",
    "dist", "build", "out",
    ".cache", ".parcel-cache",
    ".gradle", ".m2"
  ]
}
```

Com `scan_paths` configurado e `dev_project_clean: true`, o módulo escaneia os caminhos em busca de subprojetos com as pastas pesadas listadas em `targets`. Dry-run: apenas lista. Live: apaga as target folders, nunca o projeto inteiro.

### Seção `schedule`

Define quando cada módulo é "devido" na rotina inteligente e o tempo estimado.

```json
"schedule": {
  "temp_cleaner":         { "freq_days": 1,  "est_secs": 10  },
  "recycle_bin":          { "freq_days": 1,  "est_secs": 5   },
  "browser_cache":        { "freq_days": 7,  "est_secs": 15  },
  "large_file_finder":    { "freq_days": 7,  "est_secs": 30  },
  "dev_project_clean":    { "freq_days": 7,  "est_secs": 60  },
  "software_audit":       { "freq_days": 7,  "est_secs": 5   },
  "disk_optimize":        { "freq_days": 7,  "est_secs": 30  },
  "windows_update_check": { "freq_days": 1,  "est_secs": 20  },
  "duplicate_finder":     { "freq_days": 30, "est_secs": 300 },
  "system_repair":        { "freq_days": 30, "est_secs": 1800}
}
```

---

## Módulos em detalhe

### Temp Cleaner
Remove arquivos de `%TEMP%` e `C:\Windows\Temp` com mais de `min_age_days.temp_files` dias.

### Recycle Bin
Remove da Lixeira itens com mais de `min_age_days.recycle_bin` dias.

### Disk Report
Exibe espaço livre/usado por drive. Alerta se o uso ultrapassar `alert_disk_usage_pct`.

### Health Check
Consulta o status S.M.A.R.T. dos discos via WMI. Alerta em caso de status diferente de `OK`.

### Driver Audit
Verifica dispositivos com erro ou driver ausente. Em modo live, dispara rescan do PnP.

### Browser Cache
Limpa cache do Chrome, Edge e/ou Firefox com mais de `min_age_days.browser_cache` dias. Logins preservados.  
**Requer que os browsers estejam fechados durante a execução.**

### Large File Finder
Lista os maiores arquivos do sistema (acima de `size_threshold_mb` MB). Apenas relatório.

### Downloads Audit
Lista arquivos em Downloads com mais de `min_age_days.downloads_report` dias sem acesso. Apenas relatório.

### Duplicate Finder
Encontra arquivos idênticos por hash SHA256. Requer `scan_paths` configurados. Operação lenta — padrão desativado.

### Event Log Scan
Lê os logs `System` e `Application` dos últimos `min_age_days.event_log_scan` dias em busca de eventos Critical e Error. Agrupa por fonte.

### Startup Audit
Lista todas as entradas de inicialização: chaves `Run`/`RunOnce` do registro, pastas Startup e tarefas agendadas com triggers de boot/logon. Apenas relatório — para gerenciar interativamente use a opção [6].

### System Log Clean
Remove logs e dumps seguros de apagar:
- Logs CBS (`C:\Windows\Logs\CBS\*.log`, exceto o em uso)
- Minidumps (`C:\Windows\Minidump\*.dmp`) — requer admin
- Crash dumps de usuário (`%LOCALAPPDATA%\CrashDumps\*.dmp`)
- Relatórios WER (`%LOCALAPPDATA%\Microsoft\Windows\WER\ReportArchive\`)
- Full memory dump (`C:\Windows\MEMORY.DMP`) — requer admin

### Node Cache Clean
Limpa caches de npm, yarn v1, yarn berry e pnpm usando caminhos fixos.

### Restore Point
Cria um ponto de restauração do sistema antes de limpar (modo live). Limite do Windows: um ponto por dia.

### Hiberfil Cleaner
Desativa hibernação e Fast Startup permanentemente, liberando 4–16 GB (`hiberfil.sys`).  
**Atenção:** o boot fica ~5s mais lento. Irreversível via ferramenta — padrão desativado.

### Disk Optimize
TRIM em SSDs (preserva vida útil), desfragmentação em HDDs. Dry-run apenas relata o tipo de mídia.

### Windows Update Check
Consulta atualizações pendentes. Em modo live, inicia download em background via `UsoClient`.

### Windows Update Cache *(requer admin)*
Para o serviço WU, apaga o cache em `C:\Windows\SoftwareDistribution\Download` e reinicia o serviço.

### System Repair *(requer admin, lento)*
Executa SFC + DISM. Pode levar 30–60 minutos. Padrão desativado.

### Software Audit
Lista software instalado nos últimos `min_age_days.software_audit` dias (padrão: 30) via registro do Windows. Apenas relatório — útil para identificar bloatware ou rastrear o que um instalador adicionou.

### Dev Project Cleanup
Varre `dev_cleanup.scan_paths` procurando projetos com pastas de build/deps pesadas (`node_modules`, `.venv`, `target/`, etc.). Critério de "devido": projeto não foi tocado há mais de `dev_cleanup.min_age_days` dias. Live: apaga apenas as target folders, nunca o projeto inteiro. Padrão desativado — configure `scan_paths` antes de ativar.

### Pending Reboot *(sempre ativo)*
Verifica chaves de registro que indicam reboot pendente. Exibido no topo de todo relatório.

---

## Logs

Cada execução grava um arquivo `.jsonl` em `logs\` com uma linha JSON por módulo:

```jsonl
{"timestamp":"2026-05-25T10:30:00","module":"TempCleaner","data":{...}}
{"timestamp":"2026-05-25T10:30:01","module":"RecycleBin","data":{...}}
```

O histórico [8] lê esses arquivos para construir os gráficos de progresso.

---

## Histórico de execuções

`run_history.json` registra o timestamp da última execução de cada módulo. Usado pela rotina inteligente para determinar o que está "devido".

`health_history.json` registra snapshots do Health Score (máximo 90). Usado pelo header do menu e pela tela de Histórico.

---

## Relatório HTML

Gerado automaticamente em `reports\` ao final de cada execução. Tema escuro, tabelas expansíveis, destaque para alertas críticos.

Para **não** gerar o relatório:

```powershell
Invoke-Scrub -NoReport
```

---

## Estrutura do projeto

```
scrub\
├── scrub.psm1               # Módulo principal, orquestrador
├── scrub.psd1               # Manifesto do módulo
├── scrub.cmd                # Launcher (comando 'scrub' no terminal)
├── config.json              # Configuração padrão
├── Run-Scrub.ps1            # Ponto de entrada / menu interativo
├── Install-Scrub.ps1        # Instalador/desinstalador de usuário
├── lang.txt                 # Idioma salvo (auto-criado)
├── run_history.json         # Histórico de execuções (auto-criado)
├── health_history.json      # Histórico do Health Score (auto-criado)
├── strings\
│   ├── pt.ps1               # Strings em português
│   └── en.ps1               # Strings em inglês
└── modules\
    ├── TempCleaner.ps1
    ├── RecycleBin.ps1
    ├── DiskReport.ps1
    ├── BrowserCache.ps1
    ├── LargeFileFinder.ps1
    ├── DuplicateFinder.ps1
    ├── EventLogScan.ps1
    ├── HibernationClean.ps1
    ├── StartupAudit.ps1
    ├── SystemLogClean.ps1
    ├── NodeCacheClean.ps1
    ├── DriverAudit.ps1
    ├── SystemRepair.ps1
    ├── DiskOptimize.ps1
    ├── WindowsUpdateCheck.ps1
    ├── RestorePoint.ps1
    ├── PendingReboot.ps1
    ├── HtmlReport.ps1
    ├── SoftwareAudit.ps1
    ├── HealthScore.ps1
    ├── DevProjectClean.ps1
    └── FolderSizeAnalyzer.ps1
```

---

## Segurança e limitações

- Dry-run é o padrão em todos os módulos
- Modo live exige confirmação textual (`sim` / `yes`) antes de deletar
- Todos os caminhos de limpeza são whitelists fixas no código — config não consegue apontar para pastas arbitrárias
- `dev_project_clean` deleta apenas pastas cujos nomes estão na lista `targets` — nunca deleta o projeto inteiro
- Startup manager mantém backup de entradas desabilitadas em `HKCU:\Software\Scrub\DisabledStartup`
- Nunca toca: Documents, Desktop, Pictures, Music, Videos, OneDrive
- Operações que requerem admin são detectadas e reportadas — nunca falham silenciosamente
- Instalação não modifica o PATH do sistema — apenas o PATH do usuário (`HKCU`)
- Nenhuma telemetria, nenhuma conexão de rede

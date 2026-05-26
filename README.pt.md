# Scrub

[![Português](https://img.shields.io/badge/lang-Portugu%C3%AAs-green)](README.pt.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.md)

> Ferramenta de manutenção de disco para Windows — segura por padrão, poderosa quando necessário.

![Plataforma](https://img.shields.io/badge/plataforma-Windows%2010%2F11-blue?logo=windows)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Versão](https://img.shields.io/badge/vers%C3%A3o-1.0.0-green)
![Licença](https://img.shields.io/badge/licen%C3%A7a-MIT-lightgrey)

Scrub é uma ferramenta de manutenção para Windows com menu TUI interativo.  
Roda em **dry-run por padrão** — nada é deletado sem confirmação explícita.

---

## Funcionalidades

- **Rotina inteligente** — roda apenas o que está "devido" com base em frequências configuráveis
- **Health Score** — pontuação 0–100 com base em espaço livre, SMART, event log, drivers e updates
- **22 módulos** — temp cleaner, cache de browser, arquivos grandes, duplicatas, startup manager, reparo do sistema e mais
- **Analisador de pastas interativo** — explorador visual de uso de disco
- **Histórico & gráficos** — acompanhamento de progresso ao longo das execuções
- **Bilíngue** — interface em português e inglês
- **Sem admin** na maioria das operações; sem dependências externas; sem telemetria

---

## Requisitos

- Windows 10 / 11
- PowerShell 5.1 ou superior (já incluído no Windows)

---

## Instalação

Baixe a última [release](https://github.com/BrMeloCC/scrub/releases), extraia em qualquer pasta e execute:

```powershell
.\Install-Scrub.ps1
```

O instalador (sem admin):
1. Cria `scrub.cmd` na pasta do projeto
2. Adiciona a pasta ao PATH do usuário (`HKCU\Environment`)
3. Registra o módulo PowerShell via junction
4. Cria atalho no Menu Iniciar

Após instalar, **abra um novo terminal** e use o comando `scrub`.

**Para desinstalar:**

```powershell
.\Install-Scrub.ps1 -Uninstall
```

> A pasta do projeto **não é deletada** — apenas atalhos e entradas de PATH são removidos.

---

## Uso

### Menu interativo (padrão)

```
scrub
```

### Via flags (sem menu)

```powershell
.\Run-Scrub.ps1 -NoMenu             # dry-run silencioso, gera relatório
.\Run-Scrub.ps1 -Live               # modo live (pede confirmação antes de deletar)
.\Run-Scrub.ps1 -ReportOnly         # análise completa, abre relatório HTML
.\Run-Scrub.ps1 -Watch              # monitor em tempo real (Ctrl+C para sair)
.\Run-Scrub.ps1 -Watch -WatchInterval 60
.\Run-Scrub.ps1 -ConfigPath C:\meu.json
```

### Via módulo PowerShell

```powershell
Import-Module .\scrub.psd1

Invoke-Scrub                   # dry-run
Invoke-Scrub -DryRun:$false    # modo live
Get-ScrubReport                # somente análise
New-ScrubConfig                # resetar config para os padrões
```

---

## Menu

```
  Score: 82  ↑   Preset: Customizado   P = alternar

  [1]  Rotina inteligente     roda só o que é necessário, estima o tempo
  [2]  Rotina completa        dry-run -- analisa, não deleta nada
  [3]  Rotina completa LIVE   deleta de verdade (pede confirmação)
  [4]  Rotina específica      escolha quais módulos rodar

  [5]  Diagnosticar           disco, saúde, logs e inicialização (só leitura)
  [6]  Gerenciar startup      ativar/desativar entradas de inicialização
  [7]  Analisar pasta         explorador de uso de disco interativo
  [8]  Histórico              gráficos de progresso e score ao longo do tempo

  [9]  Configurar módulos     ativar/desativar, frequência e tempo estimado
  [A]  Agendar execução diária
  [B]  Desinstalar
  [I]  Idioma / Language      alternar entre português e inglês
  [0]  Sair
```

### Health Score

Exibido no topo do menu. Calculado após cada execução:

| Dimensão | Pontos |
|---|---|
| Espaço livre no drive principal | 25 |
| Saúde dos discos (SMART) | 20 |
| Erros no Event Log (últimas 24h) | 20 |
| Reboot pendente | 10 |
| Windows Updates pendentes | 15 |
| Drivers com problema | 10 |

Seta (↑↓→) indica tendência em relação à medição anterior. Histórico em `health_history.json` (últimas 90 medições).

---

## Módulos

| Módulo | Padrão | Descrição |
|---|---|---|
| `temp_cleaner` | ✅ | Limpa `%TEMP%` e `C:\Windows\Temp` |
| `recycle_bin` | ✅ | Remove itens antigos da Lixeira |
| `disk_report` | ✅ | Relatório de uso por drive (sempre ativo) |
| `health_check` | ✅ | Saúde dos discos via SMART/WMI (sempre ativo) |
| `driver_audit` | ✅ | Dispositivos com erro; rescan PnP no modo live |
| `browser_cache` | ✅ | Cache do Chrome, Edge e Firefox |
| `large_file_finder` | ✅ | Lista arquivos acima do limite (só relatório) |
| `downloads_audit` | ✅ | Arquivos antigos em Downloads (só relatório) |
| `event_log_scan` | ✅ | Eventos críticos/erro nos logs do Windows |
| `startup_audit` | ✅ | Programas e tarefas que iniciam com o Windows |
| `system_log_clean` | ✅ | Logs CBS, minidumps, relatórios WER, MEMORY.DMP |
| `node_cache_clean` | ✅ | Caches do npm, yarn e pnpm |
| `restore_point` | ✅ | Cria ponto de restauração antes de limpar (live) |
| `disk_optimize` | ✅ | TRIM em SSDs, desfragmentação em HDDs |
| `windows_update_check` | ✅ | Verifica e dispara Windows Updates pendentes |
| `software_audit` | ✅ | Software instalado recentemente (só relatório) |
| `duplicate_finder` | ❌ | Duplicatas por hash SHA256 (lento; configure `scan_paths`) |
| `hiberfil_cleaner` | ❌ | Desativa hibernação e Fast Startup (permanente) |
| `system_repair` | ❌ | SFC + DISM (30–60 min; requer admin) |
| `windows_update_cache` | ❌ | Limpa cache do Windows Update (requer admin) |
| `dev_project_clean` | ❌ | Pastas de build/deps de projetos dev inativos |

---

## Configuração

Edite `config.json` para personalizar. Principais opções:

```json
{
  "dry_run": true,
  "size_threshold_mb": 100,
  "alert_disk_usage_pct": 85,
  "min_age_days": {
    "temp_files": 3,
    "recycle_bin": 30,
    "browser_cache": 7
  },
  "browser_cache": { "chrome": true, "edge": true, "firefox": true },
  "dev_cleanup": {
    "scan_paths": ["C:\\DEV"],
    "min_age_days": 30,
    "targets": ["node_modules", ".venv", "target", "dist", "build", ...]
  },
  "schedule": {
    "temp_cleaner": { "freq_days": 1, "est_secs": 10 },
    "browser_cache": { "freq_days": 7, "est_secs": 15 }
  }
}
```

---

## Segurança

- Dry-run é o padrão em todos os módulos
- Modo live exige confirmação textual (`sim` / `yes`) antes de deletar
- Todos os caminhos de limpeza são whitelists fixas no código
- `dev_project_clean` deleta apenas pastas que estão na lista `targets`, nunca o projeto inteiro
- Nunca toca: Documents, Desktop, Pictures, Music, Videos, OneDrive
- Operações que requerem admin são detectadas e reportadas — nunca falham silenciosamente
- Instalação modifica apenas o PATH do **usuário** (`HKCU`) — nunca o PATH do sistema
- Sem telemetria, sem conexões de rede

---

## Estrutura do Projeto

```
scrub/
├── Run-Scrub.ps1          # Ponto de entrada / menu interativo
├── Install-Scrub.ps1      # Instalador/desinstalador de usuário
├── scrub.psm1             # Módulo principal / orquestrador
├── scrub.psd1             # Manifesto do módulo
├── scrub.cmd              # Launcher do terminal
├── config.json            # Configuração padrão
├── strings/
│   ├── en.ps1             # Strings em inglês
│   └── pt.ps1             # Strings em português
└── modules/               # 22 módulos PS1 independentes
```

---

## Licença

MIT — livre para usar, modificar e distribuir.

<div align="center">

[![Português](https://img.shields.io/badge/lang-Portugu%C3%AAs-green)](README.pt.md)
[![English](https://img.shields.io/badge/lang-English-blue)](README.md)

# Scrub

**Manutenção de disco para Windows — seguro por padrão, poderoso quando necessário.**

[![Plataforma](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)](https://github.com/BrMeloCC/scrub)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-012456?logo=powershell&logoColor=white)](https://github.com/BrMeloCC/scrub)
[![Versão](https://img.shields.io/github/v/release/BrMeloCC/scrub?color=brightgreen&label=release)](https://github.com/BrMeloCC/scrub/releases)
[![Licença](https://img.shields.io/badge/licen%C3%A7a-MIT-lightgrey)](LICENSE)

</div>

---

Scrub é uma ferramenta de manutenção para Windows com menu TUI interativo.  
Roda em **dry-run por padrão** — nada é deletado sem confirmação explícita.

```
scrub              # dry run — analisa, não deleta nada
scrub -Live        # modo live — pede confirmação antes de deletar
scrub -ReportOnly  # só análise, abre relatório HTML
```

---

## Início Rápido

**1. Baixe** a última [release](https://github.com/BrMeloCC/scrub/releases) e extraia em qualquer pasta.

**2. Instale** clicando duas vezes em `setup.cmd` — sem necessidade de admin.

Abra um **novo terminal** após instalar e use:

```
scrub              # dry run — analisa, não deleta nada
scrub -Live        # modo live — pede confirmação antes de deletar
scrub -ReportOnly  # só análise, abre relatório HTML
```

Para desinstalar: `setup.cmd -Uninstall`

> **Sem instalar:** clique duas vezes em `scrub.cmd` direto, ou:
> ```powershell
> .\Run-Scrub.ps1 -NoMenu
> .\Run-Scrub.ps1 -Live
> ```

---

## Funcionalidades

| | |
|---|---|
| Rotina inteligente | Roda apenas o que está devido, com base em frequências configuráveis |
| Health Score | Pontuação 0–100: espaço livre, SMART, event log, drivers, updates |
| 22 módulos | Temp, cache de browser, duplicatas, startup manager, reparo do sistema e mais |
| Analisador de pastas | Explorador visual interativo de uso de disco |
| Histórico & gráficos | Acompanhamento de progresso ao longo das execuções |
| Bilíngue | Interface em português e inglês |
| Seguro | Sem admin na maioria das ops · Sem telemetria · Sem rede |

---

## Menu

```
  Score: 82  ↑   Preset: Customizado   P = alternar

  [1]  Rotina inteligente     roda só o que é necessário, estima o tempo
  [2]  Rotina completa        dry-run — analisa, não deleta nada
  [3]  Rotina completa LIVE   deleta de verdade (pede confirmação)
  [4]  Rotina específica      escolha quais módulos rodar

  [5]  Diagnosticar           disco, saúde, logs e inicialização (só leitura)
  [6]  Gerenciar startup      ativar/desativar entradas de inicialização
  [7]  Analisar pasta         explorador de uso de disco interativo
  [8]  Histórico              gráficos de progresso e score ao longo do tempo

  [9]  Configurar módulos     ativar/desativar com última execução e tempo estimado
  [A]  Agendar execução diária
  [B]  Desinstalar
  [I]  Idioma / Language      alternar entre português e inglês
  [0]  Sair
```

### Health Score

Exibido no topo de cada execução. Seta (↑↓→) indica tendência em relação à medição anterior.

| Dimensão | Pontos |
|---|:---:|
| Espaço livre no drive principal | 25 |
| Saúde dos discos (SMART) | 20 |
| Erros no Event Log (últimas 24h) | 20 |
| Windows Updates pendentes | 15 |
| Reboot pendente | 10 |
| Drivers com problema | 10 |

### Seleção de Módulos

Os menus **Rotina específica [4]** e **Configurar módulos [9]** compartilham um seletor de módulos em comum:

- Digite um número para marcar/desmarcar um módulo
- Digite vários números separados por espaço para marcar vários de uma vez — ex: `2 3 5`
- `a` marca todos os módulos, `n` desmarca todos
- O tempo estimado total é atualizado em tempo real conforme você seleciona

**Configurar módulos [9]** também exibe a data da última execução de cada módulo e marca alterações não salvas com `*`. Pressione `r` para salvar e executar na hora sem voltar ao menu principal.

---

## Módulos

<details>
<summary><strong>Ativos por padrão</strong></summary>

| Módulo | Descrição |
|---|---|
| `temp_cleaner` | Limpa `%TEMP%` e `C:\Windows\Temp` |
| `recycle_bin` | Remove itens antigos da Lixeira |
| `disk_report` | Relatório de uso por drive (sempre ativo) |
| `health_check` | Saúde dos discos via SMART/WMI (sempre ativo) |
| `driver_audit` | Dispositivos com erro; rescan PnP no modo live |
| `browser_cache` | Cache do Chrome, Edge e Firefox |
| `large_file_finder` | Lista arquivos acima do limite (só relatório) |
| `downloads_audit` | Arquivos antigos em Downloads (só relatório) |
| `event_log_scan` | Eventos críticos/erro nos logs do Windows |
| `startup_audit` | Programas e tarefas que iniciam com o Windows |
| `system_log_clean` | Logs CBS, minidumps, relatórios WER, MEMORY.DMP |
| `node_cache_clean` | Caches do npm, yarn e pnpm |
| `restore_point` | Cria ponto de restauração antes de limpar (live) |
| `disk_optimize` | TRIM em SSDs, desfragmentação em HDDs |
| `windows_update_check` | Verifica e dispara Windows Updates pendentes |
| `software_audit` | Software instalado recentemente (só relatório) |

</details>

<details>
<summary><strong>Desativados por padrão</strong></summary>

| Módulo | Descrição |
|---|---|
| `duplicate_finder` | Duplicatas por SHA256 — lento, configure `scan_paths` primeiro |
| `hiberfil_cleaner` | Desativa hibernação e Fast Startup permanentemente |
| `system_repair` | SFC + DISM — 30–60 min, requer admin |
| `windows_update_cache` | Limpa cache do Windows Update — requer admin |
| `dev_project_clean` | Remove build/deps de projetos dev inativos |

</details>

---

## Configuração

Edite `config.json` para personalizar:

<details>
<summary><strong>Ver referência completa</strong></summary>

```json
{
  "dry_run": true,
  "size_threshold_mb": 100,
  "alert_disk_usage_pct": 85,
  "min_age_days": {
    "temp_files": 3,
    "recycle_bin": 30,
    "browser_cache": 7,
    "downloads_report": 60,
    "event_log_scan": 7,
    "software_audit": 30
  },
  "browser_cache": { "chrome": true, "edge": true, "firefox": true },
  "duplicate_finder": { "scan_paths": [], "min_size_kb": 100 },
  "dev_cleanup": {
    "scan_paths": ["C:\\DEV"],
    "min_age_days": 30,
    "targets": ["node_modules", ".venv", "target", "dist", "build", ".next", ".gradle"]
  },
  "excluded_paths": [],
  "schedule": {
    "temp_cleaner":         { "freq_days": 1,  "est_secs": 10   },
    "recycle_bin":          { "freq_days": 1,  "est_secs": 5    },
    "browser_cache":        { "freq_days": 7,  "est_secs": 15   },
    "large_file_finder":    { "freq_days": 7,  "est_secs": 30   },
    "duplicate_finder":     { "freq_days": 30, "est_secs": 300  },
    "system_repair":        { "freq_days": 30, "est_secs": 1800 }
  }
}
```

</details>

---

## Segurança

- Dry-run é o **padrão** em todos os módulos
- Modo live exige digitar `sim` / `yes` para confirmar antes de qualquer deleção
- Todos os caminhos de limpeza são **whitelists fixas** no código
- `dev_project_clean` deleta apenas pastas da lista `targets`, nunca o projeto inteiro
- Nunca toca: Documents, Desktop, Pictures, Music, Videos, OneDrive
- Modifica apenas o PATH do **usuário** (`HKCU`) — nunca o PATH do sistema
- Sem telemetria · Sem conexões de rede

---

## Estrutura do Projeto

```
scrub/
├── Run-Scrub.ps1          # Ponto de entrada / menu interativo
├── Install-Scrub.ps1      # Instalador/desinstalador de usuário
├── setup.cmd              # Instalador com um clique (clique duplo para instalar)
├── scrub.psm1             # Módulo principal / orquestrador
├── scrub.psd1             # Manifesto do módulo
├── scrub.cmd              # Launcher do terminal (funciona em qualquer pasta)
├── config.json            # Configuração padrão
├── strings/
│   ├── en.ps1             # Strings em inglês
│   └── pt.ps1             # Strings em português
└── modules/               # 22 módulos PS1 independentes
```

---

## Licença

MIT — livre para usar, modificar e distribuir.

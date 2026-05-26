function Get-StartupAudit {
    param(
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module = "StartupAudit"
        Items  = [System.Collections.Generic.List[object]]::new()
        Errors = [System.Collections.Generic.List[string]]::new()
    }

    # Registry Run keys (HKCU = current user, HKLM = all users / system)
    $regKeys = @(
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";                 Scope = "User" }
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce";             Scope = "User (once)" }
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run";                 Scope = "System" }
        @{ Path = "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce";             Scope = "System (once)" }
        @{ Path = "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run";     Scope = "System (32-bit)" }
    )

    $psPropPattern = "^PS(Path|ParentPath|ChildName|Drive|Provider)$"

    foreach ($key in $regKeys) {
        try {
            $props = Get-ItemProperty -Path $key.Path -ErrorAction SilentlyContinue
            if (-not $props) { continue }
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match $psPropPattern) { continue }
                $result.Items.Add([PSCustomObject]@{
                    Name     = $p.Name
                    Type     = "Registry"
                    Scope    = $key.Scope
                    Command  = "$($p.Value)"
                    Enabled  = $true
                    Location = $key.Path
                })
            }
        } catch {
            $result.Errors.Add("REG_FAILED: $($key.Path) - $($_.Exception.Message)")
        }
    }

    # Startup folders (User and All Users)
    $startupFolders = @(
        @{ Path = [Environment]::GetFolderPath("Startup");       Scope = "User" }
        @{ Path = [Environment]::GetFolderPath("CommonStartup"); Scope = "All Users" }
    )

    foreach ($folder in $startupFolders) {
        if (-not $folder.Path -or -not (Test-Path $folder.Path)) { continue }
        try {
            Get-ChildItem -Path $folder.Path -File -ErrorAction SilentlyContinue | ForEach-Object {
                $result.Items.Add([PSCustomObject]@{
                    Name     = $_.BaseName
                    Type     = "Startup Folder"
                    Scope    = $folder.Scope
                    Command  = $_.FullName
                    Enabled  = $true
                    Location = $folder.Path
                })
            }
        } catch {
            $result.Errors.Add("FOLDER_FAILED: $($folder.Path) - $($_.Exception.Message)")
        }
    }

    # Scheduled tasks with Boot or Logon triggers
    try {
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
        foreach ($task in $tasks) {
            $isBootLogon = $false
            foreach ($trigger in $task.Triggers) {
                try {
                    if ($trigger.CimClass -and $trigger.CimClass.CimClassName -match "Boot|Logon") {
                        $isBootLogon = $true
                        break
                    }
                } catch {}
            }
            if (-not $isBootLogon) { continue }

            $action = $task.Actions | Select-Object -First 1
            $cmd    = if ($action) { "$($action.Execute) $($action.Arguments)".Trim() } else { "" }
            $result.Items.Add([PSCustomObject]@{
                Name     = $task.TaskName
                Type     = "Scheduled Task"
                Scope    = "System"
                Command  = $cmd
                Enabled  = ($task.State -eq "Ready")
                Location = $task.TaskPath
            })
        }
    } catch {
        $result.Errors.Add("TASKS_FAILED: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

# Backup key for disabled registry entries
$STARTUP_DISABLED_KEY = "HKCU:\Software\Scrub\DisabledStartup"

function Disable-StartupEntry {
    param([PSCustomObject] $Entry)

    switch ($Entry.Type) {
        "Registry" {
            # Back up value then remove from original Run key
            try {
                if (-not (Test-Path $STARTUP_DISABLED_KEY)) {
                    New-Item -Path $STARTUP_DISABLED_KEY -Force | Out-Null
                }
                $backupKey = Join-Path $STARTUP_DISABLED_KEY ($Entry.Location -replace '[\\:]', '_')
                if (-not (Test-Path $backupKey)) {
                    New-Item -Path $backupKey -Force | Out-Null
                }
                Set-ItemProperty -Path $backupKey -Name $Entry.Name -Value $Entry.Command -Force
                Remove-ItemProperty -Path $Entry.Location -Name $Entry.Name -Force -ErrorAction Stop
                return [PSCustomObject]@{ Success = $true; Message = "Removido de $($Entry.Location)" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        "Scheduled Task" {
            try {
                Disable-ScheduledTask -TaskName $Entry.Name -TaskPath $Entry.Location -ErrorAction Stop | Out-Null
                return [PSCustomObject]@{ Success = $true; Message = "Tarefa desabilitada" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        "Startup Folder" {
            try {
                $dest = $Entry.Command + ".fax_disabled"
                Rename-Item -Path $Entry.Command -NewName ([System.IO.Path]::GetFileName($dest)) -Force -ErrorAction Stop
                return [PSCustomObject]@{ Success = $true; Message = "Renomeado para .fax_disabled" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        default {
            return [PSCustomObject]@{ Success = $false; Message = "Tipo nao suportado: $($Entry.Type)" }
        }
    }
}

function Enable-StartupEntry {
    param([PSCustomObject] $Entry)

    switch ($Entry.Type) {
        "Registry" {
            try {
                $backupKey = Join-Path $STARTUP_DISABLED_KEY ($Entry.Location -replace '[\\:]', '_')
                $val = (Get-ItemProperty -Path $backupKey -Name $Entry.Name -ErrorAction Stop).($Entry.Name)
                Set-ItemProperty -Path $Entry.Location -Name $Entry.Name -Value $val -Force
                Remove-ItemProperty -Path $backupKey -Name $Entry.Name -Force -ErrorAction SilentlyContinue
                return [PSCustomObject]@{ Success = $true; Message = "Restaurado em $($Entry.Location)" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        "Scheduled Task" {
            try {
                Enable-ScheduledTask -TaskName $Entry.Name -TaskPath $Entry.Location -ErrorAction Stop | Out-Null
                return [PSCustomObject]@{ Success = $true; Message = "Tarefa reabilitada" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        "Startup Folder" {
            try {
                $disabledPath = $Entry.Command + ".fax_disabled"
                if (Test-Path $disabledPath) {
                    Rename-Item -Path $disabledPath -NewName ([System.IO.Path]::GetFileName($Entry.Command)) -Force -ErrorAction Stop
                    return [PSCustomObject]@{ Success = $true; Message = "Restaurado" }
                }
                return [PSCustomObject]@{ Success = $false; Message = "Arquivo .fax_disabled nao encontrado" }
            } catch {
                return [PSCustomObject]@{ Success = $false; Message = $_.Exception.Message }
            }
        }
        default {
            return [PSCustomObject]@{ Success = $false; Message = "Tipo nao suportado: $($Entry.Type)" }
        }
    }
}

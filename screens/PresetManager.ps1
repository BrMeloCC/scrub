function Get-UserPresets {
    $p = Join-Path $moduleRoot "presets.json"
    if (Test-Path $p) { return (Get-Content $p -Raw | ConvertFrom-Json) }
    return [PSCustomObject]@{}
}

function Save-UserPresets {
    param([PSCustomObject] $Presets)
    $Presets | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $moduleRoot "presets.json") -Encoding UTF8
}

function Show-PresetManager {
    param([hashtable] $CurrentToggles)

    $builtIn = @("customizado", "diagnostico", "limpeza")

    while ($true) {
        $userPresets = Get-UserPresets
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.PRESET_TITLE)" -ForegroundColor White
        Write-Host "  $($script:ScrubStr.PRESET_ACTIVE) " -NoNewline
        Write-Host (Get-PresetLabel) -ForegroundColor Cyan
        Write-Host ""

        $i = 1
        $indexMap = @{}

        foreach ($key in $builtIn) {
            Write-Host ("  " + "$i".PadLeft(2) + "  ") -NoNewline
            Write-Host $key -ForegroundColor DarkGray -NoNewline
            Write-Host "  $($script:ScrubStr.PRESET_BUILTIN)" -ForegroundColor DarkGray
            $indexMap[$i] = @{ Key = $key; IsBuiltIn = $true }
            $i++
        }

        foreach ($prop in $userPresets.PSObject.Properties) {
            $active = ($script:ActivePreset -eq $prop.Name)
            $col    = if ($active) { "Cyan" } else { "White" }
            Write-Host ("  " + "$i".PadLeft(2) + "  ") -NoNewline
            Write-Host $prop.Name -ForegroundColor $col
            $indexMap[$i] = @{ Key = $prop.Name; IsBuiltIn = $false }
            $i++
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.NUM) = $($script:ScrubStr.PRESET_LOADED)   " -NoNewline
        Write-Host "s" -ForegroundColor Cyan -NoNewline
        Write-Host " = $($script:ScrubStr.PRESET_SAVE_NEW)   " -NoNewline
        Write-Host "del" -ForegroundColor Yellow -NoNewline
        Write-Host " <N> = $($script:ScrubStr.PRESET_DELETED)   " -NoNewline
        Write-Host "c" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()

        if ($raw -eq "c") { return }

        if ($raw -eq "s") {
            $anyOn = $CurrentToggles.Values | Where-Object { $_ }
            if (-not $anyOn) {
                Write-Host "  $($script:ScrubStr.PRESET_EMPTY)" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            $name = (Read-Host "  $($script:ScrubStr.PRESET_NAME_P)").Trim().ToLower()
            if (-not $name) { continue }
            if ($builtIn -contains $name -or $userPresets.PSObject.Properties[$name]) {
                Write-Host "  $($script:ScrubStr.PRESET_EXISTS)" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
                continue
            }
            $entry = [PSCustomObject]@{}
            foreach ($key in $CurrentToggles.Keys) {
                $entry | Add-Member -MemberType NoteProperty -Name $key -Value $CurrentToggles[$key] -Force
            }
            $userPresets | Add-Member -MemberType NoteProperty -Name $name -Value $entry -Force
            Save-UserPresets -Presets $userPresets
            $script:PRESETS[$name] = $CurrentToggles.Clone()
            $script:ActivePreset   = $name
            Write-Host "  $($script:ScrubStr.PRESET_SAVED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            continue
        }

        if ($raw -match '^del\s+(\d+)$') {
            $n = [int]$Matches[1]
            if ($indexMap[$n]) {
                $entry = $indexMap[$n]
                if ($entry.IsBuiltIn) {
                    Write-Host "  $($script:ScrubStr.PRESET_CANT_DEL)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                } else {
                    $key = $entry.Key
                    $userPresets.PSObject.Properties.Remove($key)
                    Save-UserPresets -Presets $userPresets
                    $script:PRESETS.Remove($key)
                    if ($script:ActivePreset -eq $key) { $script:ActivePreset = "customizado" }
                    Write-Host "  $($script:ScrubStr.PRESET_DELETED)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                }
            }
            continue
        }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $indexMap[$n]) {
            $entry = $indexMap[$n]
            if ($entry.IsBuiltIn) {
                $script:ActivePreset = $entry.Key
            } else {
                $userPresets = Get-UserPresets
                $saved = $userPresets.($entry.Key)
                if ($saved) {
                    $t = @{}
                    foreach ($prop in $saved.PSObject.Properties) { $t[$prop.Name] = [bool]$prop.Value }
                    $script:PRESETS[$entry.Key] = $t
                    $script:ActivePreset        = $entry.Key
                }
            }
            Write-Host "  $($script:ScrubStr.PRESET_LOADED)" -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
    }
}

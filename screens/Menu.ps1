function Show-Menu {
    while ($true) {
        Write-ScrubHeader
        $cached      = Get-CachedHealthScore
        $presetColor = switch ($script:ActivePreset) { "diagnostico" { "Cyan" } "limpeza" { "Yellow" } default { "White" } }

        if ($cached) {
            $sCol = Format-ScoreColor -Score $cached.Score
            Write-Host "  $($script:ScrubStr.MENU_SCORE) " -NoNewline
            Write-Host "$($cached.Score)" -ForegroundColor $sCol -NoNewline
            if ($cached.Trend) { Write-Host "  $($cached.Trend)" -ForegroundColor DarkGray -NoNewline }
            Write-Host "     $($script:ScrubStr.MENU_PRESET) " -NoNewline
        } else {
            Write-Host "  $($script:ScrubStr.MENU_PRESET) " -NoNewline
        }
        Write-Host (Get-PresetLabel) -ForegroundColor $presetColor -NoNewline
        Write-Host "   " -NoNewline
        Write-Host "P" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:ScrubStr.MENU_P_TOGGLE)" -ForegroundColor DarkGray
        Write-Host ""

        Write-Host "  $($script:ScrubStr.MENU_1)" -ForegroundColor Cyan -NoNewline
        Write-Host $script:ScrubStr.MENU_1_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_2)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_2_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_3)" -ForegroundColor Yellow -NoNewline
        Write-Host $script:ScrubStr.MENU_3_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_4)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_4_DESC -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  $($script:ScrubStr.MENU_5)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_5_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_6)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_6_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_7)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_7_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_8)" -ForegroundColor White -NoNewline
        Write-Host $script:ScrubStr.MENU_8_DESC -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  $($script:ScrubStr.MENU_9)" -ForegroundColor DarkGray -NoNewline
        Write-Host $script:ScrubStr.MENU_9_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_A)" -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_B)" -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_I)" -ForegroundColor DarkGray -NoNewline
        Write-Host $script:ScrubStr.MENU_I_DESC -ForegroundColor DarkGray
        Write-Host "  $($script:ScrubStr.MENU_0)"
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host ""

        switch ((Read-Host "  $($script:ScrubStr.CHOOSE)").Trim().ToLower()) {

            "p" { Step-ActivePreset }

            "1" { Show-SmartRoutine }

            "2" {
                Write-ScrubHeader
                $at = Get-ActiveToggles
                $ac = Get-AdminConflicts -Toggles $at
                if ($ac) { Show-AdminPrompt -Conflicts $ac }
                $res = Invoke-ScrubCustom -Toggles $at -DryRun $true
                $hist = Get-ScrubHistory
                Save-ScrubHistory -History $hist -Keys ($at.Keys | Where-Object { $at[$_] })
                Show-RunSummary -Results $res -DryRun $true
                Open-LatestReport
                $Host.UI.RawUI.FlushInputBuffer()
                Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "3" {
                $at = Get-ActiveToggles
                $ac = Get-AdminConflicts -Toggles $at
                if ($ac) { Show-AdminPrompt -Conflicts $ac }
                if (-not (Show-LivePreview -Toggles $at)) { Write-Host "  $($script:ScrubStr.ABORTED)" -ForegroundColor Yellow; break }
                Write-ScrubHeader
                $res = Invoke-ScrubCustom -Toggles $at -DryRun $false
                $hist = Get-ScrubHistory
                Save-ScrubHistory -History $hist -Keys ($at.Keys | Where-Object { $at[$_] })
                Show-RunSummary -Results $res -DryRun $false
                Open-LatestReport
                $Host.UI.RawUI.FlushInputBuffer()
                Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "4" {
                $toggles = Show-ModuleSelector
                if ($null -eq $toggles) { continue }

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
                $ac = Get-AdminConflicts -Toggles $toggles
                if ($ac) { Show-AdminPrompt -Conflicts $ac }
                $res = Invoke-ScrubCustom -Toggles $toggles -DryRun $dry
                $hist = Get-ScrubHistory
                Save-ScrubHistory -History $hist -Keys ($toggles.Keys | Where-Object { $toggles[$_] })
                Show-RunSummary -Results $res -DryRun $dry
                Open-LatestReport
                $Host.UI.RawUI.FlushInputBuffer()
                Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "5" {
                $diag = @{}
                foreach ($m in $script:CATALOG) { $diag[$m.Key] = $false }
                $diag["driver_audit"]         = $true
                $diag["event_log_scan"]       = $true
                $diag["startup_audit"]        = $true
                $diag["windows_update_check"] = $true

                Write-ScrubHeader
                $res = Invoke-ScrubCustom -Toggles $diag -DryRun $true
                Show-DiagnosticsSummary -Results $res
                Open-LatestReport
                Write-Host ""
                $Host.UI.RawUI.FlushInputBuffer()
                Read-Host "  $($script:ScrubStr.PRESS_ENTER_MENU)" | Out-Null
            }

            "6" { Show-StartupManager }

            "7" { Show-FolderAnalyzer }

            "8" { Show-History }

            "9" { Show-ModuleConfig }

            "i" { Switch-ScrubLanguage }

            "a" {
                Write-ScrubHeader
                $taskName = "Scrub_Daily"
                $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

                if ($existing) {
                    Write-Host "  $($script:ScrubStr.SCHED_CURRENT) $taskName" -ForegroundColor White
                    Write-Host "  $($script:ScrubStr.SCHED_STATUS) $($existing.State)  $($script:ScrubStr.SCHED_NEXT_RUN) $((Get-ScheduledTaskInfo -TaskName $taskName).NextRunTime)" -ForegroundColor Gray
                    Write-Host ""
                    Write-Host "  [R] $($script:ScrubStr.SCHED_REMOVE)   [Q] $($script:ScrubStr.BACK)"
                    Write-Host ""
                    $sub = (Read-Host "  >").Trim().ToUpper()
                    if ($sub -eq "R") {
                        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
                        Write-Host "  $($script:ScrubStr.SCHED_REMOVED)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                    }
                } else {
                    Write-Host "  $($script:ScrubStr.SCHED_CREATE)" -ForegroundColor White
                    Write-Host "  $($script:ScrubStr.SCHED_HINT)" -ForegroundColor DarkGray
                    Write-Host ""
                    $hora = (Read-Host "  $($script:ScrubStr.SCHED_TIME_PROMPT)").Trim()
                    if ($hora -notmatch '^\d{2}:\d{2}$') {
                        Write-Host "  $($script:ScrubStr.SCHED_TIME_ERR)" -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                        continue
                    }
                    try {
                        $action   = New-ScheduledTaskAction -Execute "powershell.exe" `
                            -Argument "-NoLogo -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$moduleRoot\Run-Scrub.ps1`" -NoMenu"
                        $trigger  = New-ScheduledTaskTrigger -Daily -At $hora
                        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -WakeToRun:$false -RunOnlyIfNetworkAvailable:$false
                        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
                        Write-Host "  $($script:ScrubStr.SCHED_OK -f $hora)" -ForegroundColor Green
                    } catch {
                        Write-Host "  $($script:ScrubStr.SCHED_FAIL) $($_.Exception.Message)" -ForegroundColor Red
                    }
                    Start-Sleep -Seconds 2
                }
            }

            "b" {
                Write-ScrubHeader
                $c = Read-Host "  $($script:ScrubStr.UNINSTALL_CONFIRM) ($($script:ScrubStr.CONFIRM_WORD)/N)"
                if ($c -ne $script:ScrubStr.CONFIRM_WORD) {
                    Write-Host "  $($script:ScrubStr.CANCELED)" -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    continue
                }
                & powershell.exe -NoLogo -ExecutionPolicy RemoteSigned `
                    -File (Join-Path $moduleRoot "Install-Scrub.ps1") -Uninstall
                Write-Host ""
                Read-Host "  $($script:ScrubStr.UNINSTALL_EXIT)" | Out-Null
                return
            }

            "0" { Write-Host ""; return }
        }
    }
}

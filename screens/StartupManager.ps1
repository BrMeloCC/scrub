function Show-StartupManager {
    while ($true) {
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.START_TITLE)" -ForegroundColor White
        Write-Host "  $($script:ScrubStr.START_LOADING)" -ForegroundColor DarkGray
        $audit = Get-StartupAudit
        $items = @($audit.Items)

        if ($items.Count -eq 0) {
            Write-Host "  $($script:ScrubStr.START_NONE)" -ForegroundColor DarkGray
            Write-Host ""
            Read-Host "  $($script:ScrubStr.PRESS_ENTER)" | Out-Null
            return
        }

        Clear-Host
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.START_TITLE)  " -ForegroundColor White -NoNewline
        Write-Host "($($items.Count) $($script:ScrubStr.START_ENTRIES))" -ForegroundColor DarkGray
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
        Write-Host "  $($script:ScrubStr.NUM) = $($script:ScrubStr.TOGGLE)   " -NoNewline
        Write-Host "d" -ForegroundColor Cyan -NoNewline
        Write-Host "<N> = $($script:ScrubStr.START_DETAIL)   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "0") { return }

        if ($raw -match '^d(\d+)$') {
            $n = [int]$Matches[1]
            if ($n -ge 1 -and $n -le $items.Count) {
                $it = $items[$n - 1]
                Write-Host ""
                Write-Host "  $($script:ScrubStr.START_NAME):    $($it.Name)"     -ForegroundColor White
                Write-Host "  $($script:ScrubStr.START_TYPE):    $($it.Type)"     -ForegroundColor DarkGray
                Write-Host "  $($script:ScrubStr.START_SCOPE):   $($it.Scope)"    -ForegroundColor DarkGray
                Write-Host "  $($script:ScrubStr.START_CMD):  $($it.Command)"  -ForegroundColor DarkGray
                Write-Host "  $($script:ScrubStr.START_LOC):   $($it.Location)" -ForegroundColor DarkGray
                Write-Host ""
                Read-Host "  $($script:ScrubStr.PRESS_ENTER)" | Out-Null
            }
            continue
        }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $items.Count) {
            $it = $items[$n - 1]
            if ($it.Enabled) {
                $c = Read-Host "  $($script:ScrubStr.START_DISABLE -f $it.Name) ($($script:ScrubStr.CONFIRM_WORD)/N)"
                if ($c -eq $script:ScrubStr.CONFIRM_WORD) {
                    $res = Disable-StartupEntry -Entry $it
                    $col = if ($res.Success) { "Green" } else { "Red" }
                    Write-Host "  $($res.Message)" -ForegroundColor $col
                    Start-Sleep -Seconds 1
                }
            } else {
                $c = Read-Host "  $($script:ScrubStr.START_ENABLE -f $it.Name) ($($script:ScrubStr.CONFIRM_WORD)/N)"
                if ($c -eq $script:ScrubStr.CONFIRM_WORD) {
                    $res = Enable-StartupEntry -Entry $it
                    $col = if ($res.Success) { "Green" } else { "Red" }
                    Write-Host "  $($res.Message)" -ForegroundColor $col
                    Start-Sleep -Seconds 1
                }
            }
        }
    }
}

function Get-EventLogScan {
    param(
        [int]    $LastDays  = 7,
        [int]    $MaxEvents = 500,
        [string] $LogPath   = ""
    )

    $result = [PSCustomObject]@{
        Module      = "EventLogScan"
        LastDays    = $LastDays
        TotalErrors = 0
        Groups      = [System.Collections.Generic.List[object]]::new()
        Errors      = [System.Collections.Generic.List[string]]::new()
    }

    $cutoff    = (Get-Date).AddDays(-$LastDays)
    $rawEvents = [System.Collections.Generic.List[object]]::new()

    foreach ($logName in @("System", "Application")) {
        try {
            $events = Get-WinEvent -FilterHashtable @{
                LogName   = $logName
                Level     = @(1, 2)   # 1=Critical, 2=Error
                StartTime = $cutoff
            } -MaxEvents $MaxEvents -ErrorAction Stop

            foreach ($ev in $events) {
                $msg = if ($ev.Message) { $ev.Message -replace '[\r\n\t]+', ' ' } else { "" }
                if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 297) + "..." }

                $rawEvents.Add([PSCustomObject]@{
                    Log         = $logName
                    Level       = if ($ev.Level -eq 1) { "Critical" } else { "Error" }
                    Source      = $ev.ProviderName
                    EventId     = $ev.Id
                    TimeCreated = $ev.TimeCreated
                    Message     = $msg
                })
            }
        } catch {
            # "No matching events found" is normal -- not an error worth surfacing
            $msg = $_.Exception.Message
            if ($msg -notlike "*No events were found*" -and $msg -notlike "*No matching events*") {
                $result.Errors.Add("SCAN_FAILED: $logName - $msg")
            }
        }
    }

    $result.TotalErrors = $rawEvents.Count

    # Group by Source+EventId to collapse repeated events, sort by frequency
    $grouped = $rawEvents |
        Group-Object -Property Source, EventId |
        Sort-Object Count -Descending

    foreach ($g in $grouped) {
        $sample  = $g.Group[0]
        $lastEv  = $g.Group | Sort-Object TimeCreated -Descending | Select-Object -First 1
        $result.Groups.Add([PSCustomObject]@{
            Source   = $sample.Source
            EventId  = $sample.EventId
            Log      = $sample.Log
            Level    = $sample.Level
            Count    = $g.Count
            LastSeen = $lastEv.TimeCreated
            Message  = $sample.Message
        })
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

function Get-DiskReport {
    param(
        [int]    $AlertUsagePct = 85,
        [string] $LogPath       = ""
    )

    $result = [PSCustomObject]@{
        Module  = "DiskReport"
        Drives  = [System.Collections.Generic.List[object]]::new()
        Alerts  = [System.Collections.Generic.List[string]]::new()
        Errors  = [System.Collections.Generic.List[string]]::new()
    }

    try {
        $disks = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null -and $_.Root -ne $null }

        foreach ($d in $disks) {
            $total   = $d.Used + $d.Free
            $usedPct = if ($total -gt 0) { [math]::Round(($d.Used / $total) * 100, 1) } else { 0 }

            $drive = [PSCustomObject]@{
                Drive      = $d.Root
                Name       = $d.Description
                TotalGB    = [math]::Round($total / 1GB, 2)
                UsedGB     = [math]::Round($d.Used / 1GB, 2)
                FreeGB     = [math]::Round($d.Free / 1GB, 2)
                UsedPct    = $usedPct
                AlertLevel = if ($usedPct -ge $AlertUsagePct) { "WARNING" } elseif ($usedPct -ge ($AlertUsagePct - 10)) { "NOTICE" } else { "OK" }
            }

            $result.Drives.Add($drive)

            if ($usedPct -ge $AlertUsagePct) {
                $result.Alerts.Add("DISK_FULL: $($d.Root) is at $usedPct% capacity ($($drive.FreeGB) GB free)")
            }
        }
    } catch {
        $result.Errors.Add("DISK_REPORT_ERROR: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

function Get-DiskHealth {
    param(
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module  = "HealthCheck"
        Disks   = [System.Collections.Generic.List[object]]::new()
        Alerts  = [System.Collections.Generic.List[string]]::new()
        Errors  = [System.Collections.Generic.List[string]]::new()
    }

    try {
        $physicalDisks = Get-PhysicalDisk -ErrorAction Stop

        foreach ($pd in $physicalDisks) {
            $health = [PSCustomObject]@{
                FriendlyName      = $pd.FriendlyName
                MediaType         = $pd.MediaType
                HealthStatus      = $pd.HealthStatus
                OperationalStatus = $pd.OperationalStatus
                SizeGB            = [math]::Round($pd.Size / 1GB, 2)
                BusType           = $pd.BusType
                AlertLevel        = "OK"
            }

            if ($pd.HealthStatus -ne "Healthy") {
                $health.AlertLevel = "CRITICAL"
                $result.Alerts.Add("DISK_HEALTH: '$($pd.FriendlyName)' status is '$($pd.HealthStatus)' - backup data immediately")
            }

            $result.Disks.Add($health)
        }
    } catch {
        $result.Errors.Add("HEALTH_CHECK_ERROR (may need admin): $($_.Exception.Message)")
    }

    # SMART via WMI as fallback
    try {
        $wmiDisks = Get-WmiObject -Namespace "root\wmi" -Class "MSStorageDriver_FailurePredictStatus" -ErrorAction Stop
        foreach ($wd in $wmiDisks) {
            if ($wd.PredictFailure) {
                $result.Alerts.Add("SMART_FAILURE_PREDICTED: InstanceName=$($wd.InstanceName) - replace disk soon")
            }
        }
    } catch {
        # WMI SMART query requires admin; silently skip if unavailable
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

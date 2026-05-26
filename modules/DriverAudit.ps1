function Get-DriverAudit {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module            = "DriverAudit"
        TotalDevices      = 0
        ProblematicCount  = 0
        ScannedForUpdates = $false
        Items             = [System.Collections.Generic.List[object]]::new()
        Errors            = [System.Collections.Generic.List[string]]::new()
    }

    try {
        $devices = Get-PnpDevice -ErrorAction Stop
        $result.TotalDevices = $devices.Count

        foreach ($d in $devices) {
            if ($d.Status -eq 'OK') { continue }
            $result.ProblematicCount++

            $code = ""
            try {
                $prop = Get-PnpDeviceProperty -InstanceId $d.InstanceId `
                    -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction SilentlyContinue
                if ($prop -and $prop.Data -and [int]$prop.Data -ne 0) {
                    $code = "Code $($prop.Data)"
                }
            } catch { }

            $result.Items.Add([PSCustomObject]@{
                Name        = if ($d.FriendlyName) { $d.FriendlyName } else { $d.Name }
                Class       = if ($d.Class) { $d.Class } else { "Unknown" }
                Status      = $d.Status.ToString()
                ProblemCode = $code
            })
        }

        # Live: trigger pnputil to re-scan hardware and check Windows Update for driver updates
        if (-not $DryRun) {
            try {
                Start-Process "pnputil.exe" -ArgumentList "/scan-devices" -Wait -NoNewWindow -ErrorAction Stop
                $result.ScannedForUpdates = $true
            } catch {
                $result.Errors.Add("PNPUTIL_FAILED: $($_.Exception.Message)")
            }
        }
    } catch {
        $result.Errors.Add("DRIVER_AUDIT_ERROR: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

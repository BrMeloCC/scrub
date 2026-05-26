function Invoke-DiskOptimize {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module  = "DiskOptimize"
        IsAdmin = $false
        Items   = [System.Collections.Generic.List[object]]::new()
        Errors  = [System.Collections.Generic.List[string]]::new()
    }

    $result.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    try {
        $volumes = Get-Volume -ErrorAction Stop |
            Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' }

        foreach ($vol in $volumes) {
            $letter    = [string]$vol.DriveLetter
            $mediaType = "Unknown"

            try {
                $part = Get-Partition -DriveLetter $letter -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($part) {
                    $disk = Get-Disk -Number $part.DiskNumber -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($disk) {
                        $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue |
                            Where-Object { $_.DeviceId -eq "$($disk.Number)" } | Select-Object -First 1
                        if ($phys -and $phys.MediaType -ne 'Unspecified') {
                            $mediaType = $phys.MediaType
                        }
                    }
                }
            } catch { }

            $action = switch ($mediaType) {
                "SSD"   { "ReTrim" }
                "HDD"   { "Defrag" }
                default { "Optimize" }
            }

            $entry = [PSCustomObject]@{
                DriveLetter = $letter
                Label       = $vol.FileSystemLabel
                MediaType   = $mediaType
                Action      = $action
                Status      = if ($DryRun) { "DRY_RUN" } else { "PENDING" }
            }

            if (-not $DryRun) {
                if (-not $result.IsAdmin) {
                    $entry.Status = "REQUIRES_ADMIN"
                } else {
                    try {
                        switch ($mediaType) {
                            "SSD"   { Optimize-Volume -DriveLetter $letter -ReTrim  -ErrorAction Stop }
                            "HDD"   { Optimize-Volume -DriveLetter $letter -Defrag  -ErrorAction Stop }
                            default { Optimize-Volume -DriveLetter $letter           -ErrorAction Stop }
                        }
                        $entry.Status = "OK"
                    } catch {
                        $entry.Status = "ERROR"
                        $result.Errors.Add("OPTIMIZE_FAILED: $letter - $($_.Exception.Message)")
                    }
                }
            }

            $result.Items.Add($entry)
        }
    } catch {
        $result.Errors.Add("DISK_OPTIMIZE_ERROR: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

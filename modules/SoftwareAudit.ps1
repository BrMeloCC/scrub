function Get-SoftwareAudit {
    param(
        [int]    $LastDays = 30,
        [string] $LogPath  = ""
    )

    $result = [PSCustomObject]@{
        Module   = "SoftwareAudit"
        LastDays = $LastDays
        Items    = [System.Collections.Generic.List[object]]::new()
        Errors   = [System.Collections.Generic.List[string]]::new()
    }

    $cutoff = (Get-Date).AddDays(-$LastDays)

    $uninstallPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($path in $uninstallPaths) {
        try {
            $entries = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($e in $entries) {
                $name = $e.DisplayName
                if (-not $name) { continue }

                $installDateRaw = $e.InstallDate
                if (-not $installDateRaw) { continue }

                $installDate = $null
                if ($installDateRaw -match '^\d{8}$') {
                    try {
                        $installDate = [datetime]::ParseExact($installDateRaw, "yyyyMMdd", $null)
                    } catch { continue }
                } else {
                    try {
                        $installDate = [datetime]$installDateRaw
                    } catch { continue }
                }

                if ($installDate -lt $cutoff) { continue }

                $key = "$name|$($e.DisplayVersion)"
                if (-not $seen.Add($key)) { continue }

                $sizeBytes = if ($e.EstimatedSize) { [long]$e.EstimatedSize * 1024 } else { 0 }

                $result.Items.Add([PSCustomObject]@{
                    Name        = $name
                    Publisher   = if ($e.Publisher) { $e.Publisher } else { "" }
                    Version     = if ($e.DisplayVersion) { $e.DisplayVersion } else { "" }
                    InstallDate = $installDate
                    SizeBytes   = $sizeBytes
                    Silent      = [bool]$e.SystemComponent
                })
            }
        } catch {
            $result.Errors.Add("SCAN_FAILED: $path - $($_.Exception.Message)")
        }
    }

    $result.Items = [System.Collections.Generic.List[object]]($result.Items | Sort-Object InstallDate -Descending)

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

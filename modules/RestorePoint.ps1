function Invoke-RestorePoint {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module         = "RestorePoint"
        IsAdmin        = $false
        Created        = $false
        PointName      = ""
        LatestExisting = ""
        Errors         = [System.Collections.Generic.List[string]]::new()
    }

    $result.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    # Always report the most recent existing restore point
    try {
        $latest = Get-ComputerRestorePoint -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -Last 1
        if ($latest) {
            $result.LatestExisting = "$($latest.Description) ($($latest.CreationTime.ToString('yyyy-MM-dd HH:mm')))"
        }
    } catch { }

    if ($DryRun) {
        if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
        return $result
    }

    if (-not $result.IsAdmin) {
        $result.Errors.Add("REQUIRES_ADMIN")
        if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
        return $result
    }

    try {
        $name = "Scrub_$(Get-Date -Format 'yyyyMMdd_HHmm')"
        Checkpoint-Computer -Description $name -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        $result.Created   = $true
        $result.PointName = $name
    } catch {
        $msg = $_.Exception.Message
        # Windows allows at most one restore point per 24h -- not an error worth surfacing loudly
        if ($msg -match "time limit|frequency") {
            $result.PointName = "Skipped (24h limit -- existing point is recent enough)"
        } else {
            $result.Errors.Add("CREATE_FAILED: $msg")
        }
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

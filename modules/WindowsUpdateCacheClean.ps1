function Invoke-WindowsUpdateCacheClean {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module      = "WindowsUpdateCacheClean"
        IsAdmin     = $false
        BytesFreed  = 0L
        Items       = [System.Collections.Generic.List[PSCustomObject]]::new()
        Errors      = [System.Collections.Generic.List[string]]::new()
    }

    $result.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $result.IsAdmin) {
        $result.Errors.Add("REQUIRES_ADMIN")
        if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
        return $result
    }

    $cachePath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"

    if (-not (Test-Path $cachePath)) {
        $result.Errors.Add("Cache path not found: $cachePath")
        return $result
    }

    $files = Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue
    $totalBytes = ($files | Measure-Object -Property Length -Sum).Sum
    if (-not $totalBytes) { $totalBytes = 0L }

    $result.Items.Add([PSCustomObject]@{
        Path      = $cachePath
        FileCount = $files.Count
        SizeBytes = [long]$totalBytes
    })

    if (-not $DryRun) {
        try {
            $svc = Get-Service -Name wuauserv -ErrorAction Stop
            if ($svc.Status -eq "Running") {
                Stop-Service -Name wuauserv -Force -ErrorAction Stop
                $stopped = $true
            } else {
                $stopped = $false
            }

            Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
            $result.BytesFreed = [long]$totalBytes

            if ($stopped) {
                Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            }
        } catch {
            $result.Errors.Add("CLEAN_FAILED: $($_.Exception.Message)")
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

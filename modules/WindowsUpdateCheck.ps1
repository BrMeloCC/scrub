function Invoke-WindowsUpdateCheck {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module       = "WindowsUpdateCheck"
        PendingCount = 0
        Triggered    = $false
        Items        = [System.Collections.Generic.List[object]]::new()
        Errors       = [System.Collections.Generic.List[string]]::new()
    }

    # Query pending updates via COM (no admin required)
    $session = $null
    try {
        $session  = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $found    = $searcher.Search("IsInstalled=0 and Type='Software'")
        $result.PendingCount = $found.Updates.Count

        foreach ($u in $found.Updates) {
            $result.Items.Add([PSCustomObject]@{
                Title    = $u.Title
                Severity = if ($u.MsrcSeverity) { $u.MsrcSeverity } else { "Unspecified" }
                SizeMB   = [math]::Round($u.MaxDownloadSize / 1MB, 1)
            })
        }
    } catch {
        $result.Errors.Add("WU_SEARCH_ERROR: $($_.Exception.Message)")
    } finally {
        if ($session) {
            try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($session) | Out-Null } catch { }
        }
    }

    # Live: trigger Windows Update service to scan, download and install in the background
    if (-not $DryRun) {
        try {
            $usoPath = Join-Path $env:SystemRoot "System32\UsoClient.exe"
            $wuPath  = Join-Path $env:SystemRoot "System32\wuauclt.exe"

            if (Test-Path $usoPath) {
                foreach ($cmd in @("StartScan", "StartDownload", "StartInstall")) {
                    Start-Process $usoPath -ArgumentList $cmd -Wait -NoNewWindow -ErrorAction Stop
                }
            } elseif (Test-Path $wuPath) {
                Start-Process $wuPath -ArgumentList "/detectnow" -Wait -NoNewWindow -ErrorAction Stop
            } else {
                $result.Errors.Add("UPDATE_CLIENT_NOT_FOUND")
            }
            $result.Triggered = $true
        } catch {
            $result.Errors.Add("USO_FAILED: $($_.Exception.Message)")
        }
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

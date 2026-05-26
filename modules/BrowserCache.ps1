# Cache paths per browser -- versioned subfolders handled by scanning at runtime
$BROWSER_CACHE_MAP = @{
    chrome  = @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\Cache_Data",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\GPUCache"
    )
    edge    = @(
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache\Cache_Data",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\GPUCache"
    )
    firefox = @(
        "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    )
}

function Invoke-BrowserCacheClean {
    param(
        [hashtable] $Browsers   = @{ chrome = $true; edge = $true; firefox = $true },
        [int]       $MinAgeDays = 7,
        [bool]      $DryRun     = $true,
        [string]    $LogPath    = ""
    )

    $result = [PSCustomObject]@{
        Module       = "BrowserCache"
        FilesFound   = 0
        FilesDeleted = 0
        BytesFreed   = 0
        Errors       = [System.Collections.Generic.List[string]]::new()
        Items        = [System.Collections.Generic.List[object]]::new()
    }

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)

    foreach ($browser in $Browsers.Keys) {
        if (-not $Browsers[$browser]) { continue }

        $cachePaths = $BROWSER_CACHE_MAP[$browser]
        if (-not $cachePaths) { continue }

        foreach ($basePath in $cachePaths) {
            if (-not (Test-Path $basePath)) { continue }

            # Firefox: find cache2\entries dirs under profiles
            $scanRoots = if ($browser -eq "firefox") {
                Get-ChildItem -Path $basePath -Recurse -Directory -Filter "entries" -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match "cache2" } |
                    Select-Object -ExpandProperty FullName
            } else {
                @($basePath)
            }

            foreach ($scanRoot in $scanRoots) {
                try {
                    $files = Get-ChildItem -Path $scanRoot -File -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.LastWriteTime -lt $cutoff }

                    foreach ($f in $files) {
                        $result.FilesFound++
                        $entry = [PSCustomObject]@{
                            Browser   = $browser
                            Path      = $f.FullName
                            SizeBytes = $f.Length
                            LastWrite = $f.LastWriteTime
                            Deleted   = $false
                        }
                        if (-not $DryRun) {
                            try {
                                Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                                $entry.Deleted       = $true
                                $result.FilesDeleted++
                                $result.BytesFreed  += $f.Length
                            } catch {
                                $result.Errors.Add("DELETE_FAILED [$browser]: $($f.FullName) - $($_.Exception.Message)")
                            }
                        }
                        $result.Items.Add($entry)
                    }
                } catch {
                    $result.Errors.Add("SCAN_FAILED [$browser]: $scanRoot - $($_.Exception.Message)")
                }
            }
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

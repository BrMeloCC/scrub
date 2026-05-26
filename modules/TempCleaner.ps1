# Safe temp directories -- hardcoded whitelist, never expanded from config
$SAFE_TEMP_PATHS = @(
    [System.Environment]::GetEnvironmentVariable("TEMP", "User"),
    [System.Environment]::GetEnvironmentVariable("TMP",  "User"),
    "$env:LOCALAPPDATA\Temp",
    "$env:SystemRoot\Temp",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
    "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db"
)

function Invoke-TempCleaner {
    param(
        [int]    $MinAgeDays = 3,
        [bool]   $DryRun     = $true,
        [string] $LogPath    = ""
    )

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $result = [PSCustomObject]@{
        Module       = "TempCleaner"
        FilesFound   = 0
        FilesDeleted = 0
        BytesFreed   = 0
        Errors       = [System.Collections.Generic.List[string]]::new()
        Items        = [System.Collections.Generic.List[object]]::new()
    }

    $uniquePaths = $SAFE_TEMP_PATHS | Where-Object { $_ } | Sort-Object -Unique

    foreach ($basePath in $uniquePaths) {
        $resolved = try { Get-Item -Path $basePath -ErrorAction SilentlyContinue } catch { $null }
        if (-not $resolved) { continue }

        $dirs  = @($resolved | Where-Object { $_.PSIsContainer })
        $files = @($resolved | Where-Object { -not $_.PSIsContainer })

        foreach ($dir in $dirs) {
            if (-not (Test-Path $dir.FullName)) { continue }
            try {
                $candidates = Get-ChildItem -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt $cutoff }

                foreach ($f in $candidates) {
                    $result.FilesFound++
                    $entry = [PSCustomObject]@{
                        Path      = $f.FullName
                        SizeBytes = $f.Length
                        LastWrite = $f.LastWriteTime
                        Deleted   = $false
                    }
                    if (-not $DryRun) {
                        try {
                            Remove-Item -Path $f.FullName -Force -ErrorAction Stop
                            $entry.Deleted        = $true
                            $result.FilesDeleted++
                            $result.BytesFreed   += $f.Length
                        } catch {
                            $result.Errors.Add("DELETE_FAILED: $($f.FullName) - $($_.Exception.Message)")
                        }
                    }
                    $result.Items.Add($entry)
                }
            } catch {
                $result.Errors.Add("SCAN_FAILED: $($dir.FullName) - $($_.Exception.Message)")
            }
        }

        foreach ($f in $files) {
            if ($f.LastWriteTime -ge $cutoff) { continue }
            $result.FilesFound++
            $entry = [PSCustomObject]@{
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
                    $result.Errors.Add("DELETE_FAILED: $($f.FullName) - $($_.Exception.Message)")
                }
            }
            $result.Items.Add($entry)
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

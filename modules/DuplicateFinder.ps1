function Get-DuplicateFiles {
    param(
        [string[]] $ScanPaths  = @(),
        [int]      $MinSizeKB  = 100,
        [string]   $LogPath    = ""
    )

    $result = [PSCustomObject]@{
        Module        = "DuplicateFinder"
        FilesScanned  = 0
        DuplicateSets = 0
        WastedBytes   = 0
        Items         = [System.Collections.Generic.List[object]]::new()
        Errors        = [System.Collections.Generic.List[string]]::new()
    }

    if (-not $ScanPaths -or $ScanPaths.Count -eq 0) {
        $result.Errors.Add("No scan_paths configured. Set duplicate_finder.scan_paths in config.json.")
        return $result
    }

    $minBytes = $MinSizeKB * 1KB
    $hashMap  = @{}

    foreach ($scanPath in $ScanPaths) {
        if (-not (Test-Path $scanPath)) {
            $result.Errors.Add("PATH_NOT_FOUND: $scanPath")
            continue
        }
        try {
            $files = Get-ChildItem -Path $scanPath -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -ge $minBytes }

            foreach ($f in $files) {
                $result.FilesScanned++
                # Group by size first to avoid hashing unique-size files
                $sizeKey = "size_$($f.Length)"
                if (-not $hashMap.ContainsKey($sizeKey)) {
                    $hashMap[$sizeKey] = [System.Collections.Generic.List[string]]::new()
                }
                $hashMap[$sizeKey].Add($f.FullName)
            }
        } catch {
            $result.Errors.Add("SCAN_FAILED: $scanPath - $($_.Exception.Message)")
        }
    }

    # Second pass: hash only files that share the same size
    $contentHashMap = @{}

    foreach ($key in $hashMap.Keys) {
        $paths = $hashMap[$key]
        if ($paths.Count -lt 2) { continue }

        foreach ($filePath in $paths) {
            try {
                $hash = (Get-FileHash -Path $filePath -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not $contentHashMap.ContainsKey($hash)) {
                    $contentHashMap[$hash] = [System.Collections.Generic.List[string]]::new()
                }
                $contentHashMap[$hash].Add($filePath)
            } catch {
                $result.Errors.Add("HASH_FAILED: $filePath - $($_.Exception.Message)")
            }
        }
    }

    foreach ($hash in $contentHashMap.Keys) {
        $dupes = $contentHashMap[$hash]
        if ($dupes.Count -lt 2) { continue }

        $result.DuplicateSets++
        $firstFile = Get-Item -Path $dupes[0] -ErrorAction SilentlyContinue
        $fileSize  = if ($firstFile) { $firstFile.Length } else { 0 }
        $wasted    = $fileSize * ($dupes.Count - 1)
        $result.WastedBytes += $wasted

        $joinedPaths = $dupes -join "`n"
        $result.Items.Add([PSCustomObject]@{
            Hash      = $hash
            Count     = $dupes.Count
            SizeBytes = $fileSize
            WastedMB  = [math]::Round($wasted / 1MB, 2)
            Paths     = $joinedPaths
        })
    }

    $result.Items = $result.Items | Sort-Object WastedMB -Descending

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

function Invoke-WindowsUpdateCacheClean {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module        = "WindowsUpdateCache"
        RequiresAdmin = $true
        FilesFound    = 0
        FilesDeleted  = 0
        BytesFreed    = 0
        Errors        = [System.Collections.Generic.List[string]]::new()
        Items         = [System.Collections.Generic.List[object]]::new()
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
    if (-not $isAdmin) {
        $result.Errors.Add("REQUIRES_ADMIN: Run PowerShell as Administrator to clean Windows Update cache")
        return $result
    }

    $wuCachePath = "$env:SystemRoot\SoftwareDistribution\Download"

    if (-not (Test-Path $wuCachePath)) {
        $result.Errors.Add("PATH_NOT_FOUND: $wuCachePath")
        return $result
    }

    # Must stop Windows Update service before cleaning to avoid corruption
    if (-not $DryRun) {
        try {
            Stop-Service -Name wuauserv -Force -ErrorAction Stop
        } catch {
            $result.Errors.Add("CANNOT_STOP_WUAUSERV: $($_.Exception.Message) - aborting to avoid corruption")
            return $result
        }
    }

    try {
        $files = Get-ChildItem -Path $wuCachePath -Recurse -File -Force -ErrorAction SilentlyContinue

        foreach ($f in $files) {
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
    } catch {
        $result.Errors.Add("SCAN_FAILED: $($_.Exception.Message)")
    } finally {
        if (-not $DryRun) {
            try { Start-Service -Name wuauserv -ErrorAction SilentlyContinue } catch {}
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

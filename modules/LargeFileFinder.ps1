function Get-LargeFiles {
    param(
        [int]    $ThresholdMB = 100,
        [int]    $Limit       = 50,
        [string] $LogPath     = ""
    )

    $result = [PSCustomObject]@{
        Module        = "LargeFileFinder"
        ThresholdMB   = $ThresholdMB
        FilesFound    = 0
        TotalSizeGB   = 0
        Items         = [System.Collections.Generic.List[object]]::new()
        Errors        = [System.Collections.Generic.List[string]]::new()
    }

    $scanRoots = @($env:USERPROFILE)
    $skipPatterns = @(
        "\\AppData\\Local\\Packages\\",
        "\\AppData\\Local\\Microsoft\\Windows\\",
        "\\AppData\\Roaming\\Microsoft\\Windows\\"
    )

    $thresholdBytes = $ThresholdMB * 1MB
    $collected      = [System.Collections.Generic.List[object]]::new()

    foreach ($root in $scanRoots) {
        if (-not (Test-Path $root)) { continue }
        try {
            Get-ChildItem -Path $root -Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -ge $thresholdBytes } |
                ForEach-Object {
                    $fp = $_.FullName
                    $skip = $false
                    foreach ($pat in $skipPatterns) {
                        if ($fp -match [regex]::Escape($pat)) { $skip = $true; break }
                    }
                    if (-not $skip) {
                        $collected.Add([PSCustomObject]@{
                            Path      = $fp
                            SizeBytes = $_.Length
                            SizeMB    = [math]::Round($_.Length / 1MB, 1)
                            LastWrite = $_.LastWriteTime
                            Extension = $_.Extension
                        })
                    }
                }
        } catch {
            $result.Errors.Add("SCAN_FAILED: $root - $($_.Exception.Message)")
        }
    }

    $sorted = $collected | Sort-Object SizeBytes -Descending | Select-Object -First $Limit
    $result.FilesFound  = $sorted.Count
    $result.TotalSizeGB = [math]::Round(($sorted | Measure-Object -Property SizeBytes -Sum).Sum / 1GB, 2)
    foreach ($item in $sorted) { $result.Items.Add($item) }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

function Get-DownloadsAudit {
    param(
        [int]    $ReportAgeDays = 60,
        [string] $LogPath       = ""
    )

    $result = [PSCustomObject]@{
        Module      = "DownloadsAudit"
        Path        = ""
        FilesTotal  = 0
        FilesOld    = 0
        TotalSizeMB = 0
        OldSizeMB   = 0
        Items       = [System.Collections.Generic.List[object]]::new()
        Errors      = [System.Collections.Generic.List[string]]::new()
    }

    $downloadsPath = Join-Path (Split-Path $env:USERPROFILE -Parent | Split-Path -Parent) "Downloads"
    $downloadsPath = Join-Path $env:USERPROFILE "Downloads"

    # Try Shell.Application for accurate known-folder path
    try {
        $shell  = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace(0x1C1)  # FOLDERID_Downloads
        if ($folder) { $downloadsPath = $folder.Self.Path }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    } catch {}

    $result.Path = $downloadsPath
    $cutoff      = (Get-Date).AddDays(-$ReportAgeDays)

    if (-not (Test-Path $downloadsPath)) {
        $result.Errors.Add("Downloads folder not found: $downloadsPath")
        return $result
    }

    try {
        $files = Get-ChildItem -Path $downloadsPath -File -Recurse -ErrorAction SilentlyContinue

        foreach ($f in $files) {
            $result.FilesTotal++
            $result.TotalSizeMB += $f.Length / 1MB

            if ($f.LastWriteTime -lt $cutoff) {
                $result.FilesOld++
                $result.OldSizeMB += $f.Length / 1MB
                $result.Items.Add([PSCustomObject]@{
                    Name      = $f.Name
                    Path      = $f.FullName
                    SizeMB    = [math]::Round($f.Length / 1MB, 2)
                    LastWrite = $f.LastWriteTime
                })
            }
        }

        $result.TotalSizeMB = [math]::Round($result.TotalSizeMB, 1)
        $result.OldSizeMB   = [math]::Round($result.OldSizeMB, 1)
    } catch {
        $result.Errors.Add("DOWNLOADS_SCAN_FAILED: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

function Invoke-RecycleBinCleaner {
    param(
        [int]    $MinAgeDays = 30,
        [bool]   $DryRun     = $true,
        [string] $LogPath    = ""
    )

    $result = [PSCustomObject]@{
        Module       = "RecycleBin"
        FilesFound   = 0
        FilesDeleted = 0
        BytesFreed   = [long]0
        Errors       = [System.Collections.Generic.List[string]]::new()
        Items        = [System.Collections.Generic.List[object]]::new()
    }

    $cutoff = (Get-Date).AddDays(-$MinAgeDays)
    $sid    = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root })) {
        $rbPath = Join-Path $drive.Root "`$Recycle.Bin\$sid"
        if (-not (Test-Path $rbPath)) { continue }

        try {
            # $R* = dados do item deletado (arquivo ou pasta)
            # $I* = metadados (nome original, data) -- ignorados no scan, removidos junto com $R no live
            $rbItems = Get-ChildItem -Path $rbPath -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\$R' -and $_.LastWriteTime -lt $cutoff }

            foreach ($f in $rbItems) {
                $sizeBytes = if ($f.PSIsContainer) { [long]0 } else { $f.Length }
                $result.FilesFound++

                $entry = [PSCustomObject]@{
                    Name        = $f.Name
                    Path        = $f.FullName
                    SizeBytes   = $sizeBytes
                    DeletedDate = $f.LastWriteTime
                    Deleted     = $false
                }

                if (-not $DryRun) {
                    try {
                        # Remove o $I correspondente pelo nome ($RXXXXXX -> $IXXXXXX)
                        $metaPath = Join-Path $rbPath ('$I' + $f.Name.Substring(2))
                        Remove-Item -Path $f.FullName -Recurse -Force -ErrorAction Stop
                        Remove-Item -Path $metaPath   -Force   -ErrorAction SilentlyContinue
                        $entry.Deleted       = $true
                        $result.FilesDeleted++
                        $result.BytesFreed  += $sizeBytes
                    } catch {
                        $result.Errors.Add("DELETE_FAILED: $($f.FullName) - $($_.Exception.Message)")
                    }
                }

                $result.Items.Add($entry)
            }
        } catch {
            $result.Errors.Add("SCAN_FAILED: $rbPath - $($_.Exception.Message)")
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

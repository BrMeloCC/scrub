function Invoke-NodeCacheClean {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module       = "NodeCacheClean"
        FilesFound   = 0
        FilesDeleted = 0
        BytesFreed   = [long]0
        Items        = [System.Collections.Generic.List[object]]::new()
        Errors       = [System.Collections.Generic.List[string]]::new()
    }

    # Known cache locations per package manager -- no admin needed, all user-owned
    # Using fixed well-known paths avoids spawning npm/yarn/pnpm processes and works
    # even when the tool is not on PATH at scan time.
    $candidates = @(
        @{ Label = "npm";        Path = (Join-Path $env:APPDATA "npm-cache") }
        @{ Label = "yarn v1";    Path = (Join-Path $env:LOCALAPPDATA "Yarn\Cache") }
        @{ Label = "yarn berry"; Path = (Join-Path $env:LOCALAPPDATA "yarn\berry\cache") }
        @{ Label = "pnpm";       Path = (Join-Path $env:LOCALAPPDATA "pnpm\store") }
    )

    foreach ($c in $candidates) {
        if (-not (Test-Path $c.Path)) { continue }

        try {
            $files   = Get-ChildItem $c.Path -Recurse -File -Force -ErrorAction SilentlyContinue
            $count   = $files.Count
            $sizeSum = ($files | Measure-Object Length -Sum).Sum
            if (-not $sizeSum) { $sizeSum = [long]0 }

            $result.FilesFound += $count

            $entry = [PSCustomObject]@{
                Label     = $c.Label
                Path      = $c.Path
                FileCount = $count
                SizeBytes = $sizeSum
                Deleted   = $false
            }

            if (-not $DryRun) {
                try {
                    Remove-Item $c.Path -Recurse -Force -ErrorAction Stop
                    $entry.Deleted        = $true
                    $result.FilesDeleted += $count
                    $result.BytesFreed   += $sizeSum
                } catch {
                    $result.Errors.Add("DELETE_FAILED: $($c.Label) ($($c.Path)) - $($_.Exception.Message)")
                }
            }

            $result.Items.Add($entry)
        } catch {
            $result.Errors.Add("SCAN_FAILED: $($c.Label) ($($c.Path)) - $($_.Exception.Message)")
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

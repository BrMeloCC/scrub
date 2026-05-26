function Invoke-SystemLogClean {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module       = "SystemLogClean"
        FilesFound   = 0
        FilesDeleted = 0
        BytesFreed   = [long]0
        Items        = [System.Collections.Generic.List[object]]::new()
        Errors       = [System.Collections.Generic.List[string]]::new()
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    # Scan targets: each entry defines where to look and whether admin is required to delete
    $targets = @(
        # CBS logs: skip CBS.log (active, locked by TrustedInstaller while running)
        @{
            Label      = "CBS"
            Path       = (Join-Path $env:SystemRoot "Logs\CBS")
            Filter     = "*.log"
            Recurse    = $false
            Exclude    = "CBS.log"
            NeedsAdmin = $true
        }
        # Minidump crash files
        @{
            Label      = "MiniDump"
            Path       = (Join-Path $env:SystemRoot "Minidump")
            Filter     = "*.dmp"
            Recurse    = $false
            Exclude    = ""
            NeedsAdmin = $true
        }
        # User-space crash dumps (no admin needed)
        @{
            Label      = "UserCrashDump"
            Path       = (Join-Path $env:LOCALAPPDATA "CrashDumps")
            Filter     = "*.dmp"
            Recurse    = $false
            Exclude    = ""
            NeedsAdmin = $false
        }
        # Windows Error Reporting archived reports (no admin needed)
        @{
            Label      = "WER"
            Path       = (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\WER\ReportArchive")
            Filter     = "*"
            Recurse    = $true
            Exclude    = ""
            NeedsAdmin = $false
        }
    )

    foreach ($t in $targets) {
        if (-not (Test-Path $t.Path)) { continue }
        try {
            $files = Get-ChildItem -Path $t.Path -Filter $t.Filter -Recurse:$t.Recurse -File -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $t.Exclude -or $_.Name -ne $t.Exclude }

            foreach ($f in $files) {
                $result.FilesFound++
                $canDelete = (-not $t.NeedsAdmin) -or $isAdmin

                $entry = [PSCustomObject]@{
                    Label     = $t.Label
                    Path      = $f.FullName
                    SizeBytes = $f.Length
                    LastWrite = $f.LastWriteTime
                    Deleted   = $false
                }

                if (-not $DryRun) {
                    if (-not $canDelete) {
                        $result.Errors.Add("REQUIRES_ADMIN: $($f.FullName)")
                    } else {
                        try {
                            Remove-Item $f.FullName -Force -ErrorAction Stop
                            $entry.Deleted        = $true
                            $result.FilesDeleted++
                            $result.BytesFreed   += $f.Length
                        } catch {
                            $result.Errors.Add("DELETE_FAILED: $($f.FullName) - $($_.Exception.Message)")
                        }
                    }
                }

                $result.Items.Add($entry)
            }
        } catch {
            $result.Errors.Add("SCAN_FAILED: $($t.Label) - $($_.Exception.Message)")
        }
    }

    # Full memory dump handled separately (single file, often very large)
    $memDump = Join-Path $env:SystemRoot "MEMORY.DMP"
    $memItem = Get-Item $memDump -Force -ErrorAction SilentlyContinue
    if ($memItem) {
        $result.FilesFound++
        $entry = [PSCustomObject]@{
            Label     = "FullMemoryDump"
            Path      = $memItem.FullName
            SizeBytes = $memItem.Length
            LastWrite = $memItem.LastWriteTime
            Deleted   = $false
        }
        if (-not $DryRun) {
            if (-not $isAdmin) {
                $result.Errors.Add("REQUIRES_ADMIN: $($memItem.FullName)")
            } else {
                try {
                    Remove-Item $memItem.FullName -Force -ErrorAction Stop
                    $entry.Deleted        = $true
                    $result.FilesDeleted++
                    $result.BytesFreed   += $memItem.Length
                } catch {
                    $result.Errors.Add("DELETE_FAILED: $($memItem.FullName) - $($_.Exception.Message)")
                }
            }
        }
        $result.Items.Add($entry)
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

$DEV_CLEAN_TARGETS = @(
    "node_modules", ".venv", "venv", "__pycache__", ".pytest_cache",
    "target",                         # Rust / Maven
    "bin", "obj",                     # .NET
    ".next", ".nuxt", ".svelte-kit",  # JS frameworks
    "dist", "build", "out",
    ".cache", ".parcel-cache",
    ".gradle", ".m2"                  # Java
)

function Invoke-DevProjectClean {
    param(
        [string[]] $ScanPaths  = @(),
        [int]      $MinAgeDays = 30,
        [string[]] $Targets    = $DEV_CLEAN_TARGETS,
        [bool]     $DryRun     = $true,
        [string]   $LogPath    = ""
    )

    $result = [PSCustomObject]@{
        Module       = "DevProjectClean"
        DryRun       = $DryRun
        MinAgeDays   = $MinAgeDays
        Projects     = [System.Collections.Generic.List[object]]::new()
        BytesFreed   = 0
        DirsDeleted  = 0
        Errors       = [System.Collections.Generic.List[string]]::new()
    }

    if (-not $ScanPaths -or $ScanPaths.Count -eq 0) {
        if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
        return $result
    }

    $cutoff  = (Get-Date).AddDays(-$MinAgeDays)
    $seen    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetSet = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]$Targets, [System.StringComparer]::OrdinalIgnoreCase)

    foreach ($scanRoot in $ScanPaths) {
        if (-not (Test-Path $scanRoot)) { continue }

        try {
            $projectDirs = Get-ChildItem -Path $scanRoot -Directory -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object {
                    $name = $_.Name
                    -not $targetSet.Contains($name) -and
                    (Get-ChildItem $_.FullName -File -ErrorAction SilentlyContinue | Select-Object -First 1)
                }

            foreach ($proj in $projectDirs) {
                if (-not $seen.Add($proj.FullName)) { continue }

                $heavyFolders = [System.Collections.Generic.List[object]]::new()
                $totalHeavyBytes = 0

                foreach ($target in $Targets) {
                    $tPath = Join-Path $proj.FullName $target
                    if (-not (Test-Path $tPath)) { continue }

                    try {
                        $bytes = 0L
                        try {
                            foreach ($fi in ([System.IO.DirectoryInfo]::new($tPath)).EnumerateFiles('*', [System.IO.SearchOption]::AllDirectories)) {
                                try { $bytes += $fi.Length } catch {}
                            }
                        } catch {}

                        $lastWrite = (Get-Item $tPath -ErrorAction SilentlyContinue).LastWriteTime

                        $heavyFolders.Add([PSCustomObject]@{
                            Name      = $target
                            Path      = $tPath
                            SizeBytes = $bytes
                            LastWrite = $lastWrite
                            Deleted   = $false
                        })
                        $totalHeavyBytes += $bytes
                    } catch {
                        $result.Errors.Add("SCAN_FAILED: $tPath - $($_.Exception.Message)")
                    }
                }

                if ($heavyFolders.Count -eq 0) { continue }

                $projLastWrite = (Get-Item $proj.FullName -ErrorAction SilentlyContinue).LastWriteTime
                $isDue = $projLastWrite -lt $cutoff

                $projEntry = [PSCustomObject]@{
                    Path       = $proj.FullName
                    Name       = $proj.Name
                    LastWrite  = $projLastWrite
                    IsDue      = $isDue
                    HeavyBytes = $totalHeavyBytes
                    Folders    = $heavyFolders
                }

                if (-not $DryRun -and $isDue) {
                    foreach ($hf in $heavyFolders) {
                        try {
                            Remove-Item $hf.Path -Recurse -Force -ErrorAction Stop
                            $hf.Deleted          = $true
                            $result.BytesFreed  += $hf.SizeBytes
                            $result.DirsDeleted++
                        } catch {
                            $result.Errors.Add("DELETE_FAILED: $($hf.Path) - $($_.Exception.Message)")
                        }
                    }
                }

                $result.Projects.Add($projEntry)
            }
        } catch {
            $result.Errors.Add("ROOT_SCAN_FAILED: $scanRoot - $($_.Exception.Message)")
        }
    }

    $result.Projects = [System.Collections.Generic.List[object]](
        $result.Projects | Sort-Object HeavyBytes -Descending)

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

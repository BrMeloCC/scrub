function Invoke-HibernationClean {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module           = "HibernationClean"
        HibernateEnabled = $false
        FastStartupOn    = $false
        FilePath         = (Join-Path $env:SystemDrive "hiberfil.sys")
        FileSizeBytes    = [long]0
        Disabled         = $false
        Errors           = [System.Collections.Generic.List[string]]::new()
    }

    # Read state from registry -- no admin needed
    try {
        $powerKey = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -ErrorAction Stop
        $result.HibernateEnabled = $powerKey.HibernateEnabled -eq 1
        $result.FastStartupOn    = $powerKey.HiberbootEnabled -eq 1
    } catch {
        # Fallback: if registry unreadable, presence of file implies hibernate is on
        $result.HibernateEnabled = Test-Path $result.FilePath
    }

    # Get file size -- hidden+system file, needs -Force
    $hiberItem = Get-Item -Path $result.FilePath -Force -ErrorAction SilentlyContinue
    if ($hiberItem) { $result.FileSizeBytes = $hiberItem.Length }

    # Nothing actionable if hibernate is fully off and no file exists
    if (-not $result.HibernateEnabled -and -not $result.FastStartupOn -and $result.FileSizeBytes -eq 0) {
        if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
        return $result
    }

    if (-not $DryRun) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator
        )
        if (-not $isAdmin) {
            $result.Errors.Add("REQUIRES_ADMIN: Rerun as Administrator to disable hibernate and reclaim space")
        } else {
            try {
                # powercfg /hibernate off removes hiberfil.sys and disables fast startup as well
                $proc = Start-Process "powercfg.exe" -ArgumentList "/hibernate off" -Wait -PassThru -NoNewWindow -ErrorAction Stop
                if ($proc.ExitCode -eq 0) {
                    $result.Disabled = $true
                } else {
                    $result.Errors.Add("POWERCFG_FAILED: exit code $($proc.ExitCode)")
                }
            } catch {
                $result.Errors.Add("POWERCFG_ERROR: $($_.Exception.Message)")
            }
        }
    }

    if ($LogPath) { Write-ScrubLog -LogPath $LogPath -Entry $result }
    return $result
}

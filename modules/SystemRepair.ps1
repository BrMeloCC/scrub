function Invoke-SystemRepair {
    param(
        [bool]   $DryRun  = $true,
        [string] $LogPath = ""
    )

    $result = [PSCustomObject]@{
        Module     = "SystemRepair"
        IsAdmin    = $false
        SfcStatus  = "SKIPPED"
        DismStatus = "SKIPPED"
        Errors     = [System.Collections.Generic.List[string]]::new()
    }

    $result.IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if (-not $result.IsAdmin) {
        $result.Errors.Add("REQUIRES_ADMIN")
        if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
        return $result
    }

    # DryRun: DISM /CheckHealth only (fast, seconds, no side effects)
    # Live:   SFC /scannow (10-20 min) + DISM /RestoreHealth (10-30 min)

    if (-not $DryRun) {
        try {
            $p = Start-Process "$env:SystemRoot\System32\sfc.exe" -ArgumentList "/scannow" `
                -Wait -PassThru -NoNewWindow -ErrorAction Stop
            $result.SfcStatus = switch ($p.ExitCode) {
                0       { "OK" }
                2       { "REPAIRED" }
                3       { "ISSUES_REMAIN" }
                default { "ExitCode $($p.ExitCode)" }
            }
        } catch {
            $result.SfcStatus = "ERROR"
            $result.Errors.Add("SFC_FAILED: $($_.Exception.Message)")
        }
    }

    $dismArgs = if ($DryRun) { "/Online /Cleanup-Image /CheckHealth" } else { "/Online /Cleanup-Image /RestoreHealth" }
    try {
        $dismOut = Join-Path $env:TEMP "fax_dism_$(Get-Date -Format 'yyyyMMddHHmmss').txt"
        $p = Start-Process "$env:SystemRoot\System32\dism.exe" -ArgumentList $dismArgs `
            -Wait -PassThru -NoNewWindow -RedirectStandardOutput $dismOut -ErrorAction Stop
        $raw = if (Test-Path $dismOut) { Get-Content $dismOut -Raw -ErrorAction SilentlyContinue } else { "" }
        Remove-Item $dismOut -Force -ErrorAction SilentlyContinue

        $result.DismStatus = if ($p.ExitCode -eq 0) {
            if ($raw -match "No component store corruption detected") { "OK" }
            elseif ($raw -match "repairable")                        { "REPAIRABLE" }
            elseif ($DryRun)                                         { "OK" }
            else                                                     { "OK_OR_REPAIRED" }
        } else {
            "ExitCode $($p.ExitCode)"
        }
    } catch {
        $result.DismStatus = "ERROR"
        $result.Errors.Add("DISM_FAILED: $($_.Exception.Message)")
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

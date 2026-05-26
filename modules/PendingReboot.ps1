function Get-PendingRebootCheck {
    param([string] $LogPath = "")

    $result = [PSCustomObject]@{
        Module         = "PendingReboot"
        RebootRequired = $false
        Reasons        = [System.Collections.Generic.List[string]]::new()
        Errors         = [System.Collections.Generic.List[string]]::new()
    }

    $checks = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing"; Key = "RebootPending";                    Label = "Windows Update (CBS)" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update"; Key = "RebootRequired";                   Label = "Windows Update" }
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager";                    Key = "PendingFileRenameOperations";      Label = "Pending file rename" }
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Updates";                                          Key = "UpdateExeVolatile";                Label = "Pending update executable" }
    )

    foreach ($c in $checks) {
        try {
            if (-not (Test-Path $c.Path)) { continue }
            $val = Get-ItemProperty -Path $c.Path -Name $c.Key -ErrorAction SilentlyContinue
            if ($null -ne $val -and $null -ne $val.($c.Key)) {
                $result.RebootRequired = $true
                $result.Reasons.Add($c.Label)
            }
        } catch {
            $result.Errors.Add("CHECK_FAILED: $($c.Label) - $($_.Exception.Message)")
        }
    }

    if ($LogPath) { Write-FaxLog -LogPath $LogPath -Entry $result }
    return $result
}

function Get-FolderTree {
    param(
        [string] $Path,
        [int]    $MaxDepth = 1
    )

    $result = [PSCustomObject]@{
        Path       = $Path
        TotalBytes = 0L
        Children   = [System.Collections.Generic.List[object]]::new()
        Errors     = [System.Collections.Generic.List[string]]::new()
    }

    if (-not (Test-Path $Path -PathType Container)) {
        $result.Errors.Add("PATH_NOT_FOUND: $Path")
        return $result
    }

    try {
        $rootInfo = [System.IO.DirectoryInfo]::new($Path)

        try {
            foreach ($fi in $rootInfo.EnumerateFiles()) {
                try { $result.TotalBytes += $fi.Length } catch {}
            }
        } catch {}

        foreach ($d in $rootInfo.EnumerateDirectories()) {
            $lbl = if ($script:FaxStr -and $script:FaxStr.FOLD_CHECKING) { $script:FaxStr.FOLD_CHECKING } else { "verificando" }
            Write-Host "`r  $lbl $($d.Name)...                              " -NoNewline -ForegroundColor DarkGray
            $bytes = 0L
            try {
                foreach ($fi in $d.EnumerateFiles('*', [System.IO.SearchOption]::AllDirectories)) {
                    try { $bytes += $fi.Length } catch {}
                }
            } catch {
                $result.Errors.Add("SCAN_PARTIAL: $($d.FullName)")
            }
            $result.TotalBytes += $bytes
            $result.Children.Add([PSCustomObject]@{
                Name      = $d.Name
                Path      = $d.FullName
                SizeBytes = $bytes
            })
        }
        Write-Host "`r$(' ' * 70)`r" -NoNewline
    } catch {
        $result.Errors.Add("DIR_SCAN_FAILED: $Path - $($_.Exception.Message)")
    }

    $result.Children = [System.Collections.Generic.List[object]](
        $result.Children | Sort-Object SizeBytes -Descending)

    return $result
}

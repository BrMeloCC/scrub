function Show-FolderAnalyzer {
    param([string]$StartPath = "")

    if (-not $StartPath) {
        Clear-Host
        Write-ScrubHeader
        Write-Host "  $($script:ScrubStr.FOLD_TITLE)" -ForegroundColor White
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "   1  " -NoNewline; Write-Host $script:ScrubStr.FOLD_PROFILE -ForegroundColor White -NoNewline
        Write-Host "   $env:USERPROFILE" -ForegroundColor DarkGray
        Write-Host "   2  " -NoNewline; Write-Host $script:ScrubStr.FOLD_DRIVE -ForegroundColor White
        Write-Host "   3  " -NoNewline; Write-Host $script:ScrubStr.FOLD_TYPE_PATH -ForegroundColor White
        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        Write-Host "  [1-3]   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""
        $entry = (Read-Host "  >").Trim()
        switch ($entry) {
            "0" { return }
            "1" { $StartPath = $env:USERPROFILE }
            "2" {
                $picked = Invoke-DrivePickerMenu
                if (-not $picked) { return }
                $StartPath = $picked
            }
            "3" {
                $typed = (Read-Host "  $($script:ScrubStr.FOLD_PATH_PROMPT)").Trim()
                if (Test-Path $typed -PathType Container) { $StartPath = $typed }
                else { Write-Host "  $($script:ScrubStr.NOT_FOUND)" -ForegroundColor Yellow; Start-Sleep 1; return }
            }
            default { return }
        }
    }

    $currentPath = $StartPath
    $tree        = $null
    $page        = 0
    $pageSize    = 20

    while ($true) {
        if ($null -eq $tree) {
            Clear-Host
            Write-ScrubHeader
            Write-Host "  $($script:ScrubStr.FOLD_TITLE)  " -ForegroundColor White -NoNewline
            Write-Host $script:ScrubStr.LOADING -ForegroundColor DarkGray
            $tree = Get-FolderTree -Path $currentPath
        }

        $children   = @($tree.Children)
        $totalPages = [math]::Max(1, [math]::Ceiling($children.Count / $pageSize))
        $page       = [math]::Min($page, $totalPages - 1)
        $pageStart  = $page * $pageSize
        $pageEnd    = [math]::Min($pageStart + $pageSize - 1, $children.Count - 1)
        $pageItems  = if ($children.Count -gt 0) { @($children[$pageStart..$pageEnd]) } else { @() }

        Clear-Host
        Write-Host "  $currentPath" -ForegroundColor Cyan
        $totalLabel = if ($tree.TotalBytes -gt 0) { "  $($script:ScrubStr.FOLD_TOTAL) $(ConvertTo-ScrubBytes $tree.TotalBytes)" } else { "" }
        Write-Host $totalLabel -ForegroundColor DarkGray
        Write-Host ""

        for ($i = 0; $i -lt $pageItems.Count; $i++) {
            $c   = $pageItems[$i]
            $pct = if ($tree.TotalBytes -gt 0) { [int][math]::Round(100 * $c.SizeBytes / $tree.TotalBytes) } else { 0 }
            $bar = Format-SizeBar -Bytes $c.SizeBytes -Total $tree.TotalBytes
            Write-Host ("  " + "$($i + 1)".PadLeft(2) + "  ") -NoNewline
            Write-Host $bar -ForegroundColor Cyan -NoNewline
            Write-Host ("  " + "$pct%".PadLeft(4) + "  ") -ForegroundColor DarkGray -NoNewline
            Write-Host ($c.Name.PadRight(30)) -ForegroundColor White -NoNewline
            Write-Host (ConvertTo-ScrubBytes $c.SizeBytes) -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host ("  " + ("-" * 52)) -ForegroundColor DarkGray
        $canGoUp = (Split-Path $currentPath -Parent) -ne $currentPath -and (Split-Path $currentPath -Parent) -ne ""
        Write-Host "  [1-$($pageItems.Count)] $($script:ScrubStr.FOLD_ENTER)   " -NoNewline
        if ($canGoUp) { Write-Host "U" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:ScrubStr.FOLD_UP)   " -NoNewline }
        if ($totalPages -gt 1) {
            if ($page -lt $totalPages - 1) { Write-Host "N" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:ScrubStr.FOLD_NEXT)   " -NoNewline }
            if ($page -gt 0)               { Write-Host "P" -ForegroundColor Cyan -NoNewline; Write-Host " = $($script:ScrubStr.FOLD_PREV)   " -NoNewline }
            Write-Host "($($page+1)/$totalPages)" -ForegroundColor DarkGray -NoNewline
            Write-Host "   " -NoNewline
        }
        Write-Host "C" -ForegroundColor Yellow -NoNewline
        Write-Host " = $($script:ScrubStr.FOLD_PATH)   " -NoNewline
        Write-Host "0" -ForegroundColor DarkGray -NoNewline
        Write-Host " = $($script:ScrubStr.BACK)"
        Write-Host ""

        $raw = (Read-Host "  >").Trim().ToLower()
        if ($raw -eq "0") { return }
        if ($raw -eq "n" -and $page -lt $totalPages - 1) { $page++; continue }
        if ($raw -eq "p" -and $page -gt 0)               { $page--; continue }
        if ($raw -eq "u" -and $canGoUp) {
            $currentPath = Split-Path $currentPath -Parent
            $tree = $null; $page = 0; continue
        }
        if ($raw -eq "c") {
            $picked = Invoke-DrivePickerMenu
            if ($picked) { $currentPath = $picked; $tree = $null; $page = 0 }
            continue
        }
        $n = 0
        if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le $pageItems.Count) {
            $currentPath = $pageItems[$n - 1].Path
            $tree = $null; $page = 0
        }
    }
}

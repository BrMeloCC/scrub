function Write-ScrubHtmlReport {
    param(
        [hashtable] $Results,
        [string]    $ReportPath,
        [bool]      $DryRun = $true
    )

    $modeLabel  = if ($DryRun) { "DRY RUN" } else { "LIVE" }
    $modeBadge  = if ($DryRun) { "badge-dryrun" } else { "badge-live" }
    $runDate    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    function _HumanBytes([long]$b) {
        if ($b -ge 1GB) { return "$([math]::Round($b/1GB,2)) GB" }
        if ($b -ge 1MB) { return "$([math]::Round($b/1MB,1)) MB" }
        if ($b -ge 1KB) { return "$([math]::Round($b/1KB,0)) KB" }
        return "$b B"
    }

    # ── Summary section ──────────────────────────────────────────────────────
    $sections = [System.Text.StringBuilder]::new()
    $summaryRows = [System.Text.StringBuilder]::new()
    $grandFreed = 0L
    $grandPotential = 0L

    $moduleLabels = @{
        TempCleaner        = "Temp Files"
        RecycleBin         = "Recycle Bin"
        BrowserCache       = "Browser Cache"
        SystemLogClean     = "System Logs"
        NodeCacheClean     = "Node.js Caches"
        HiberfileCleaner   = "Hiberfil.sys"
        DevProjectClean    = "Dev Project Cleanup"
        WindowsUpdateCache = "Windows Update Cache"
    }

    foreach ($key in $moduleLabels.Keys) {
        if (-not $Results.ContainsKey($key)) { continue }
        $r = $Results[$key]
        $freed = if ($r.BytesFreed) { [long]$r.BytesFreed } else { 0L }
        $potential = 0L
        if ($r.Items) { foreach ($item in $r.Items) { if ($item.SizeBytes) { $potential += [long]$item.SizeBytes } } }
        if ($freed -eq 0 -and $potential -eq 0) { continue }
        $grandFreed += $freed
        $grandPotential += $potential
        $label = $moduleLabels[$key]
        if ($freed -gt 0) {
            [void]$summaryRows.Append("<tr><td>$label</td><td style='color:#3fb950'>$(_HumanBytes $freed)</td><td>—</td></tr>")
        } else {
            [void]$summaryRows.Append("<tr><td>$label</td><td>—</td><td style='color:#d29922'>$(_HumanBytes $potential)</td></tr>")
        }
    }

    if ($summaryRows.Length -gt 0) {
        $totalFreed = if ($grandFreed -gt 0) { "<strong style='color:#3fb950'>$(_HumanBytes $grandFreed)</strong>" } else { "—" }
        $totalPot   = if ($grandPotential -gt 0) { "<strong style='color:#d29922'>$(_HumanBytes $grandPotential)</strong>" } else { "—" }
        [void]$sections.Append('<section id="summary"><h2>Summary</h2>')
        [void]$sections.Append('<table><thead><tr><th>Module</th><th>Freed</th><th>Would free</th></tr></thead><tbody>')
        [void]$sections.Append($summaryRows.ToString())
        [void]$sections.Append("<tr style='border-top:1px solid #30363d'><td><strong>Total</strong></td><td>$totalFreed</td><td>$totalPot</td></tr>")
        [void]$sections.Append('</tbody></table></section>')
    }

    # ── Pending Reboot section ───────────────────────────────────
    if ($Results.ContainsKey("PendingReboot")) {
        $pr = $Results["PendingReboot"]
        if ($pr.RebootRequired) {
            [void]$sections.Append('<section><h2>Pending Reboot</h2>')
            [void]$sections.Append("<p style='color:#f85149'><strong>Reboot required</strong> &mdash; system may be unstable until restarted.</p>")
            [void]$sections.Append('<table><thead><tr><th>Reason</th></tr></thead><tbody>')
            foreach ($r in $pr.Reasons) {
                [void]$sections.Append("<tr class='row-critical'><td>$([System.Web.HttpUtility]::HtmlEncode($r))</td></tr>")
            }
            [void]$sections.Append('</tbody></table></section>')
        }
    }

    # ── Disk Report section ──────────────────────────────────────
    if ($Results.ContainsKey("DiskReport")) {
        $dr = $Results["DiskReport"]
        [void]$sections.Append('<section><h2>Disk Space</h2><table><thead><tr><th>Drive</th><th>Total</th><th>Used</th><th>Free</th><th>Used %</th><th>Status</th></tr></thead><tbody>')
        foreach ($d in $dr.Drives) {
            $cls = switch ($d.AlertLevel) { "WARNING" { "row-warn" } "NOTICE" { "row-notice" } default { "" } }
            [void]$sections.Append("<tr class='$cls'><td>$($d.Drive)</td><td>$($d.TotalGB) GB</td><td>$($d.UsedGB) GB</td><td>$($d.FreeGB) GB</td><td>$($d.UsedPct)%</td><td>$($d.AlertLevel)</td></tr>")
        }
        [void]$sections.Append('</tbody></table></section>')
    }

    # ── Health Check section ─────────────────────────────────────
    if ($Results.ContainsKey("HealthCheck")) {
        $hc = $Results["HealthCheck"]
        [void]$sections.Append('<section><h2>Disk Health (SMART)</h2><table><thead><tr><th>Disk</th><th>Type</th><th>Size</th><th>Health</th><th>Status</th></tr></thead><tbody>')
        foreach ($d in $hc.Disks) {
            $cls = if ($d.AlertLevel -eq "CRITICAL") { "row-critical" } else { "" }
            [void]$sections.Append("<tr class='$cls'><td>$($d.FriendlyName)</td><td>$($d.MediaType)</td><td>$($d.SizeGB) GB</td><td>$($d.HealthStatus)</td><td>$($d.AlertLevel)</td></tr>")
        }
        foreach ($err in $hc.Errors) {
            [void]$sections.Append("<tr class='row-notice'><td colspan='5'>$err</td></tr>")
        }
        [void]$sections.Append('</tbody></table></section>')
    }

    # ── Driver Audit section ─────────────────────────────────────
    if ($Results.ContainsKey("DriverAudit")) {
        $da = $Results["DriverAudit"]
        [void]$sections.Append('<section><h2>Driver Audit</h2>')
        if ($da.ProblematicCount -eq 0) {
            [void]$sections.Append("<p style='color:#3fb950'>All <strong>$($da.TotalDevices)</strong> devices OK.</p>")
        } else {
            [void]$sections.Append("<p><strong>$($da.TotalDevices)</strong> devices scanned &mdash; <span style='color:#d29922'><strong>$($da.ProblematicCount) problematic</strong></span></p>")
            [void]$sections.Append('<table><thead><tr><th>Device</th><th>Class</th><th>Status</th><th>Problem Code</th></tr></thead><tbody>')
            foreach ($item in $da.Items) {
                [void]$sections.Append("<tr class='row-warn'><td>$([System.Web.HttpUtility]::HtmlEncode($item.Name))</td><td>$($item.Class)</td><td>$($item.Status)</td><td>$($item.ProblemCode)</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        if ($da.ScannedForUpdates) {
            [void]$sections.Append("<p style='color:#8b949e;font-size:12px'>Driver update scan triggered via pnputil.</p>")
        }
        [void]$sections.Append('</section>')
    }

    # ── Hiberfil section ─────────────────────────────────────────
    if ($Results.ContainsKey("HiberfileCleaner")) {
        $hf = $Results["HiberfileCleaner"]
        [void]$sections.Append('<section><h2>Hiberfil.sys</h2>')
        if ($hf.Disabled) {
            [void]$sections.Append("<p style='color:#3fb950'><strong>Hibernate disabled</strong> &mdash; $(_HumanBytes $hf.FileSizeBytes) freed.</p>")
        } elseif ($hf.HibernateEnabled -or $hf.FastStartupOn -or $hf.FileSizeBytes -gt 0) {
            $flags = @()
            if ($hf.HibernateEnabled) { $flags += "Hibernate" }
            if ($hf.FastStartupOn)    { $flags += "Fast Startup" }
            $flagStr = if ($flags.Count -gt 0) { $flags -join " + " } else { "enabled" }
            $cls = if ($hf.FileSizeBytes -ge 4GB) { "row-warn" } else { "" }
            [void]$sections.Append("<table><thead><tr><th>Feature</th><th>File</th><th>Size</th><th>Action</th></tr></thead><tbody>")
            [void]$sections.Append("<tr class='$cls'><td>$flagStr</td><td><code>$($hf.FilePath)</code></td><td>$(_HumanBytes $hf.FileSizeBytes)</td><td>Run Live as Admin to disable</td></tr>")
            [void]$sections.Append("</tbody></table>")
            [void]$sections.Append("<p style='color:#8b949e;font-size:12px;margin-top:8px'>Note: disabling hibernate also turns off Fast Startup (slightly slower cold boots).</p>")
        } else {
            [void]$sections.Append("<p>Hibernate is off &mdash; no hiberfil.sys found.</p>")
        }
        foreach ($err in $hf.Errors) {
            [void]$sections.Append("<p style='color:#f85149'>$([System.Web.HttpUtility]::HtmlEncode($err))</p>")
        }
        [void]$sections.Append('</section>')
    }

    # ── Restore Point section ────────────────────────────────────
    if ($Results.ContainsKey("RestorePoint")) {
        $rp = $Results["RestorePoint"]
        [void]$sections.Append('<section><h2>System Restore Point</h2>')
        if ($rp.Created) {
            [void]$sections.Append("<p style='color:#3fb950'>Created: <strong>$([System.Web.HttpUtility]::HtmlEncode($rp.PointName))</strong></p>")
        } elseif ($rp.PointName) {
            [void]$sections.Append("<p style='color:#8b949e'>$([System.Web.HttpUtility]::HtmlEncode($rp.PointName))</p>")
        } elseif ($DryRun) {
            [void]$sections.Append("<p style='color:#8b949e'>Skipped in dry-run mode.</p>")
        }
        if ($rp.LatestExisting) {
            [void]$sections.Append("<p style='color:#8b949e;font-size:12px'>Latest existing point: $([System.Web.HttpUtility]::HtmlEncode($rp.LatestExisting))</p>")
        }
        foreach ($err in $rp.Errors) {
            [void]$sections.Append("<p style='color:#f85149'>$([System.Web.HttpUtility]::HtmlEncode($err))</p>")
        }
        [void]$sections.Append('</section>')
    }

    # ── Temp Cleaner section ─────────────────────────────────────
    if ($Results.ContainsKey("TempCleaner")) {
        $tc = $Results["TempCleaner"]
        $totalSize = 0L; foreach ($item in $tc.Items) { $totalSize += $item.SizeBytes }
        [void]$sections.Append("<section><h2>Temp Files</h2>")
        [void]$sections.Append("<p>Found <strong>$($tc.FilesFound)</strong> files &mdash; <strong>$(_HumanBytes $totalSize)</strong> recoverable</p>")
        if ($tc.Items.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show files</summary><table><thead><tr><th>Path</th><th>Size</th><th>Last Write</th><th>Deleted</th></tr></thead><tbody>')
            foreach ($item in ($tc.Items | Select-Object -First 200)) {
                $del = if ($item.Deleted) { "yes" } else { "-" }
                [void]$sections.Append("<tr><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Path))</td><td>$(_HumanBytes $item.SizeBytes)</td><td>$($item.LastWrite.ToString('yyyy-MM-dd'))</td><td>$del</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Recycle Bin section ──────────────────────────────────────
    if ($Results.ContainsKey("RecycleBin")) {
        $rb = $Results["RecycleBin"]
        [void]$sections.Append("<section><h2>Recycle Bin</h2>")
        [void]$sections.Append("<p>Found <strong>$($rb.FilesFound)</strong> old items</p>")
        if ($rb.Items.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show items</summary><table><thead><tr><th>Name</th><th>Size</th><th>Deleted Date</th><th>Removed</th></tr></thead><tbody>')
            foreach ($item in $rb.Items) {
                $del = if ($item.Deleted) { "yes" } else { "-" }
                [void]$sections.Append("<tr><td>$([System.Web.HttpUtility]::HtmlEncode($item.Name))</td><td>$(_HumanBytes $item.SizeBytes)</td><td>$($item.DeletedDate.ToString('yyyy-MM-dd'))</td><td>$del</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        [void]$sections.Append('</section>')
    }

    # ── System Log Clean section ─────────────────────────────────
    if ($Results.ContainsKey("SystemLogClean")) {
        $sl = $Results["SystemLogClean"]
        $totalSize = 0L; foreach ($item in $sl.Items) { $totalSize += $item.SizeBytes }
        [void]$sections.Append("<section><h2>System Logs &amp; Crash Dumps</h2>")
        [void]$sections.Append("<p>Found <strong>$($sl.FilesFound)</strong> files &mdash; <strong>$(_HumanBytes $totalSize)</strong> recoverable</p>")
        if ($sl.FilesDeleted -gt 0) {
            [void]$sections.Append("<p style='color:#3fb950'>Deleted $($sl.FilesDeleted) files, freed $(_HumanBytes $sl.BytesFreed)</p>")
        }
        if ($sl.Items.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show files</summary><table><thead><tr><th>Type</th><th>Path</th><th>Size</th><th>Last Write</th><th>Deleted</th></tr></thead><tbody>')
            foreach ($item in $sl.Items) {
                $del = if ($item.Deleted) { "yes" } else { "-" }
                [void]$sections.Append("<tr><td>$($item.Label)</td><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Path))</td><td>$(_HumanBytes $item.SizeBytes)</td><td>$($item.LastWrite.ToString('yyyy-MM-dd'))</td><td>$del</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Browser Cache section ────────────────────────────────────
    if ($Results.ContainsKey("BrowserCache")) {
        $bc = $Results["BrowserCache"]
        $totalSize = 0L; foreach ($item in $bc.Items) { $totalSize += $item.SizeBytes }
        [void]$sections.Append("<section><h2>Browser Cache</h2>")
        [void]$sections.Append("<p>Found <strong>$($bc.FilesFound)</strong> old cache files &mdash; <strong>$(_HumanBytes $totalSize)</strong></p>")
        [void]$sections.Append('</section>')
    }

    # ── Node Cache section ───────────────────────────────────────
    if ($Results.ContainsKey("NodeCacheClean")) {
        $nc = $Results["NodeCacheClean"]
        [void]$sections.Append('<section><h2>Node.js Package Caches</h2>')
        if ($nc.Items.Count -eq 0) {
            [void]$sections.Append('<p>No caches found (npm / yarn / pnpm not installed).</p>')
        } else {
            $totalSize = 0L; foreach ($item in $nc.Items) { $totalSize += $item.SizeBytes }
            [void]$sections.Append("<p>Found <strong>$($nc.Items.Count)</strong> cache(s) &mdash; <strong>$(_HumanBytes $totalSize)</strong></p>")
            [void]$sections.Append('<table><thead><tr><th>Manager</th><th>Path</th><th>Files</th><th>Size</th><th>Deleted</th></tr></thead><tbody>')
            foreach ($item in $nc.Items) {
                $del = if ($item.Deleted) { "yes" } else { "-" }
                [void]$sections.Append("<tr><td>$($item.Label)</td><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Path))</td><td>$($item.FileCount)</td><td>$(_HumanBytes $item.SizeBytes)</td><td>$del</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Large Files section ──────────────────────────────────────
    if ($Results.ContainsKey("LargeFiles")) {
        $lf = $Results["LargeFiles"]
        [void]$sections.Append("<section><h2>Large Files (top $($lf.FilesFound))</h2>")
        [void]$sections.Append("<p>Total: <strong>$($lf.TotalSizeGB) GB</strong> across $($lf.FilesFound) files over $($lf.ThresholdMB) MB</p>")
        if ($lf.Items.Count -gt 0) {
            [void]$sections.Append('<table><thead><tr><th>Path</th><th>Size</th><th>Last Write</th><th>Type</th></tr></thead><tbody>')
            foreach ($item in $lf.Items) {
                [void]$sections.Append("<tr><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Path))</td><td>$($item.SizeMB) MB</td><td>$($item.LastWrite.ToString('yyyy-MM-dd'))</td><td>$($item.Extension)</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Downloads Audit section ──────────────────────────────────
    if ($Results.ContainsKey("DownloadsAudit")) {
        $da = $Results["DownloadsAudit"]
        [void]$sections.Append("<section><h2>Downloads Audit</h2>")
        [void]$sections.Append("<p>Folder: <code>$($da.Path)</code></p>")
        [void]$sections.Append("<p>Total: <strong>$($da.FilesTotal)</strong> files ($($da.TotalSizeMB) MB) &mdash; <strong>$($da.FilesOld)</strong> old files ($($da.OldSizeMB) MB)</p>")
        if ($da.Items.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show old files</summary><table><thead><tr><th>Name</th><th>Size</th><th>Last Write</th></tr></thead><tbody>')
            foreach ($item in $da.Items) {
                [void]$sections.Append("<tr><td>$([System.Web.HttpUtility]::HtmlEncode($item.Name))</td><td>$($item.SizeMB) MB</td><td>$($item.LastWrite.ToString('yyyy-MM-dd'))</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Event Log Scan section ───────────────────────────────────────
    if ($Results.ContainsKey("EventLogScan")) {
        $el = $Results["EventLogScan"]
        [void]$sections.Append("<section><h2>Event Log (last $($el.LastDays) days)</h2>")
        $critCount = 0; foreach ($g in $el.Groups) { if ($g.Level -eq "Critical") { $critCount++ } }
        [void]$sections.Append("<p>Found <strong>$($el.TotalErrors)</strong> errors/criticals across <strong>$($el.Groups.Count)</strong> unique sources</p>")
        if ($critCount -gt 0) {
            [void]$sections.Append("<p style='color:#f85149'><strong>$critCount Critical event source(s)</strong></p>")
        }
        if ($el.Groups.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show events</summary><table><thead><tr><th>Source</th><th>ID</th><th>Log</th><th>Level</th><th>Count</th><th>Last Seen</th><th>Message</th></tr></thead><tbody>')
            foreach ($item in ($el.Groups | Select-Object -First 100)) {
                $levelCls = if ($item.Level -eq "Critical") { "row-critical" } elseif ($item.Count -ge 10) { "row-warn" } else { "" }
                $lastSeen = if ($item.LastSeen) { $item.LastSeen.ToString('yyyy-MM-dd HH:mm') } else { "-" }
                [void]$sections.Append("<tr class='$levelCls'><td>$([System.Web.HttpUtility]::HtmlEncode($item.Source))</td><td>$($item.EventId)</td><td>$($item.Log)</td><td>$($item.Level)</td><td>$($item.Count)</td><td>$lastSeen</td><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Message))</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        foreach ($err in $el.Errors) {
            [void]$sections.Append("<p style='color:#f85149'>$([System.Web.HttpUtility]::HtmlEncode($err))</p>")
        }
        [void]$sections.Append('</section>')
    }

    # ── Startup Audit section ────────────────────────────────────
    if ($Results.ContainsKey("StartupAudit")) {
        $sa = $Results["StartupAudit"]
        [void]$sections.Append("<section><h2>Startup Programs</h2>")
        [void]$sections.Append("<p><strong>$($sa.Items.Count)</strong> startup entries found</p>")
        if ($sa.Items.Count -gt 0) {
            [void]$sections.Append('<details><summary>Show entries</summary><table><thead><tr><th>Name</th><th>Type</th><th>Scope</th><th>Enabled</th><th>Command</th></tr></thead><tbody>')
            foreach ($item in $sa.Items) {
                $enabledLabel = if ($item.Enabled) { "yes" } else { "no" }
                $cls          = if (-not $item.Enabled) { "row-notice" } else { "" }
                [void]$sections.Append("<tr class='$cls'><td>$([System.Web.HttpUtility]::HtmlEncode($item.Name))</td><td>$($item.Type)</td><td>$($item.Scope)</td><td>$enabledLabel</td><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($item.Command))</td></tr>")
            }
            [void]$sections.Append('</tbody></table></details>')
        }
        [void]$sections.Append('</section>')
    }

    # ── System Repair section ────────────────────────────────────
    if ($Results.ContainsKey("SystemRepair")) {
        $sr = $Results["SystemRepair"]
        [void]$sections.Append('<section><h2>System Repair (SFC + DISM)</h2>')
        if ($sr.Errors -contains "REQUIRES_ADMIN") {
            [void]$sections.Append("<p style='color:#d29922'>Requires admin rights. Run as Administrator to check/repair system files.</p>")
        } else {
            [void]$sections.Append('<table><thead><tr><th>Tool</th><th>Status</th><th>Notes</th></tr></thead><tbody>')
            $sfcCls  = if ($sr.SfcStatus  -match "ISSUES|ERROR|REMAIN") { "row-warn" } else { "" }
            $dismCls = if ($sr.DismStatus -match "ISSUES|ERROR|REPAIRABLE") { "row-warn" } else { "" }
            [void]$sections.Append("<tr class='$sfcCls'><td>SFC</td><td><strong>$($sr.SfcStatus)</strong></td><td>Details in C:\Windows\Logs\CBS\CBS.log</td></tr>")
            [void]$sections.Append("<tr class='$dismCls'><td>DISM</td><td><strong>$($sr.DismStatus)</strong></td><td>Component store integrity</td></tr>")
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Disk Optimize section ────────────────────────────────────
    if ($Results.ContainsKey("DiskOptimize")) {
        $do = $Results["DiskOptimize"]
        [void]$sections.Append('<section><h2>Disk Optimization</h2>')
        if ($do.Items.Count -eq 0) {
            [void]$sections.Append('<p>No fixed volumes found.</p>')
        } else {
            [void]$sections.Append('<table><thead><tr><th>Drive</th><th>Label</th><th>Media</th><th>Action</th><th>Status</th></tr></thead><tbody>')
            foreach ($item in $do.Items) {
                $cls = if ($item.Status -eq "ERROR") { "row-warn" } elseif ($item.Status -eq "REQUIRES_ADMIN") { "row-notice" } else { "" }
                [void]$sections.Append("<tr class='$cls'><td><strong>$($item.DriveLetter):</strong></td><td>$([System.Web.HttpUtility]::HtmlEncode($item.Label))</td><td>$($item.MediaType)</td><td>$($item.Action)</td><td>$($item.Status)</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Windows Update Check section ─────────────────────────────
    if ($Results.ContainsKey("WindowsUpdateCheck")) {
        $wu = $Results["WindowsUpdateCheck"]
        [void]$sections.Append('<section><h2>Windows Update</h2>')
        if ($wu.PendingCount -eq 0 -and $wu.Errors.Count -eq 0) {
            [void]$sections.Append("<p style='color:#3fb950'><strong>System is up to date.</strong></p>")
        } else {
            if ($wu.PendingCount -gt 0) {
                [void]$sections.Append("<p style='color:#d29922'><strong>$($wu.PendingCount) updates pending</strong></p>")
            }
            if ($wu.Triggered) {
                [void]$sections.Append("<p style='color:#8b949e'>Update process triggered in background &mdash; check Windows Update for progress.</p>")
            }
            if ($wu.Items.Count -gt 0) {
                [void]$sections.Append('<details><summary>Show pending updates</summary><table><thead><tr><th>Title</th><th>Severity</th><th>Size</th></tr></thead><tbody>')
                foreach ($item in $wu.Items) {
                    $cls = if ($item.Severity -eq "Critical") { "row-critical" } elseif ($item.Severity -eq "Important") { "row-warn" } else { "" }
                    [void]$sections.Append("<tr class='$cls'><td>$([System.Web.HttpUtility]::HtmlEncode($item.Title))</td><td>$($item.Severity)</td><td>$($item.SizeMB) MB</td></tr>")
                }
                [void]$sections.Append('</tbody></table></details>')
            }
            foreach ($err in $wu.Errors) {
                [void]$sections.Append("<p style='color:#f85149'>$([System.Web.HttpUtility]::HtmlEncode($err))</p>")
            }
        }
        [void]$sections.Append('</section>')
    }

    # ── Duplicate Finder section ─────────────────────────────────
    if ($Results.ContainsKey("DuplicateFinder")) {
        $df = $Results["DuplicateFinder"]
        [void]$sections.Append("<section><h2>Duplicate Files</h2>")
        [void]$sections.Append("<p>Scanned <strong>$($df.FilesScanned)</strong> files &mdash; found <strong>$($df.DuplicateSets)</strong> duplicate sets wasting <strong>$([math]::Round($df.WastedBytes/1MB,1)) MB</strong></p>")
        if ($df.Items.Count -gt 0) {
            [void]$sections.Append('<table><thead><tr><th>Hash (prefix)</th><th>Copies</th><th>Size</th><th>Wasted</th><th>Paths</th></tr></thead><tbody>')
            foreach ($item in ($df.Items | Select-Object -First 50)) {
                $pathLines = ($item.Paths -split "`n" | ForEach-Object { "<div>$([System.Web.HttpUtility]::HtmlEncode($_))</div>" }) -join ""
                [void]$sections.Append("<tr><td><code>$($item.Hash.Substring(0,12))…</code></td><td>$($item.Count)</td><td>$(_HumanBytes $item.SizeBytes)</td><td>$($item.WastedMB) MB</td><td class='path'>$pathLines</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Software Audit section ────────────────────────────────────
    if ($Results.ContainsKey("SoftwareAudit")) {
        $sa = $Results["SoftwareAudit"]
        [void]$sections.Append("<section><h2>Recently Installed Software (last $($sa.LastDays) days)</h2>")
        if ($sa.Items.Count -eq 0) {
            [void]$sections.Append("<p>No software installed in this period.</p>")
        } else {
            [void]$sections.Append("<p><strong>$($sa.Items.Count)</strong> program(s) installed.</p>")
            [void]$sections.Append('<table><thead><tr><th>Name</th><th>Publisher</th><th>Version</th><th>Date</th><th>Size</th></tr></thead><tbody>')
            foreach ($item in $sa.Items) {
                $dateFmt = if ($item.InstallDate) { try { ([datetime]$item.InstallDate).ToString("yyyy-MM-dd") } catch { $item.InstallDate } } else { "" }
                $sizeFmt = if ($item.SizeBytes -gt 0) { _HumanBytes $item.SizeBytes } else { "" }
                [void]$sections.Append("<tr><td>$([System.Web.HttpUtility]::HtmlEncode($item.Name))</td><td>$([System.Web.HttpUtility]::HtmlEncode($item.Publisher))</td><td>$([System.Web.HttpUtility]::HtmlEncode($item.Version))</td><td>$dateFmt</td><td>$sizeFmt</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Dev Project Cleanup section ────────────────────────────────
    if ($Results.ContainsKey("DevProjectClean")) {
        $dc = $Results["DevProjectClean"]
        [void]$sections.Append("<section><h2>Dev Project Cleanup</h2>")
        if ($dc.Projects.Count -eq 0) {
            [void]$sections.Append("<p>No projects found. Set <code>dev_cleanup.scan_paths</code> in config.json.</p>")
        } else {
            $totalHeavy = ($dc.Projects | Measure-Object -Property HeavyBytes -Sum).Sum
            $due        = @($dc.Projects | Where-Object { $_.IsDue })
            $modeNote   = if ($dc.DryRun) { " (dry-run)" } else { " (LIVE)" }
            [void]$sections.Append("<p><strong>$($dc.Projects.Count)</strong> project(s)$modeNote &mdash; <strong>$($due.Count)</strong> due &mdash; recoverable: <strong>$(_HumanBytes $totalHeavy)</strong></p>")
            [void]$sections.Append('<table><thead><tr><th>Project</th><th>Last modified</th><th>Heavy folders</th><th>Size</th><th>Status</th></tr></thead><tbody>')
            foreach ($proj in $dc.Projects) {
                $lastFmt  = if ($proj.LastWrite) { try { ([datetime]$proj.LastWrite).ToString("yyyy-MM-dd") } catch { "" } } else { "" }
                $folders  = ($proj.Folders | ForEach-Object { $_.Name }) -join ", "
                $cls      = if ($proj.IsDue) { "row-notice" } else { "" }
                $status   = if (-not $proj.IsDue) { "up to date" } elseif ($dc.DryRun) { "pending" } else { "cleaned" }
                [void]$sections.Append("<tr class='$cls'><td class='path'>$([System.Web.HttpUtility]::HtmlEncode($proj.Path))</td><td>$lastFmt</td><td>$([System.Web.HttpUtility]::HtmlEncode($folders))</td><td>$(_HumanBytes $proj.HeavyBytes)</td><td>$status</td></tr>")
            }
            [void]$sections.Append('</tbody></table>')
        }
        [void]$sections.Append('</section>')
    }

    # ── Windows Update Cache section ──────────────────────────────
    if ($Results.ContainsKey("WindowsUpdateCache")) {
        $wc = $Results["WindowsUpdateCache"]
        [void]$sections.Append('<section><h2>Windows Update Cache</h2>')
        if ($wc.Errors -contains "REQUIRES_ADMIN") {
            [void]$sections.Append("<p style='color:#d29922'>Requires admin rights to clean.</p>")
        } elseif ($wc.Items.Count -gt 0) {
            $item = $wc.Items[0]
            if ($wc.BytesFreed -gt 0) {
                [void]$sections.Append("<p style='color:#3fb950'>Freed <strong>$(_HumanBytes $wc.BytesFreed)</strong> from Windows Update cache.</p>")
            } else {
                [void]$sections.Append("<p>Cache size: <strong>$(_HumanBytes $item.SizeBytes)</strong> ($($item.FileCount) files) — run LIVE as admin to clean.</p>")
            }
        } else {
            [void]$sections.Append("<p>Cache is empty or not accessible.</p>")
        }
        foreach ($err in $wc.Errors) {
            if ($err -ne "REQUIRES_ADMIN") {
                [void]$sections.Append("<p style='color:#f85149'>$([System.Web.HttpUtility]::HtmlEncode($err))</p>")
            }
        }
        [void]$sections.Append('</section>')
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Scrub Report — $runDate</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, -apple-system, sans-serif; background: #0f1117; color: #c9d1d9; font-size: 14px; }
  header { background: #161b22; border-bottom: 1px solid #30363d; padding: 20px 32px; display: flex; align-items: center; gap: 16px; }
  header h1 { font-size: 20px; font-weight: 600; }
  .badge { font-size: 11px; font-weight: 700; border-radius: 4px; padding: 3px 8px; letter-spacing: .05em; }
  .badge-dryrun { background: #264f78; color: #79c0ff; }
  .badge-live   { background: #3d1f00; color: #ffa657; }
  .score-badge  { font-size: 14px; font-weight: 700; margin-left: 8px; }
  .meta { font-size: 12px; color: #8b949e; margin-left: auto; }
  main { max-width: 1200px; margin: 0 auto; padding: 24px 32px; }
  section { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 20px; padding: 20px 24px; }
  section h2 { font-size: 15px; font-weight: 600; margin-bottom: 14px; color: #e6edf3; border-bottom: 1px solid #21262d; padding-bottom: 10px; }
  section p { margin-bottom: 10px; color: #8b949e; }
  section p strong { color: #c9d1d9; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th { text-align: left; padding: 8px 10px; color: #8b949e; font-weight: 500; border-bottom: 1px solid #21262d; }
  td { padding: 6px 10px; border-bottom: 1px solid #161b22; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  tr:hover td { background: #1c2128; }
  .path { font-family: monospace; font-size: 11px; word-break: break-all; color: #8b949e; }
  .row-warn td    { background: #2d1f00; }
  .row-notice td  { background: #1b2635; }
  .row-critical td { background: #3d0000; }
  details { margin-top: 10px; }
  summary { cursor: pointer; color: #58a6ff; font-size: 13px; padding: 4px 0; }
  summary:hover { color: #79c0ff; }
  code { background: #21262d; padding: 2px 6px; border-radius: 4px; font-size: 12px; }
</style>
</head>
<body>
<header>
  <h1>Scrub</h1>
  <span class="badge $modeBadge">$modeLabel</span>
  $(if ($Results -and $Results.ContainsKey("HealthScore")) {
    $hs = $Results["HealthScore"]
    $scoreColor = if ($hs.Score -ge 80) { "#3fb950" } elseif ($hs.Score -ge 50) { "#d29922" } else { "#f85149" }
    "<span class='score-badge' style='color:$scoreColor'>Score: $($hs.Score)</span>"
  })
  <span class="meta">$runDate</span>
</header>
<main>
$($sections.ToString())
</main>
</body>
</html>
"@

    $html | Set-Content -Path $ReportPath -Encoding UTF8
    Write-Host "  Report saved: $ReportPath" -ForegroundColor DarkGray
}

function Save-ScrubJson {
    param([object] $Results, [string] $ReportDir, [bool] $DryRun, [string] $ModuleRoot)
    try {
        $timestamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
        $version   = (Import-PowerShellDataFile (Join-Path $ModuleRoot 'scrub.psd1')).ModuleVersion
        $out = [ordered]@{
            timestamp = (Get-Date -Format "o")
            dry_run   = $DryRun
            version   = $version
            modules   = [ordered]@{}
        }
        foreach ($key in $Results.Keys) {
            $mod = $Results[$key]
            $entry = [ordered]@{}
            if ($mod.PSObject.Properties["BytesFreed"])   { $entry["BytesFreed"]   = $mod.BytesFreed }
            if ($mod.PSObject.Properties["FilesDeleted"]) { $entry["FilesDeleted"] = $mod.FilesDeleted }
            if ($mod.PSObject.Properties["Errors"])       { $entry["Errors"]       = @($mod.Errors) }
            if ($mod.PSObject.Properties["Items"] -and $null -ne $mod.Items) {
                $entry["ItemsCount"] = $mod.Items.Count
                if ($mod.Items.Count -le 20) { $entry["Items"] = $mod.Items }
            }
            $out.modules[$key] = $entry
        }
        $jsonPath = Join-Path $ReportDir "scrub-$timestamp.json"
        $out | ConvertTo-Json -Depth 5 | Set-Content $jsonPath -Encoding UTF8
    } catch {}
}

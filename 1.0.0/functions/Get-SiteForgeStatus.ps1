function Get-SiteForgeStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n🧭 Gathering SiteForge status..." -ForegroundColor Cyan

    $status = [ordered]@{}

    # ───── Basic System Info ─────
    $status['Hostname']    = (hostname)
    $status['OS']          = (lsb_release -ds 2>$null) -replace '"'
    $status['Uptime']      = (uptime -p) -replace '^up ', ''
    $status['Date & Time'] = (date)
    $status['PowerShell']  = $PSVersionTable.PSVersion.ToString()

    # ───── NGINX Info ─────
    try {
        $nginxVersion = (nginx -v 2>&1) -replace 'nginx version: ', ''
        $status['NGINX Version'] = $nginxVersion
        $status['NGINX Status']  = (sudo systemctl is-active nginx)
    } catch {
        $status['NGINX Version'] = "Not installed"
        $status['NGINX Status']  = "N/A"
    }

    # ───── Git Info ─────
    try {
        $status['Git Version'] = (git --version) -replace 'git version ', ''
    } catch {
        $status['Git Version'] = "Not installed"
    }

    # --- SSL certificate existence ---
    try {
        if ($webDomain) {
            $sslDomain = $webDomain
        } else {
            $nginxConf = Get-ChildItem /etc/nginx/sites-available -File | Select-Object -First 1
            $sslDomain = if ($nginxConf) { $nginxConf.BaseName } else { (hostname) }
        }
    
        $sslPath = "/etc/letsencrypt/live/$sslDomain/fullchain.pem"
        if (Test-Path $sslPath) {
            $file = Get-Item $sslPath
            $kbSize = [math]::Round($file.Length / 1KB, 1)
            if ($kbSize -lt 1) { $sizeText = "<1 KB" } else { $sizeText = "$kbSize KB" }
            $status['SSL Certificate'] = "Detected for $sslDomain ($sizeText, modified $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
        } else {
            $status['SSL Certificate'] = "Missing at /etc/letsencrypt/live/$sslDomain/"
        }
    } catch {
        $status['SSL Certificate'] = "Error checking SSL certificate"
    }

    # ───── Web Root Info ─────
    if (Test-Path "/var/www/html") {
        $webFiles = (Get-ChildItem /var/www/html -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        $status['Web Root'] = "/var/www/html ($webFiles files)"
    } else {
        $status['Web Root'] = "Missing"
    }

    # ───── Git Repo Info ─────
    if ($gitRepo) {
        $status['Git Repo'] = $gitRepo
    } else {
        $status['Git Repo'] = "Not configured (`$gitRepo missing in profile)"
    }

    # ───── Firewall Info ─────
    try {
        if (Get-Command ufw -ErrorAction SilentlyContinue) {
            $ufwOutput = (sudo ufw status | Out-String)
            if ($ufwOutput -match "Status: active") {
                $ports = ($ufwOutput -split "`n" | Where-Object {$_ -match "ALLOW"}) -replace '\s+ALLOW.*',''
                $ports = ($ports | Where-Object {$_ -ne ""}) -join ', '
                if (-not $ports) { $ports = "custom rules" }
                $status['Firewall'] = "active ($ports)"
            } else {
                $status['Firewall'] = "inactive"
            }
        } else {
            $status['Firewall'] = "not installed"
        }
    } catch {
        $status['Firewall'] = "Error checking firewall"
    }

    # ───── Fail2Ban Info ─────
    try {
        if (Get-Command fail2ban-client -ErrorAction SilentlyContinue) {
            $summary = (sudo fail2ban-client status 2>&1)
            if ($summary -match "Jail list:") {
                $jailList = ($summary -split "Jail list:")[1].Trim() -split ",\s*"
                $jailCount = ($jailList | Where-Object { $_ -ne "" }).Count
                $totalBanned = 0
                foreach ($j in $jailList) {
                    if ($j.Trim()) {
                        $banned = ((sudo fail2ban-client status $j.Trim() | Select-String "Currently banned:").ToString().Split(":")[-1].Trim())
                        if ([int]::TryParse($banned, [ref]$null)) { $totalBanned += [int]$banned }
                    }
                }
                $status['Fail2Ban'] = "active ($jailCount jails, $totalBanned banned)"
            }
            elseif ((sudo systemctl is-active fail2ban) -eq 'active') {
                $status['Fail2Ban'] = "active (no jails)"
            }
            else {
                $status['Fail2Ban'] = "installed but inactive"
            }
        } else {
            $status['Fail2Ban'] = "not installed"
        }
    } catch {
        $status['Fail2Ban'] = "Error checking Fail2Ban"
    }

    # ───── Output ─────
    Write-Host "`n🧩 SITEFORGE STATUS" -ForegroundColor Green
    Write-Host "───────────────────────────────"
    foreach ($key in $status.Keys) {
        Write-Host ("{0,-18} : {1}" -f $key, $status[$key])
    }
    Write-Host "───────────────────────────────"
    Write-Host "`n💡 Tip: Run 'Update-Website' to redeploy your latest version."
}


function Get-SiteForgeStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n🧭 Gathering SiteForge status..." -ForegroundColor Cyan

    if (Test-Path $PROFILE) { . $PROFILE }

    $status = [ordered]@{}

    # --- Basic system info ---
    $status['Hostname']       = (hostname)
    $status['OS']             = (lsb_release -ds 2>$null) -replace '"'
    $status['Uptime']         = (uptime -p) -replace '^up ', ''
    $status['Date & Time']    = (date)
    $status['PowerShell']     = $PSVersionTable.PSVersion.ToString()

    # --- NGINX info ---
    try {
        $status['NGINX Version'] = ((nginx -v 2>&1) -replace 'nginx version: ', '')
        $status['NGINX Status']  = (sudo systemctl is-active nginx)
    } catch {
        $status['NGINX Version'] = "Not installed"
        $status['NGINX Status']  = "N/A"
    }

    # --- Git info ---
    try {
        $status['Git Version'] = ((git --version) -replace 'git version ', '')
    } catch {
        $status['Git Version'] = "Not installed"
    }

    # --- Detect active domain ---
    $sslDomain = $null
    if ($webDomain) {
        $sslDomain = $webDomain
    } else {
        # Try to find from NGINX config file contents
        $conf = Get-ChildItem /etc/nginx/sites-available -File | Where-Object {
            (Select-String -Path $_.FullName -Pattern 'server_name' -Quiet)
        } | Select-Object -First 1
        if ($conf) {
            $serverNameLine = (Select-String -Path $conf.FullName -Pattern 'server_name').Line
            $sslDomain = ($serverNameLine -split '\s+')[1] -replace ';',''
        }
    }

    # --- SSL certificate existence ---
    if ($sslDomain) {
        $sslPath = "/etc/letsencrypt/live/$sslDomain/fullchain.pem"
        if (Test-Path $sslPath) {
            $file = Get-Item $sslPath
            $kbSize = [math]::Round($file.Length / 1KB, 1)
            if ($kbSize -lt 1) { $sizeText = "<1 KB" } else { $sizeText = "$kbSize KB" }
            $status['SSL Certificate'] = "Detected for $sslDomain ($sizeText, modified $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"

        } else {
            $status['SSL Certificate'] = "Missing at /etc/letsencrypt/live/$sslDomain/"
        }
    } else {
        $status['SSL Certificate'] = "No domain found in NGINX configs"
    }

    # --- Web root info ---
    if (Test-Path "/var/www/html") {
        $webFiles = (Get-ChildItem /var/www/html -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        $status['Web Root'] = "/var/www/html ($webFiles files)"
    } else {
        $status['Web Root'] = "Missing"
    }

    # --- Repo info ---
    if ($gitRepo) {
        $status['Git Repo'] = $gitRepo
    } else {
        $status['Git Repo'] = "Not configured (`$gitRepo missing in profile)"
    }

    # --- Display summary ---
    Write-Host "`n🧩 SITEFORGE STATUS" -ForegroundColor Green
    Write-Host "───────────────────────────────"
    foreach ($key in $status.Keys) {
        Write-Host ("{0,-18} : {1}" -f $key, $status[$key])
    }
    Write-Host "───────────────────────────────"
    Write-Host "`n💡 Tip: Run 'update-website' to redeploy your latest version."
}

function Get-SiteForgeStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n🧭 Gathering SiteForge status..." -ForegroundColor Cyan

    # Initialize info container
    $status = [ordered]@{}

    # Basic system info
    $status['Hostname']       = (hostname)
    $status['OS']             = (lsb_release -ds 2>$null) -replace '"'
    $status['Uptime']         = (uptime -p) -replace '^up ', ''
    $status['Date & Time']    = (date)

    # PowerShell info
    $status['PowerShell']     = $PSVersionTable.PSVersion.ToString()

    # NGINX info
    try {
        $nginxVersion = (nginx -v 2>&1) -replace 'nginx version: ', ''
        $status['NGINX Version'] = $nginxVersion
        $status['NGINX Status'] = (sudo systemctl is-active nginx)
    } catch {
        $status['NGINX Version'] = "Not installed"
        $status['NGINX Status']  = "N/A"
    }

    # Git info
    try {
        $gitVersion = (git --version) -replace 'git version ', ''
        $status['Git Version'] = $gitVersion
    } catch {
        $status['Git Version'] = "Not installed"
    }

    # SSL certificate info (if exists)
    $domainConf = Get-ChildItem /etc/nginx/sites-available -File | Select-Object -First 1
    if ($domainConf) {
        $domainName = $domainConf.BaseName
        $sslCertPath = "/etc/letsencrypt/live/$domainName/fullchain.pem"
        if (Test-Path $sslCertPath) {
            $certInfo = openssl x509 -in $sslCertPath -noout -dates 2>$null
            $notAfter = ($certInfo | Select-String 'notAfter=').ToString().Split('=')[-1]
            $status['SSL Certificate'] = "Valid until $notAfter"
        } else {
            $status['SSL Certificate'] = "Not found"
        }
    } else {
        $status['SSL Certificate'] = "No domain config detected"
    }

    # Web root info
    if (Test-Path "/var/www/html") {
        $webFiles = (Get-ChildItem /var/www/html -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        $status['Web Root'] = "/var/www/html ($webFiles files)"
    } else {
        $status['Web Root'] = "Missing"
    }

    # Repo info
    if ($gitRepo) {
        $status['Git Repo'] = $gitRepo
    } else {
        $status['Git Repo'] = "Not configured (`$gitRepo missing in profile)"
    }

    # Print results
    Write-Host "`n🧩 SITEFORGE STATUS" -ForegroundColor Green
    Write-Host "───────────────────────────────"
    foreach ($key in $status.Keys) {
        Write-Host ("{0,-18} : {1}" -f $key, $status[$key])
    }

    Write-Host "───────────────────────────────"
    Write-Host "`n💡 Tip: Run 'update-website' to redeploy your latest version."
}

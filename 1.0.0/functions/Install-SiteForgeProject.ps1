function Install-SiteForgeProject {
    <#
    .SYNOPSIS
        Fully automates deployment of a new website on Ubuntu using PowerShell + NGINX.
        Handles installs, SSL, firewall, Fail2Ban, and SSH (if needed).

    .EXAMPLE
        Install-SiteForgeProject -Domain "example.com" -Repo "git@github.com:Unit-259/example.git" -Email "me@example.com" -UseSSH -EnableFirewall -EnableFail2Ban -AutoDNSCheck -SkipPrompts
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [string]$Domain,
        [Parameter(Mandatory = $false)] [string]$Repo,
        [Parameter(Mandatory = $false)] [string]$Email,
        [switch]$ForceReinstall,
        [switch]$UseSSH,
        [switch]$EnableFirewall,
        [switch]$EnableFail2Ban,
        [switch]$SkipPrompts,
        [switch]$AutoDNSCheck
    )

    # Silence file copy progress
    $oldPref = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    Write-Host "`n🚀 Launching SiteForge Project Installer..." -ForegroundColor Cyan

    # --- Step 0: Collect inputs ---
    if (-not $Domain -and -not $SkipPrompts) { $Domain = Read-Host "Enter your primary domain (e.g. example.com)" }
    if (-not $Repo -and -not $SkipPrompts)   { $Repo   = Read-Host "Enter your Git repository URL (HTTPS or SSH)" }
    if (-not $Email -and -not $SkipPrompts)  { $Email  = Read-Host "Enter your contact email for SSL + SSH key" }

    if (-not $Domain -or -not $Repo -or -not $Email) {
        Write-Host "❌ Missing required parameters. Use -SkipPrompts for unattended mode." -ForegroundColor Red
        $ProgressPreference = $oldPref
        return
    }

    if ($UseSSH -or -not $SkipPrompts) {
        if (-not $UseSSH) {
            $privateRepo = Read-Host "Is this a PRIVATE repository that requires SSH? (y/N)"
            $UseSSH = $privateRepo.Trim().ToLower() -in @('y','yes')
        }
    } else {
        $UseSSH = $false
    }

    # --- Step 0.5: DNS validation ---
    if ($AutoDNSCheck) {
        Write-Host "`n🌍 Auto DNS check enabled — verifying $Domain..." -ForegroundColor Cyan
        for ($i = 1; $i -le 10; $i++) {
            Write-Host "🔎 Attempt $i/10..." -ForegroundColor Gray
            if (Test-SiteForgeDNS -Domain $Domain) {
                Write-Host "✅ DNS successfully resolves to this server!" -ForegroundColor Green
                break
            } else {
                if ($i -lt 10) {
                    Write-Host "⚠️  DNS not ready yet — retrying in 30 seconds..." -ForegroundColor Yellow
                    Start-Sleep -Seconds 30
                } else {
                    Write-Host "❌ DNS still not pointing to this server after 10 attempts. Exiting." -ForegroundColor Red
                    $ProgressPreference = $oldPref
                    return
                }
            }
        }
    } else {
        if (-not (Test-SiteForgeDNS -Domain $Domain)) {
            Write-Host "`n⚠️  DNS is not yet pointing to this server." -ForegroundColor Yellow
            Write-Host "   Please update your A record to this server's IP and rerun Install-SiteForgeProject." -ForegroundColor DarkGray
            $ProgressPreference = $oldPref
            return
        }
    }

    # --- Step 1: Force reinstall logic ---
    if ($ForceReinstall) {
        Write-Host "`n⚠️  Force reinstall mode activated for $Domain" -ForegroundColor Yellow
        if (-not $SkipPrompts) {
            $confirm = Read-Host "This will delete NGINX config, SSL certs, site files, and SiteForge vars. Proceed? (y/N)"
            if ($confirm.Trim().ToLower() -notin @('y','yes')) {
                Write-Host "❌ Operation cancelled."
                $ProgressPreference = $oldPref
                return
            }
        }

        Write-Host "`n🧹 Cleaning up old configuration..." -ForegroundColor Yellow
        try {
            sudo systemctl stop nginx *> $null 2>&1
            sudo rm -f "/etc/nginx/sites-available/$Domain" "/etc/nginx/sites-enabled/$Domain" *> $null 2>&1
            sudo rm -rf "/etc/letsencrypt/live/$Domain" "/etc/letsencrypt/renewal/$Domain.conf" "/var/www/html/*" *> $null 2>&1

            if (Test-Path $PROFILE) {
                (Get-Content $PROFILE) |
                    Where-Object { $_ -notmatch 'SiteForge Variables' -and $_ -notmatch '\$gitRepo|\$webDomain|\$emailAddr' } |
                    Set-Content $PROFILE
            }

            if (-not $SkipPrompts) {
                $sshConfirm = Read-Host "Do you also want to delete your SSH key (~/.ssh/id_ed25519)? (y/N)"
                if ($sshConfirm.Trim().ToLower() -in @('y','yes')) {
                    sudo rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub *> $null 2>&1
                    Write-Host "🗝️  SSH keys deleted."
                }
            }

            sudo systemctl start nginx *> $null 2>&1
            Write-Host "✅ Reinstall cleanup complete."
        } catch {
            Write-Host "⚠️  Cleanup encountered an error: $_" -ForegroundColor Red
        }
    }

    # --- Step 2: Install dependencies ---
    Write-Host "`n📦 Installing required packages..." -ForegroundColor Yellow
    sudo apt-get update -y *> $null 2>&1
    sudo apt-get upgrade -y *> $null 2>&1
    sudo apt-get install -y nginx git curl software-properties-common certbot python3-certbot-nginx *> $null 2>&1

    # --- Step 3: Optional SSH key generation ---
    if ($UseSSH) {
        if (-not (Test-Path -Path ~/.ssh/id_ed25519)) {
            Write-Host "`n🔑 Generating new SSH key..."
            ssh-keygen -t ed25519 -C $Email *> $null 2>&1
            Write-Host "`n📋 Public SSH key (add to GitHub Deploy Keys):" -ForegroundColor Yellow
            cat ~/.ssh/id_ed25519.pub
            Read-Host "`nPress Enter once you've added the key to GitHub"
        } else {
            Write-Host "✅ SSH key already exists — skipping generation."
        }
    } else {
        Write-Host "🔓 Skipping SSH key generation (public repo)."
    }

    # --- Step 3.5: Optional Security Hardening ---
    if ($EnableFirewall -or (-not $SkipPrompts -and (Read-Host "Would you like to enable and lock down the firewall to ports 22, 80, and 443? (Y/n)") -notin @('n','no'))) {
        Write-Host "`n🛡️  Enabling firewall..." -ForegroundColor Yellow
        Enable-Firewall *> $null 2>&1
    }

    if ($EnableFail2Ban -or (-not $SkipPrompts -and (Read-Host "Would you like to install and enable Fail2Ban for brute-force protection? (Y/n)") -notin @('n','no'))) {
        Write-Host "`n🚨 Installing Fail2Ban..." -ForegroundColor Yellow
        Enable-Fail2Ban *> $null 2>&1
    }

    # --- Step 4: Ensure PowerShell profile exists ---
    if (-not (Test-Path -Path $PROFILE)) {
        Write-Host "Creating PowerShell profile..."
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path -Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force *> $null 2>&1 }
        New-Item -ItemType File -Path $PROFILE -Force *> $null 2>&1
    }

    # --- Step 5: Persist variables + helper functions ---
    $varsBlock = @"
# SiteForge Variables
`$gitRepo   = '$Repo'
`$webDomain = '$Domain'
`$emailAddr = '$Email'
Import-Module SiteForge -Force
"@

    $helpers = @'
# --- SiteForge Helper Functions ---
function errorLogs     { sudo tail -f /var/log/nginx/error.log }
function nginxConfig   { sudo nano "/etc/nginx/sites-available/$webDomain" }
function catnginxConfig{ sudo cat "/etc/nginx/sites-available/$webDomain" }
function restartNginx  { sudo nginx -t && sudo systemctl reload nginx }
'@

    $content = Get-Content $PROFILE -Raw
    $content = $content -replace '(?s)# SiteForge Variables.*?(?=# ---|$)', ''
    $content += "`n$varsBlock`n$helpers"
    Set-Content -Path $PROFILE -Value $content
    Start-Sleep -Seconds 1
    . $PROFILE

    # --- Step 7: Deploy initial site ---
    Write-Host "`n🌍 Deploying website for $Domain..." -ForegroundColor Cyan
    $webRoot = "/var/www/html"
    sudo mkdir -p $webRoot *> $null 2>&1
    cd /root/
    git clone $Repo tempdir *> $null 2>&1

    if (Test-Path "./tempdir/html") {
        Get-ChildItem "./tempdir/html" -Recurse | Move-Item -Destination $webRoot -Force
    } else {
        Get-ChildItem "./tempdir" -Recurse -Exclude '.git','README.md' | Move-Item -Destination $webRoot -Force
    }
    Remove-Item -Recurse -Force ./tempdir *> $null 2>&1

    # --- Step 8: Create NGINX config ---
    $configPath = "/etc/nginx/sites-available/$Domain"
    if (-not (Test-Path $configPath)) {
        Write-Host "`n⚙️  Creating NGINX configuration..." -ForegroundColor Yellow
        $nginxConfig = @'
server {
    listen 80;
    server_name DOMAIN_PLACEHOLDER www.DOMAIN_PLACEHOLDER;
    root /var/www/html;
    index index.html index.htm index.php;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
'@ -replace 'DOMAIN_PLACEHOLDER', $Domain
        $nginxConfig | sudo tee $configPath > $null
        sudo ln -sf $configPath "/etc/nginx/sites-enabled/$Domain" *> $null 2>&1
    }

    # --- Step 9: Obtain SSL cert ---
    Write-Host "`n🔐 Requesting Let's Encrypt SSL certificate..." -ForegroundColor Yellow
    sudo nginx -t *> $null 2>&1
    sudo certbot --nginx --non-interactive --agree-tos --email $Email -d $Domain -d "www.$Domain" *> $null 2>&1

    # --- Step 10: Reload NGINX ---
    sudo nginx -t *> $null 2>&1
    sudo systemctl reload nginx *> $null 2>&1

    # --- Step 11: Success summary ---
    Write-Host "`n✅ SiteForge setup complete!" -ForegroundColor Green
    Write-Host "🌐 Website: https://$Domain"
    Write-Host "📂 Web root: /var/www/html"
    Write-Host "🧩 Config: /etc/nginx/sites-available/$Domain"
    Write-Host "💾 Repo: $Repo"
    Write-Host "`nRun 'update-Website' anytime to redeploy from Git." -ForegroundColor Cyan

    # --- Step 12: Reload profile & status ---
    Write-Host "`n🔄 Reloading PowerShell profile..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    & pwsh -NoLogo -Command ". $PROFILE; Get-SiteForgeStatus"

    # Restore preference and exit
    $ProgressPreference = $oldPref
    exit
}

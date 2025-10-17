function Install-SiteForgeProject {
    <#
    .SYNOPSIS
        Fully automates deployment of a new website on Ubuntu using PowerShell + NGINX.
        Handles installs, SSL, firewall, Fail2Ban, and SSH (if needed).

    .DESCRIPTION
        Run once to install and configure your webserver, deploy your repo, request SSL,
        and permanently save configuration variables in your PowerShell profile.
        Optionally pass -ForceReinstall to wipe and rebuild everything from scratch.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] [string]$Domain,
        [Parameter(Mandatory = $false)] [string]$Repo,
        [Parameter(Mandatory = $false)] [string]$Email,
        [switch]$ForceReinstall
    )

    Write-Host "`n🚀 Launching SiteForge Project Installer..." -ForegroundColor Cyan

    # --- Step 0: Collect inputs ---
    if (-not $Domain) { $Domain = Read-Host "Enter your primary domain (e.g. example.com)" }
    if (-not $Repo)   { $Repo   = Read-Host "Enter your Git repository URL (HTTPS or SSH)" }
    if (-not $Email)  { $Email  = Read-Host "Enter your contact email for SSL + SSH key" }

    $privateRepo = Read-Host "Is this a PRIVATE repository that requires SSH? (y/N)"
    $privateRepo = $privateRepo.Trim().ToLower() -in @('y','yes')

    # --- Step 0.5: DNS validation ---
    if (-not (Test-SiteForgeDNS -Domain $Domain)) {
        Write-Host "`n⚠️  DNS is not yet pointing to this server." -ForegroundColor Yellow
        Write-Host "   Please update your A record to this server's IP and rerun Install-SiteForgeProject." -ForegroundColor DarkGray
        return
    }

    # --- Step 1: Force reinstall logic ---
    if ($ForceReinstall) {
        Write-Host "`n⚠️  Force reinstall mode activated for $Domain" -ForegroundColor Yellow
        $confirm = Read-Host "This will delete NGINX config, SSL certs, site files, and SiteForge vars. Proceed? (y/N)"
        if ($confirm.Trim().ToLower() -notin @('y','yes')) {
            Write-Host "❌ Operation cancelled."
            return
        }

        Write-Host "`n🧹 Cleaning up old configuration..." -ForegroundColor Yellow
        try {
            sudo systemctl stop nginx
            sudo rm -f "/etc/nginx/sites-available/$Domain"
            sudo rm -f "/etc/nginx/sites-enabled/$Domain"
            sudo rm -rf "/etc/letsencrypt/live/$Domain"
            sudo rm -rf "/etc/letsencrypt/renewal/$Domain.conf"
            sudo rm -rf "/var/www/html/*"

            # Remove SiteForge vars from profile
            if (Test-Path $PROFILE) {
                (Get-Content $PROFILE) |
                    Where-Object { $_ -notmatch 'SiteForge Variables' -and $_ -notmatch '\$gitRepo|\$webDomain|\$emailAddr' } |
                    Set-Content $PROFILE
            }

            # Optional SSH cleanup
            $sshConfirm = Read-Host "Do you also want to delete your SSH key (~/.ssh/id_ed25519)? (y/N)"
            if ($sshConfirm.Trim().ToLower() -in @('y','yes')) {
                sudo rm -f ~/.ssh/id_ed25519
                sudo rm -f ~/.ssh/id_ed25519.pub
                Write-Host "🗝️  SSH keys deleted."
            }

            sudo systemctl start nginx
            Write-Host "✅ Reinstall cleanup complete."
        } catch {
            Write-Host "⚠️  Cleanup encountered an error: $_" -ForegroundColor Red
        }
    }

    # --- Step 2: Install dependencies ---
    Write-Host "`n📦 Installing required packages..." -ForegroundColor Yellow
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y nginx git curl software-properties-common

    # --- Step 3: Optional SSH key generation ---
    if ($privateRepo) {
        if (-not (Test-Path -Path ~/.ssh/id_ed25519)) {
            Write-Host "`n🔑 Generating new SSH key..."
            ssh-keygen -t ed25519 -C $Email
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
    $fwChoice = Read-Host "Would you like to enable and lock down the firewall to ports 22, 80, and 443? (Y/n)"
    if ($fwChoice.Trim().ToLower() -notin @('n','no')) {
        Write-Host "`n🛡️  Enabling firewall..." -ForegroundColor Yellow
        Enable-Firewall
    }

    $banChoice = Read-Host "Would you like to install and enable Fail2Ban for brute-force protection? (Y/n)"
    if ($banChoice.Trim().ToLower() -notin @('n','no')) {
        Write-Host "`n🚨 Installing Fail2Ban..." -ForegroundColor Yellow
        Enable-Fail2Ban
    }

    # --- Step 4: Ensure PowerShell profile exists ---
    if (-not (Test-Path -Path $PROFILE)) {
        Write-Host "Creating PowerShell profile..."
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path -Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
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

    # --- Step 6: Reload profile ---
    Write-Host "`n🔄 Reloading PowerShell profile..." -ForegroundColor Yellow
    . $PROFILE

    # --- Step 7: Deploy initial site ---
    Write-Host "`n🌍 Deploying website for $Domain..." -ForegroundColor Cyan
    $webRoot = "/var/www/html"
    sudo mkdir -p $webRoot
    cd /root/
    git clone $Repo tempdir | Out-Host

    if (Test-Path "./tempdir/html") {
        Get-ChildItem "./tempdir/html" -Recurse | Move-Item -Destination $webRoot -Force
    } else {
        Get-ChildItem "./tempdir" -Recurse -Exclude '.git','README.md' | Move-Item -Destination $webRoot -Force
    }
    Remove-Item -Recurse -Force ./tempdir

    # --- Step 8: Create NGINX config ---
    $configPath = "/etc/nginx/sites-available/$Domain"
    if (-not (Test-Path $configPath)) {
        $nginxConfig = @"
server {
    listen 80;
    server_name $Domain www.$Domain;
    root /var/www/html;
    index index.html index.htm index.php;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
"@
        $nginxConfig | sudo tee $configPath > $null
        sudo ln -sf $configPath "/etc/nginx/sites-enabled/$Domain"
    }

    # --- Step 9: Obtain SSL cert ---
    Write-Host "`n🔐 Requesting Let's Encrypt SSL certificate..." -ForegroundColor Yellow
    sudo nginx -t
    sudo certbot --nginx --non-interactive --agree-tos --email $Email -d $Domain -d "www.$Domain"

    # --- Step 10: Reload NGINX ---
    sudo nginx -t
    sudo systemctl reload nginx

    # --- Step 11: Success summary ---
    Write-Host "`n✅ SiteForge setup complete!" -ForegroundColor Green
    Write-Host "🌐 Website: https://$Domain"
    Write-Host "📂 Web root: /var/www/html"
    Write-Host "🧩 Config: /etc/nginx/sites-available/$Domain"
    Write-Host "💾 Repo: $Repo"
    Write-Host "`nRun 'update-Website' anytime to redeploy from Git." -ForegroundColor Cyan

    # --- Step 12: Reload profile & status ---
    . $PROFILE
    Get-SiteForgeStatus
}

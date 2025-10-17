function Install-SiteForgeProject {
    <#
    .SYNOPSIS
        Fully automates deployment of a new website on Ubuntu using PowerShell + NGINX.
        Installs all dependencies, configures SSL, sets up SSH (optional),
        saves config variables to profile, deploys from Git, and activates the site.

    .DESCRIPTION
        This command is designed for a fresh Ubuntu environment running PowerShell.
        It can deploy public or private repos, generate SSL certs, and persist all
        necessary environment details for future management.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [string]$Domain,
        [Parameter(Mandatory=$false)] [string]$Repo,
        [Parameter(Mandatory=$false)] [string]$Email
    )

    Write-Host "`n🚀 Launching SiteForge Project Installer..." -ForegroundColor Cyan

    # --- Step 1: Interactive prompts ---
    if (-not $Domain) { $Domain = Read-Host "Enter your primary domain (e.g. example.com)" }
    if (-not $Repo)   { $Repo   = Read-Host "Enter your Git repository URL (HTTPS or SSH)" }
    if (-not $Email)  { $Email  = Read-Host "Enter your contact email for SSL + SSH key" }

    $privateRepo = Read-Host "Is this a PRIVATE repository that requires SSH? (y/N)"
    $privateRepo = $privateRepo.Trim().ToLower() -in @('y','yes')

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
function update-Website {
    Write-Host "`n🔁 Updating website from $gitRepo..." -ForegroundColor Cyan
    $p = Get-Location
    if (Test-Path "/var/www/html") { sudo rm -rf /var/www/html/* } else { sudo mkdir -p /var/www/html }
    cd /root/
    if (Test-Path "./tempdir") { Remove-Item -Recurse -Force ./tempdir }
    git clone $gitRepo tempdir | Out-Host
    $htmlDir = "./tempdir/html"
    if (Test-Path $htmlDir) {
        Get-ChildItem -Path $htmlDir -Recurse | Move-Item -Destination /var/www/html -Force
    } else {
        Get-ChildItem -Path "./tempdir" -Recurse -Exclude '.git','README.md' | Move-Item -Destination /var/www/html -Force
    }
    Remove-Item -Recurse -Force ./tempdir
    cd $p
    sudo chmod -R 755 /var/www/html
    sudo nginx -t
    sudo systemctl reload nginx
    Write-Host "✅ Website updated successfully." -ForegroundColor Green
}
'@

    # Clean + append new sections
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
        try_files \$uri \$uri/ /index.html;
    }
}
"@
        $nginxConfig | sudo tee $configPath > $null
        sudo ln -sf $configPath "/etc/nginx/sites-enabled/$Domain"
    }

    # --- Step 9: Obtain SSL cert ---
    Write-Host "`n🔐 Requesting Let's Encrypt SSL certificate..." -ForegroundColor Yellow
    sudo certbot --nginx --non-interactive --agree-tos --email $Email -d $Domain -d "www.$Domain"

    # --- Step 10: Reload NGINX ---
    sudo nginx -t
    sudo systemctl reload nginx

    # --- Step 11: Summary banner ---
    Write-Host "`n✅ SiteForge setup complete!" -ForegroundColor Green
    Write-Host "🌐 Website: https://$Domain"
    Write-Host "📂 Web root: /var/www/html"
    Write-Host "🧩 Config: /etc/nginx/sites-available/$Domain"
    Write-Host "💾 Repo: $Repo"
    Write-Host "`nRun 'update-Website' anytime to redeploy from Git." -ForegroundColor Cyan
}

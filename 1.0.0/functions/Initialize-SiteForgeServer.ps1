function Initialize-SiteForgeServer {
    <#
    .SYNOPSIS
        Bootstraps a fresh Ubuntu/PowerShell web server for SiteForge.
        Installs NGINX, Certbot, Git, sets up SSH keys, saves configuration
        variables to the PowerShell profile, and reloads the profile so that
        all SiteForge functions are available immediately.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Email,
        [Parameter(Mandatory = $false)]
        [string]$Domain,
        [Parameter(Mandatory = $false)]
        [string]$Repo
    )

    Write-Host "`n🔧 Initializing SiteForge Server..." -ForegroundColor Cyan

    # --- Interactive prompts if missing ---
    if (-not $Email)  { $Email  = Read-Host "Enter your contact email for SSL + SSH key" }
    if (-not $Domain) { $Domain = Read-Host "Enter your primary domain (e.g. example.com)" }
    if (-not $Repo)   { $Repo   = Read-Host "Enter your website Git repository URL" }

    # --- Install prerequisites ---
    Write-Host "`n📦 Installing required packages..." -ForegroundColor Yellow
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y nginx git curl software-properties-common

    # --- Install Certbot if needed ---
    if (-not (Get-Command certbot -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Certbot..."
        sudo apt-get install -y certbot python3-certbot-nginx
    }

    # --- Generate SSH key if missing ---
    if (-not (Test-Path -Path ~/.ssh/id_ed25519)) {
        Write-Host "`n🔑 Generating new SSH key..."
        ssh-keygen -t ed25519 -C $Email
        Write-Host "`n📋 Public SSH key (add this as a GitHub deploy key):" -ForegroundColor Yellow
        cat ~/.ssh/id_ed25519.pub
        Read-Host "`nPress Enter once you've added the key to GitHub"
    } else {
        Write-Host "✅ SSH key already exists — skipping generation."
    }

    # --- Ensure PowerShell profile exists ---
    if (-not (Test-Path -Path $PROFILE)) {
        Write-Host "Creating PowerShell profile..."
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path -Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }

    # --- Inject variables and helpers into the profile ---
    $varsBlock = @"
# SiteForge Variables
`$gitRepo   = '$Repo'
`$webDomain = '$Domain'
`$emailAddr = '$Email'
Import-Module SiteForge -Force
"@

    $helperBlock = @'
# --- SiteForge Helper Functions ---
function errorLogs     { sudo tail -f /var/log/nginx/error.log }
function nginxConfig   { sudo nano "/etc/nginx/sites-available/$webDomain" }
function catnginxConfig{ sudo cat "/etc/nginx/sites-available/$webDomain" }
function restartNginx  { sudo nginx -t && sudo systemctl reload nginx }
'@

    # Remove any old SiteForge section and replace cleanly
    $profileContent = Get-Content $PROFILE -Raw
    $profileContent = $profileContent -replace '(?s)# SiteForge Variables.*?(?=# ---|$)', ''
    $profileContent += "`n$varsBlock`n$helperBlock"
    Set-Content -Path $PROFILE -Value $profileContent

    # --- Reload profile immediately ---
    Write-Host "`n🔄 Reloading PowerShell profile to activate SiteForge..." -ForegroundColor Yellow
    . $PROFILE

    Write-Host "`n✅ SiteForge initialization complete for $Domain" -ForegroundColor Green
    Write-Host "`nNext steps:"
    Write-Host "▶ New-SiteForgeProject -Domain $Domain -Repo $Repo -Email $Email" -ForegroundColor Cyan
    Write-Host "▶ Update-Website           # deploy your site"
    Write-Host "▶ errorLogs                # view live NGINX errors"
}

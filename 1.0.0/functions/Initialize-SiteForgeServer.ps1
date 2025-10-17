function Initialize-SiteForgeServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Email = "admin@example.com"
    )

    Write-Host "`n🔧 Initializing SiteForge Server..." -ForegroundColor Cyan

    # --- System setup ---------------------------------------------------------
    Write-Host "Updating system packages..."
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y nginx git curl software-properties-common

    # --- Certbot --------------------------------------------------------------
    if (-not (Get-Command certbot -ErrorAction SilentlyContinue)) {
        Write-Host "Installing Certbot..."
        sudo apt-get install -y certbot python3-certbot-nginx
    }

    # --- SSH key --------------------------------------------------------------
    if (-not (Test-Path -Path ~/.ssh/id_ed25519)) {
        Write-Host "Generating new SSH key..."
        ssh-keygen -t ed25519 -C $Email
        Write-Host "`nYour new public SSH key (add to GitHub deploy keys):"
        cat ~/.ssh/id_ed25519.pub
        Write-Host "`n⚠️ Add this key to your GitHub account before cloning private repos."
    } else {
        Write-Host "SSH key already exists — skipping generation."
    }

    # --- Profile scaffolding --------------------------------------------------
    if (-not (Test-Path -Path $PROFILE)) {
        Write-Host "Creating PowerShell profile..."
        $profileDir = Split-Path -Parent $PROFILE
        if (-not (Test-Path -Path $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }

    # Ensure SiteForge variables exist
    if (-not (Select-String -Path $PROFILE -Pattern '^\$gitRepo' -Quiet)) {
        Add-Content -Path $PROFILE -Value "`n# SiteForge Variables`n`$gitRepo = ''`n`$webDomain = ''"
    }

    # Helper functions (domain-aware)
    $helperFunctions = @'
function errorLogs { sudo tail -f /var/log/nginx/error.log }
function nginxConfig { sudo nano "/etc/nginx/sites-available/$webDomain" }
function catnginxConfig { sudo cat "/etc/nginx/sites-available/$webDomain" }
function restartNginx { sudo nginx -t && sudo systemctl reload nginx }
'@

    if (-not (Select-String -Path $PROFILE -Pattern 'function errorLogs' -Quiet)) {
        Add-Content -Path $PROFILE -Value "`n# --- SiteForge Helper Functions ---`n$helperFunctions"
    }

    Write-Host "`n✅ SiteForge initialization complete." -ForegroundColor Green
    . $PROFILE
}


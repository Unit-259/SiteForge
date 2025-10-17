function New-SiteForgeProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [string]$Repo,
        [Parameter(Mandatory = $false)]
        [string]$Email = "admin@example.com"
    )

    Write-Host "`n🌍 Creating new SiteForge project for $Domain..." -ForegroundColor Cyan

    # --- Persist variables ----------------------------------------------------
    if (-not (Test-Path -Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }

    $repoLine   = "`$gitRepo = '$Repo'"
    $domainLine = "`$webDomain = '$Domain'"

    $content = if (Test-Path $PROFILE) { Get-Content -Raw $PROFILE } else { "" }

    foreach ($pair in @(@{pattern='^\$gitRepo\s*=.*'; line=$repoLine},
                        @{pattern='^\$webDomain\s*=.*'; line=$domainLine})) {
        if ($content -match $pair.pattern) {
            $content = $content -replace $pair.pattern, $pair.line
        } else {
            Add-Content -Path $PROFILE -Value "`n$($pair.line)"
        }
    }
    if ($content) { $content | Set-Content -Path $PROFILE }
    Write-Host "💾 Stored `$gitRepo and `$webDomain in profile."

    # --- Web root -------------------------------------------------------------
    $directory = "/var/www/html/"
    if (-not (Test-Path $directory)) {
        Write-Host "Creating web root directory..."
        sudo mkdir -p $directory
    }

    # --- Clone repo -----------------------------------------------------------
    Write-Host "Cloning repository..."
    cd /root/
    if (Test-Path ./tempdir) { Remove-Item -Recurse -Force ./tempdir }
    git clone $Repo tempdir | Out-Host

    if (Test-Path ./tempdir/html) {
        Write-Host "📁 Found 'html' folder — deploying contents..."
        Get-ChildItem -Path ./tempdir/html -Recurse | Move-Item -Destination /var/www/html -Force
    } else {
        Write-Host "📂 No 'html' folder found — deploying root repo files instead..."
        Get-ChildItem -Path ./tempdir -Recurse -Exclude '.git', '.github', '.gitignore' | Move-Item -Destination /var/www/html -Force
    }
    Remove-Item -Recurse -Force ./tempdir

    # --- NGINX configuration --------------------------------------------------
    $configPath = "/etc/nginx/sites-available/$Domain"
    if (-not (Test-Path $configPath)) {
$nginxConfig = @"
server {
    listen 80;
    server_name $Domain www.$Domain;
    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
"@
        $nginxConfig | sudo tee $configPath > $null
        sudo ln -sf $configPath "/etc/nginx/sites-enabled/$Domain"
        Write-Host "📝 Created NGINX config for $Domain"
    }

    # --- SSL certificate ------------------------------------------------------
    Write-Host "Requesting SSL certificate..."
    sudo certbot --nginx --non-interactive --agree-tos --email $Email -d $Domain -d "www.$Domain"

    sudo nginx -t
    sudo systemctl reload nginx

    Write-Host "`n✅ SiteForge project setup complete for $Domain" -ForegroundColor Green
}


function New-SiteForgeProject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,
        [Parameter(Mandatory=$true)]
        [string]$Repo,
        [Parameter(Mandatory=$false)]
        [string]$Email = "admin@example.com"
    )

    Write-Host "`n🌍 Creating new SiteForge project for $Domain..." -ForegroundColor Cyan

    # Store repo reference in PowerShell profile
    if (-not (Test-Path -Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }
    $profileLine = "`$gitRepo = '$Repo'"
    if (-not (Select-String -Path $PROFILE -Pattern '^\$gitRepo\s*=' -Quiet)) {
        Add-Content -Path $PROFILE -Value "`n# SiteForge Git Repository`n$profileLine"
    } else {
        (Get-Content $PROFILE) -replace '^\$gitRepo\s*=.*', $profileLine | Set-Content $PROFILE
    }

    Write-Host "💾 Stored `$gitRepo reference in profile."

    # Make sure NGINX web directory exists
    $directory = "/var/www/html/"
    if (-not (Test-Path -Path $directory)) {
        Write-Host "Creating web root directory..."
        sudo mkdir -p $directory
    }

    # Clone repository
    Write-Host "Cloning repository..."
    cd /root/
    git clone $Repo tempdir

    if (Test-Path -Path "./tempdir/html") {
        Get-ChildItem -Path ./tempdir/html -Recurse | Move-Item -Destination /var/www/html
    } else {
        Write-Host "⚠️ The directory 'html' does not exist within the repository."
    }

    Remove-Item -Path ./tempdir -Recurse -Force

    # Generate basic NGINX config
    $configPath = "/etc/nginx/sites-available/$Domain"
    if (-not (Test-Path -Path $configPath)) {
        $nginxConfig = @"
server {
    listen 80;
    server_name $Domain;
    root /var/www/html;
    index index.html index.htm index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
"@
        $nginxConfig | sudo tee $configPath > $null
        sudo ln -sf $configPath "/etc/nginx/sites-enabled/$Domain"
        Write-Host "📝 Created NGINX config for $Domain"
    }

    # Obtain SSL certificate
    Write-Host "Requesting SSL certificate..."
    sudo certbot --nginx --non-interactive --agree-tos --email $Email -d $Domain

    sudo nginx -t
    sudo systemctl reload nginx

    Write-Host "`n✅ SiteForge project setup complete for $Domain" -ForegroundColor Green
}

function Enable-Firewall {
    [CmdletBinding()]
    param(
        [switch]$WhitelistMyIP
    )

    Write-Host "`n🛡️ Initializing UFW firewall setup..." -ForegroundColor Cyan

    # --- Ensure UFW is installed ---
    if (-not (Get-Command ufw -ErrorAction SilentlyContinue)) {
        Write-Host "📦 Installing UFW..." -ForegroundColor Yellow
        sudo apt-get update -y | Out-Null
        sudo apt-get install -y ufw | Out-Null
    } else {
        Write-Host "✅ UFW already installed."
    }

    # --- Get current status ---
    $statusOutput = (sudo ufw status 2>&1)
    $isActive = $statusOutput -match 'Status: active'

    if ($isActive) {
        Write-Host "⚙️  Firewall is already active." -ForegroundColor Yellow
        $choice = Read-Host "Do you want to reset and reconfigure it? (Y/n)"
        if ($choice -eq 'Y' -or $choice -eq 'y' -or [string]::IsNullOrWhiteSpace($choice)) {
            sudo ufw --force reset | Out-Null
            Write-Host "🔁 Reset existing rules."
        } else {
            Write-Host "🟢 Keeping current configuration."
            return
        }
    }

    # --- Apply default deny / allow rules ---
    Write-Host "⚙️  Setting default rules..."
    sudo ufw default deny incoming | Out-Null
    sudo ufw default allow outgoing | Out-Null

    # --- Allow essential ports ---
    sudo ufw allow 22/tcp | Out-Null
    sudo ufw allow 80/tcp | Out-Null
    sudo ufw allow 443/tcp | Out-Null

    # --- Optional: Whitelist current public IP for SSH ---
    if ($WhitelistMyIP) {
        try {
            $myIP = (curl -s ifconfig.me)
            if ($myIP) {
                sudo ufw allow from $myIP to any port 22 proto tcp | Out-Null
                Write-Host "🧩 Whitelisted your current IP ($myIP) for SSH access."
            }
        } catch {
            Write-Host "⚠️  Could not retrieve your public IP automatically."
        }
    }

    # --- Enable and confirm ---
    Write-Host "🚀 Enabling firewall..."
    sudo ufw --force enable | Out-Null

    # --- Show summary ---
    Write-Host "`n✅ Firewall enabled successfully!" -ForegroundColor Green
    Show-FirewallStatus
}

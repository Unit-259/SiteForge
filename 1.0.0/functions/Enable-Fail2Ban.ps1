function Enable-Fail2Ban {
    [CmdletBinding()]
    param(
        [switch]$StrictMode
    )

    Write-Host "`n🚨 Initializing Fail2Ban setup..." -ForegroundColor Cyan

    # --- Ensure Fail2Ban is installed ---
    if (-not (Get-Command fail2ban-client -ErrorAction SilentlyContinue)) {
        Write-Host "📦 Installing Fail2Ban..." -ForegroundColor Yellow
        sudo apt-get update -y | Out-Null
        sudo apt-get install -y fail2ban | Out-Null
    } else {
        Write-Host "✅ Fail2Ban already installed."
    }

    # --- Prepare config paths ---
    $configPath = "/etc/fail2ban/jail.local"
    $backupPath = "/etc/fail2ban/jail.local.bak"

    if ((Test-Path $configPath) -and (-not (Test-Path $backupPath))) {
        sudo cp $configPath $backupPath
        Write-Host "💾 Backed up existing jail.local config."
    }

    # --- Configuration defaults ---
    $bantime  = if ($StrictMode) { "24h" } else { "10m" }
    $findtime = "10m"
    $maxretry = if ($StrictMode) { "3" } else { "5" }

    # --- Simplified and compatible config ---
    $configContent = @"
[DEFAULT]
bantime  = $bantime
findtime = $findtime
maxretry = $maxretry
backend  = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = $maxretry

[nginx-http-auth]
enabled  = true
filter   = nginx-http-auth
logpath  = /var/log/nginx/error.log
maxretry = 3
"@

    Write-Host "⚙️  Applying new Fail2Ban configuration..."
    $configContent | sudo tee $configPath > $null

    # --- Ensure service is active ---
    Write-Host "🔄 Ensuring Fail2Ban service is active..."
    sudo systemctl enable fail2ban | Out-Null
    sudo systemctl restart fail2ban | Out-Null
    Start-Sleep 2

    # --- Verify and summarize ---
    try {
        $jailsOutput = (sudo fail2ban-client status 2>&1)
        if ($jailsOutput -match "Status: active") {
            Write-Host "`n✅ Fail2Ban enabled successfully!" -ForegroundColor Green

            if ($jailsOutput -match "Jail list:") {
                $jails = ($jailsOutput -split "Jail list:")[1].Trim() -split ",\s*"
                Write-Host "`n🧱 ACTIVE JAILS"
                Write-Host "───────────────────────────────"
                foreach ($jail in $jails) {
                    $jail = $jail.Trim()
                    if ($jail) {
                        $jailStatus = (sudo fail2ban-client status $jail 2>&1)
                        $banned = ($jailStatus | Select-String "Currently banned:").ToString().Split(":")[-1].Trim()
                        if (-not [int]::TryParse($banned, [ref]$null)) { $banned = 0 }
                        Write-Host ("🟢 {0,-20} : {1} banned" -f $jail, $banned)
                    }
                }
                Write-Host "───────────────────────────────"
                Write-Host "📄 Logs: /var/log/fail2ban.log"
            }
        } else {
            Write-Host "🟥 Fail2Ban service is installed but inactive." -ForegroundColor Red
        }
    } catch {
        Write-Host "⚠️  Error retrieving Fail2Ban status: $($_.Exception.Message)"
    }
}

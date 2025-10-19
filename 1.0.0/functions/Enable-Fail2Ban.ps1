function Enable-Fail2Ban {
    <#
    .SYNOPSIS
        Installs and enables Fail2Ban with sane defaults.
    #>

    Write-Host "`n🚨 Initializing Fail2Ban setup..." -ForegroundColor Yellow
    sudo apt-get install -y fail2ban *> $null

    $jailConf = "/etc/fail2ban/jail.local"
    @"
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
"@ | sudo tee $jailConf > $null

    Write-Host "⚙️  Applying configuration..."
    sudo systemctl enable fail2ban *> $null
    sudo systemctl restart fail2ban *> $null
    Start-Sleep -Seconds 2

    if ((sudo systemctl is-active fail2ban) -eq 'active') {
        Write-Host "✅ Fail2Ban is active and running." -ForegroundColor Green
    } else {
        Write-Host "🟥 Fail2Ban failed to start. Check /var/log/fail2ban.log" -ForegroundColor Red
    }
}

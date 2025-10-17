function Show-Fail2BanStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n🔍 Checking Fail2Ban status..." -ForegroundColor Cyan

    if (-not (Get-Command fail2ban-client -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Fail2Ban is not installed."
        return
    }

    try {
        $summary = (sudo fail2ban-client status 2>&1)

        if ($summary -match "Status: active") {
            Write-Host "✅ Fail2Ban service is active." -ForegroundColor Green

            if ($summary -match "Jail list:") {
                $jails = ($summary -split "Jail list:")[1].Trim() -split ",\s*"
                $totalBanned = 0

                Write-Host "`n🧱 ACTIVE JAILS"
                Write-Host "───────────────────────────────"
                foreach ($jail in $jails) {
                    $jail = $jail.Trim()
                    if ($jail) {
                        $jailStatus = (sudo fail2ban-client status $jail 2>&1)
                        $banned = ($jailStatus | Select-String "Currently banned:").ToString().Split(":")[-1].Trim()
                        if (-not [int]::TryParse($banned, [ref]$null)) { $banned = 0 }
                        $totalBanned += [int]$banned
                        $color = if ($banned -gt 0) { "Red" } else { "Green" }
                        Write-Host ("🟢 {0,-20} : {1} banned" -f $jail, $banned) -ForegroundColor $color
                    }
                }
                Write-Host "───────────────────────────────"
                Write-Host ("📊 Total banned IPs : {0}" -f $totalBanned) -ForegroundColor Yellow
                Write-Host "📄 Logs: /var/log/fail2ban.log"
            } else {
                Write-Host "⚠️  No active jails found. Check your jail.local configuration."
            }
        } else {
            Write-Host "🟥 Fail2Ban is installed but inactive." -ForegroundColor Red
        }
    } catch {
        Write-Host "⚠️  Error retrieving Fail2Ban status: $($_.Exception.Message)"
    }
}

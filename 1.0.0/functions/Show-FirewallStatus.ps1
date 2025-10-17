function Show-FirewallStatus {
    [CmdletBinding()]
    param()

    Write-Host "`n🔎 Checking UFW status..." -ForegroundColor Cyan

    if (-not (Get-Command ufw -ErrorAction SilentlyContinue)) {
        Write-Host "❌ UFW not installed."
        return
    }

    $statusOutput = sudo ufw status numbered 2>&1

    if ($statusOutput -match 'Status: inactive') {
        Write-Host "🟥 Firewall is inactive." -ForegroundColor Red
        return
    }

    Write-Host "`n🧱 ACTIVE FIREWALL RULES"
    Write-Host "───────────────────────────────"
    $lines = $statusOutput -split "`n" | Where-Object { $_ -match '\[\s*\d+\]' }
    foreach ($line in $lines) {
        if ($line -match '22') { Write-Host "🟢 SSH:    $line" }
        elseif ($line -match '80') { Write-Host "🟢 HTTP:   $line" }
        elseif ($line -match '443') { Write-Host "🟢 HTTPS:  $line" }
        else { Write-Host "⚙️  Other:  $line" }
    }
    Write-Host "───────────────────────────────"
    Write-Host "✅ Firewall is active and protecting your server." -ForegroundColor Green
}

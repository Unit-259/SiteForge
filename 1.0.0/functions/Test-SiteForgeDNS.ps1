function Test-SiteForgeDNS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain
    )

    try {
        Write-Host "`n🌐 Checking DNS resolution for $Domain..." -ForegroundColor Yellow

        # --- Resolve domain using .NET DNS
        $addresses = [System.Net.Dns]::GetHostAddresses($Domain)
        $resolved = ($addresses | ForEach-Object { $_.ToString() }) -join ', '
        Write-Host "🧩 Raw DNS results: $resolved" -ForegroundColor DarkGray

        # --- Extract IPv4 address (force string conversion early)
        $dnsIPs = @(
            foreach ($a in $addresses) {
                if ($a.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
                    $a.ToString().Trim()
                }
            }
        )

        if (-not $dnsIPs -or $dnsIPs.Count -eq 0) {
            Write-Host "❌ Could not resolve $Domain — no IPv4 A record found." -ForegroundColor Red
            return $false
        }

        $dnsIP = [string]$dnsIPs[0]

        # --- Get this server’s public IP
        try {
            $localIP = (Invoke-RestMethod -Uri "https://api.ipify.org" -ErrorAction Stop).Trim()
        } catch {
            $localIP = (hostname -I).Split(" ")[0]
        }

        Write-Host "🌍 DNS resolves to: $dnsIP" -ForegroundColor Cyan
        Write-Host "💻 Server public IP: $localIP" -ForegroundColor Cyan

        # --- Compare results
        if ($dnsIP -eq $localIP) {
            Write-Host "✅ DNS is correctly pointed to this server ($localIP)" -ForegroundColor Green
            return $true
        } else {
            Write-Host "⚠️ DNS mismatch — domain resolves to $dnsIP but this server is $localIP" -ForegroundColor Yellow
            return $false
        }
    }
    catch {
        Write-Host "❌ Error checking DNS: $_" -ForegroundColor Red
        return $false
    }
}

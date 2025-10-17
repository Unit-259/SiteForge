function Update-Website {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$RepoLink = $gitRepo
    )

    if (-not $RepoLink) {
        Write-Host "❌ No repository link found. Please provide one or set `$gitRepo in your PowerShell profile."
        return
    }

    Write-Host "`n🔁 Updating website from $RepoLink..." -ForegroundColor Cyan

    $p = Get-Location
    sudo rm -rf /var/www/html/*
    cd /root/

    git clone $RepoLink tempdir

    if (Test-Path -Path "./tempdir/html") {
        Get-ChildItem -Path ./tempdir/html -Recurse | Move-Item -Destination /var/www/html
    } else {
        Write-Host "⚠️ The directory 'html' does not exist within the repository."
    }

    Remove-Item -Path ./tempdir -Recurse -Force
    cd $p

    sudo chmod +x /var/www/html
    sudo chmod 755 /var/www/html

    Write-Host "✅ Website updated successfully." -ForegroundColor Green
}

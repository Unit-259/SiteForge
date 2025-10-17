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

    # Save current path
    $p = Get-Location

    # Clean target directory
    if (Test-Path "/var/www/html") {
        sudo rm -rf /var/www/html/*
    } else {
        sudo mkdir -p /var/www/html
    }

    # Clone the repository fresh each time
    cd /root/
    if (Test-Path "./tempdir") {
        Remove-Item -Recurse -Force ./tempdir
    }
    git clone $RepoLink tempdir | Out-Host

    # Decide what to move
    $htmlDir = "./tempdir/html"
    $repoRoot = "./tempdir"

    if (Test-Path $htmlDir) {
        Write-Host "📁 Found 'html' folder — deploying contents..."
        Get-ChildItem -Path $htmlDir -Recurse | Move-Item -Destination /var/www/html -Force
    } else {
        Write-Host "📂 No 'html' folder found — deploying root repo files instead..."
        Get-ChildItem -Path $repoRoot -Recurse -Exclude '.git', '.github', '.gitignore' | Move-Item -Destination /var/www/html -Force
    }

    # Cleanup
    if (Test-Path "./tempdir") {
        Remove-Item -Recurse -Force ./tempdir
    }
    cd $p

    # Fix permissions
    sudo chmod -R 755 /var/www/html

    Write-Host "✅ Website updated successfully." -ForegroundColor Green
}

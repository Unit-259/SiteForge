# Import all function scripts dynamically
Get-ChildItem -Path $PSScriptRoot/functions -Filter *.ps1 | ForEach-Object {
    . $_.FullName
}

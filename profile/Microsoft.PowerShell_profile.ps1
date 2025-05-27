# Set the theme path explicitly so it’s always valid
$env:POSH_THEMES_PATH = "$HOME\Documents\PowerShell\PoshThemes"

# Only try to init if oh-my-posh.exe is on the PATH
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\aanestad.omp.json" | Invoke-Expression
} else {
    Write-Host "⚠ oh-my-posh not found on PATH" -ForegroundColor Yellow
}

# Import Terminal-Icons if available
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
} else {
    Write-Host "⚠ Terminal-Icons module not available" -ForegroundColor Yellow
}

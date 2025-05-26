<#
.SYNOPSIS
  Bootstrap-installer for PowerShell-oppsett med full override fra GitHub raw URLs:
    - Admin-sjekk
    - Overrider PowerShell-profile, Oh-My-Posh-tema, og Windows Terminal settings.json
      med Remove-Item før nedlasting for å sikre rename/override
    - Installerer PSReadLine, Terminal-Icons, Oh My Posh
    - Installerer Hack Nerd Font via winget
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# ===== Auto-elevate =====
function Ensure-Admin {
    $current = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "→ Restarting as administrator…" -ForegroundColor Yellow
        Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-Admin

# Base URL
$githubRawBase = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'

Write-Host "`n→ Overriding Windows Terminal settings.json…" -ForegroundColor Cyan
$wtTargets = @(
    Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
    Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
)
foreach ($wtPath in $wtTargets) {
    $dir = Split-Path $wtPath -Parent
    if (Test-Path $dir) {
        # Remove existing to guarantee overwrite
        Remove-Item $wtPath -Force -ErrorAction SilentlyContinue
        Invoke-RestMethod -Uri "$githubRawBase/terminal/settings.json" -OutFile $wtPath -UseBasicParsing
        Write-Host "   • Overwrote Terminal settings at $wtPath"
    }
}

Write-Host "`n→ Overriding PowerShell profile…" -ForegroundColor Cyan
$profileDest = $PROFILE.CurrentUserAllHosts
Remove-Item $profileDest -Force -ErrorAction SilentlyContinue
Invoke-RestMethod -Uri "$githubRawBase/profile/Microsoft.PowerShell_profile.ps1" `
    -OutFile $profileDest -UseBasicParsing
Write-Host "   • Overwrote profile at $profileDest"

Write-Host "`n→ Overriding Oh-My-Posh theme…" -ForegroundColor Cyan
$themeUri = "$githubRawBase/theme/aanestad.omp.json"
if ($env:POSH_THEMES_PATH) {
    $themeDest = Join-Path $env:POSH_THEMES_PATH 'aanestad.omp.json'
} else {
    $ompModule = Get-Module -ListAvailable oh-my-posh | Sort-Object Version -Descending | Select-Object -First 1
    $themeDest = Join-Path $ompModule.ModuleBase 'themes\aanestad.omp.json'
}
Remove-Item $themeDest -Force -ErrorAction SilentlyContinue
Invoke-RestMethod -Uri $themeUri -OutFile $themeDest -UseBasicParsing
Write-Host "   • Overwrote theme at $themeDest"

Write-Host "`n→ Installerer/updater moduler…" -ForegroundColor Cyan
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($mod in 'PSReadLine','Terminal-Icons','oh-my-posh') {
    if (Get-InstalledModule -Name $mod -ErrorAction SilentlyContinue) {
        Update-Module $mod -Force
        Write-Host "   • Oppdaterte $mod"
    } else {
        Install-Module  $mod -Scope CurrentUser -Force
        Write-Host "   • Installerte $mod"
    }
}

Write-Host "`n→ Installerer Hack Nerd Font via winget…" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id SourceFoundry.HackFonts -e --silent | Out-Null
    Write-Host "   • Installert Hack Nerd Font"
} else {
    Write-Warning "   • winget ikke funnet; hoppet over fontinstallasjon."
}

Write-Host "`n✅ Ferdig! Restart terminalen for å se endringene." -ForegroundColor Green

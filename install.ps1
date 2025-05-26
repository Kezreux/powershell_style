<#
.SYNOPSIS
  Bootstrap-installer for PowerShell-oppsett med full override fra GitHub raw URLs:
    - Admin-sjekk
    - Overrider Windows Terminal settings.json, Oh‑My‑Posh‑tema og PowerShell‑profil
    - Installerer/oppdaterer PSReadLine, Terminal‑Icons, Oh‑My‑Posh
    - Installerer Hack Nerd Font via winget
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

#───────────────────────────────────────────────────────────────────────────────
# 1. Auto‑elevate
#───────────────────────────────────────────────────────────────────────────────
function Ensure-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "→ Restarting as administrator …" -ForegroundColor Yellow
        Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-Admin

#───────────────────────────────────────────────────────────────────────────────
# 2. File overrides
#───────────────────────────────────────────────────────────────────────────────
$githubRawBase = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'

# (a) Windows Terminal settings.json (two possible locations)
Write-Host "`n→ Overriding Windows Terminal settings.json" -ForegroundColor Cyan
$wtTargets = @(
    Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json',
    Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
)
foreach ($wtPath in $wtTargets) {
    if (Test-Path (Split-Path $wtPath -Parent)) {
        Remove-Item $wtPath -Force -ErrorAction SilentlyContinue
        Invoke-RestMethod -Uri "$githubRawBase/terminal/settings.json" -OutFile $wtPath -UseBasicParsing
        Write-Host "   • $wtPath overwritten"
    }
}

# (b) PowerShell profile
Write-Host "`n→ Overriding PowerShell profile" -ForegroundColor Cyan
$profileDest = $PROFILE.CurrentUserAllHosts
Remove-Item $profileDest -Force -ErrorAction SilentlyContinue
Invoke-RestMethod -Uri "$githubRawBase/profile/Microsoft.PowerShell_profile.ps1" -OutFile $profileDest -UseBasicParsing
Write-Host "   • $profileDest overwritten"

# (c) Oh‑My‑Posh theme (use standard user theme folder)
Write-Host "`n→ Overriding Oh‑My‑Posh theme" -ForegroundColor Cyan
$themeUri  = "$githubRawBase/theme/aanestad.omp.json"
$themeDest = Join-Path $env:USERPROFILE 'Documents\PowerShell\PoshThemes\aanestad.omp.json'
$themeDir  = Split-Path $themeDest -Parent
if (-not (Test-Path $themeDir)) { New-Item -Path $themeDir -ItemType Directory -Force | Out-Null }
Remove-Item $themeDest -Force -ErrorAction SilentlyContinue
Invoke-RestMethod -Uri $themeUri -OutFile $themeDest -UseBasicParsing
Write-Host "   • $themeDest overwritten"

#───────────────────────────────────────────────────────────────────────────────
# 3. PowerShell modules
#───────────────────────────────────────────────────────────────────────────────
Write-Host "`n→ Installing/updating PowerShell modules" -ForegroundColor Cyan
$modules = 'PSReadLine','Terminal-Icons','oh-my-posh'
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in $modules) {
    if (Get-InstalledModule -Name $m -ErrorAction SilentlyContinue) {
        Update-Module $m -Force
        Write-Host "   • Updated $m"
    } else {
        Install-Module $m -Scope CurrentUser -Force
        Write-Host "   • Installed $m"
    }
}

#───────────────────────────────────────────────────────────────────────────────
# 4. Hack Nerd Font via winget
#───────────────────────────────────────────────────────────────────────────────
Write-Host "`n→ Installing Hack Nerd Font" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id SourceFoundry.HackFonts -e --silent | Out-Null
    Write-Host "   • Hack Nerd Font installed"
} else {
    Write-Warning "   • winget not found; font skipped"
}

Write-Host "`n✅ All done! Restart the terminal to see the changes." -ForegroundColor Green

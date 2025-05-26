<#
.SYNOPSIS
  Bootstrap-installer for PowerShell-oppsett med full override fra GitHub raw URLs:
    - Admin-sjekk
    - Downloader PowerShell-profile, Oh-My-Posh-tema og Windows Terminal settings fra GitHub
    - Installerer PSReadLine, Terminal-Icons, Oh My Posh
    - Installerer Hack Nerd Font via winget
    - Overrider alle filer uansett tidligere innhold
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# ── CONFIG ──────────────────────────────────────────────────────────────────────
$githubRawBase = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'
$fileMap = @{
    # Windows Terminal settings.json
    "$githubRawBase/terminal/settings.json" = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    # Oh My Posh tema
    "$githubRawBase/theme/aanestad.omp.json" = Join-Path $env:USERPROFILE 'Documents\PowerShell\PoshThemes\aanestad.omp.json'
    # PowerShell-profile
    "$githubRawBase/profile/Microsoft.PowerShell_profile.ps1" = $PROFILE.CurrentUserAllHosts
}
$modules     = 'PSReadLine','Terminal-Icons','oh-my-posh'
$fontPackage = 'SourceFoundry.HackFonts'
# ────────────────────────────────────────────────────────────────────────────────

function Ensure-Admin {
    if (-not ([Security.Principal.WindowsPrincipal]::new(
            [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        Write-Host "→ Restarting as administrator…" -ForegroundColor Yellow
        Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-Admin

Write-Host "`n→ Downloader og overrider filer fra GitHub…" -ForegroundColor Cyan
foreach ($url in $fileMap.Keys) {
    $dst = $fileMap[$url]
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Write-Host "   • Overrider $([IO.Path]::GetFileName($dst)) ← $url"
    Invoke-RestMethod -Uri $url -OutFile $dst -UseBasicParsing -ErrorAction Stop
}

Write-Host "`n→ Installerer/opdaterer PowerShell-moduler…" -ForegroundColor Cyan
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($mod in $modules) {
    if (Get-InstalledModule -Name $mod -ErrorAction SilentlyContinue) {
        Write-Host "   • Oppdaterer $mod"
        Update-Module $mod -Force
    } else {
        Write-Host "   • Installerer $mod"
        Install-Module $mod -Scope CurrentUser -Force
    }
}

Write-Host "`n→ Installerer Hack Nerd Font via winget…" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id $fontPackage -e --silent | Out-Null
    Write-Host "   • Hack Nerd Font installert"
} else {
    Write-Warning "   • winget ikke funnet; font installasjon hoppes over."
}

Write-Host "`n✅ Ferdig! Vennligst restart terminalen for å se endringene." -ForegroundColor Green

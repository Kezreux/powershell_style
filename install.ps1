<#
.SYNOPSIS
  Bootstrap-installer for PowerShell-oppsett med full override fra GitHub raw URLs:
    - Admin-sjekk
    - Downloader JSON- og PowerShell-profile fra GitHub
    - Installerer PSReadLine, Terminal-Icons, Oh My Posh
    - Installerer Hack Nerd Font via winget
    - Overrider Windows Terminal settings.json fra GitHub
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# ── CONFIG ──────────────────────────────────────────────────────────────────────
$githubRawBase = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'

# Kartlegg rå URL → lokal sti
$fileMap = @{
    # Windows Terminal
    "$githubRawBase/terminal/settings.json" = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    # Oh My Posh theme
    "$githubRawBase/theme/aanestad.omp.json" = "$env:USERPROFILE\.config\oh-my-posh\themes.json"
    # PowerShell-profile
    "$githubRawBase/profile/Microsoft.PowerShell_profile.ps1" = $PROFILE.CurrentUserAllHosts
}

# Moduler og font-pakke
$modules      = 'PSReadLine','Terminal-Icons','oh-my-posh'
$fontPackage  = 'SourceFoundry.HackFonts'
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

Write-Host "`n→ Downloading files from GitHub…" -ForegroundColor Cyan
foreach ($url in $fileMap.Keys) {
    $dst = $fileMap[$url]
    $dir = Split-Path $dst -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Write-Host "   • $([IO.Path]::GetFileName($dst)) ← $url"
    Invoke-RestMethod -Uri $url -OutFile $dst -UseBasicParsing
}

Write-Host "`n→ Installing/updating PowerShell modules…" -ForegroundColor Cyan
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($mod in $modules) {
    if (Get-InstalledModule -Name $mod -ErrorAction SilentlyContinue) {
        Write-Host "   • Updating $mod"
        Update-Module   $mod -Force
    } else {
        Write-Host "   • Installing $mod"
        Install-Module  $mod -Scope CurrentUser -Force
    }
}

Write-Host "`n→ Installing Hack Nerd Font via winget…" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id $fontPackage -e --silent
} else {
    Write-Warning "   • winget not found; installer vil hoppe over fontinstallasjon."
}

Write-Host "`n✅ Fullførte oppsettet! Vennligst restart terminalen for å se endringene." -ForegroundColor Green

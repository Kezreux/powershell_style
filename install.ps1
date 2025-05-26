<#
.SYNOPSIS
  Bootstrap-installer for PowerShell-oppsett med full override fra GitHub raw URLs:
    - Admin-sjekk
    - Downloader JSON- og profile-filer fra GitHub
    - Installerer PSReadLine, Terminal-Icons, Oh My Posh
    - Installerer Hack Nerd Font via winget
    - Kopierer Windows Terminal settings.json fra GitHub (override)
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# ── CONFIG ──────────────────────────────────────────────────────────────────────
$githubRawBase = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'
$fileMap = @{  
    "$githubRawBase/terminal/settings.json"  = "$env:USERPROFILE\.config\myapp\settings.json"
    "$githubRawBase/theme/aanestad.omp.json"    = "$env:USERPROFILE\.config\oh-my-posh\themes.json"
    "$githubRawBase/profile/Microsoft.PowerShell_profile.ps1"   = $PROFILE.CurrentUserAllHosts
    "$githubRawBase/terminal/settings.json" = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
}
$modules = 'PSReadLine','Terminal-Icons','oh-my-posh'
$fontPackageId = 'SourceFoundry.HackFonts'
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

Write-Host "`n→ Installing/updating PS modules…" -ForegroundColor Cyan
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in $modules) {
    if (Get-InstalledModule -Name $m -ErrorAction SilentlyContinue) {
        Write-Host "   • Updating $m"
        Update-Module $m -Force
    } else {
        Write-Host "   • Installing $m"
        Install-Module $m -Scope CurrentUser -Force
    }
}

Write-Host "`n→ Installing Hack Nerd Font via winget…" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget install --id $fontPackageId -e --silent
} else {
    Write-Warning "   • winget not found; install Hack Nerd Font manually."
}

Write-Host "`n✅ Done! Restart your terminal to apply changes." -ForegroundColor Green

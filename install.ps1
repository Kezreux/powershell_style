<#
.SYNOPSIS
  Bootstrap-installer for PowerShell‑oppsett med full override fra GitHub raw URLs:
    • Admin‑sjekk og auto‑elevasjon
    • Overrider Windows‑Terminal settings.json, Oh‑My‑Posh‑tema og PowerShell‑profil (sletter først, laster ned fra GitHub)
    • Setter POSH_THEMES_PATH automatisk
    • Installerer/oppdaterer PSReadLine, Terminal‑Icons, Oh‑My‑Posh
    • Installerer Hack Nerd Font via winget
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

#────────────────────────── 1. Auto‑elevate ────────────────────────────────
function Ensure-Admin {
    $p = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "→ Restarting as administrator …" -ForegroundColor Yellow
        Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-Admin

$github = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'

#────────────────────────── 2. Windows Terminal ─────────────────────────────
Write-Host "`n→ Overriding Windows Terminal settings.json" -ForegroundColor Cyan
$wtTargets = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
foreach ($path in $wtTargets) {
    if (Test-Path (Split-Path $path -Parent)) {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
        Invoke-RestMethod -Uri "$github/terminal/settings.json" -OutFile $path -UseBasicParsing
        Write-Host "   • $path overwritten"
    }
}

#────────────────────────── 3. PowerShell-profile ────────────────────────────
Write-Host "`n→ Overriding host-specific PowerShell profile" -ForegroundColor Cyan

$hostProfile = $PROFILE.CurrentUserCurrentHost
$hostDir     = Split-Path $hostProfile -Parent

# 1) Ensure the directory exists
if (-not (Test-Path $hostDir)) {
    New-Item -Path $hostDir -ItemType Directory -Force | Out-Null
}

# 2) Download the remote profile into a string
$remoteUri = "$github/profile/Microsoft.PowerShell_profile.ps1"
$profileContent = Invoke-RestMethod -Uri $remoteUri -UseBasicParsing -ErrorAction Stop

# 3) Prepend the Import-Module line
$bootstrap = @'
# auto-import oh-my-posh so the shim is available
Import-Module oh-my-posh -ErrorAction SilentlyContinue
'@

# 4) Write it all out
($bootstrap + "`n" + $profileContent) |
  Out-File -FilePath $hostProfile -Encoding UTF8 -Force

Write-Host "   • $hostProfile overwritten (with Import-Module prepended)"



#────────────────────────── 4. Oh‑My‑Posh‑tema ──────────────────────────────
Write-Host "`n→ Overriding Oh‑My‑Posh theme" -ForegroundColor Cyan
$themeDest = "$HOME\Documents\PowerShell\PoshThemes\aanestad.omp.json"
$themeDir  = Split-Path $themeDest -Parent
if (-not (Test-Path $themeDir)) { New-Item -ItemType Directory $themeDir -Force | Out-Null }
Remove-Item $themeDest -Force -ErrorAction SilentlyContinue
Invoke-RestMethod -Uri "$github/theme/aanestad.omp.json" -OutFile $themeDest -UseBasicParsing
Write-Host "   • $themeDest overwritten"

# Sett miljøvariabel slik at profile-linjen finner temaet
[Environment]::SetEnvironmentVariable('POSH_THEMES_PATH', $themeDir, 'User')
$env:POSH_THEMES_PATH = $themeDir
Write-Host "   • POSH_THEMES_PATH set to $themeDir"

#────────────────────────── 5. PowerShell‑moduler ───────────────────────────
Write-Host "`n→ Installing/updating PowerShell modules" -ForegroundColor Cyan
$mods = 'PSReadLine','Terminal-Icons','oh-my-posh'
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach ($m in $mods) {
    if (Get-InstalledModule -Name $m -ErrorAction SilentlyContinue) {
        Update-Module $m -Force
        Write-Host "   • Updated $m"
    } else {
        Install-Module $m -Scope CurrentUser -Force
        Write-Host "   • Installed $m"
    }
}

#────────────────────────── 6. Hack Nerd Font ───────────────────────────────
Write-Host "`n→ Installing Hack Nerd Font via winget" -ForegroundColor Cyan

if (Get-Command winget -ErrorAction SilentlyContinue) {
    $args = @(
        'install',
        '--id', 'SourceFoundry.HackFonts',
        '-e',  '--silent',
        '--accept-source-agreements',
        '--accept-package-agreements'
    )

    # Launch Winget in-process, wait for it to finish
    Start-Process -FilePath winget `
                  -ArgumentList $args `
                  -NoNewWindow `
                  -Wait

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   • Hack Nerd Font installed"
    } else {
        Write-Warning "   • Winget exited with code $LASTEXITCODE; font may not have been installed."
    }
} else {
    Write-Warning "   • winget not found; font skipped"
}

Write-Host "`n✅ Done! Restart the terminal to see the changes." -ForegroundColor Green

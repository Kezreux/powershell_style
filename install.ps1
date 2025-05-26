<#
.SYNOPSIS
  Full bootstrap for Windows Terminal + PowerShell + Oh-My-Posh + Nerd fonts
#>

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

# 1) Elevate
function Ensure-Admin {
  $p = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent())
  if (-not $p.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "→ Restarting as administrator…" -ForegroundColor Yellow
    Start-Process pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
  }
}
Ensure-Admin

$github = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'

# 2) Windows Terminal
Write-Host "`n→ Overriding Windows Terminal settings.json" -ForegroundColor Cyan
$wt = @(
  "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
  "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)
foreach($p in $wt){
  $dir = Split-Path $p -Parent
  if (Test-Path $dir) {
    Remove-Item $p -Force -ErrorAction SilentlyContinue
    Invoke-RestMethod "$github/terminal/settings.json" -OutFile $p -UseBasicParsing
    Write-Host "   • $p"
  }
}

# 3) Theme file
Write-Host "`n→ Installing aanestad theme" -ForegroundColor Cyan
$themeDir = "$env:USERPROFILE\Documents\PowerShell\PoshThemes"
$themeFile= Join-Path $themeDir 'aanestad.omp.json'
if (-not (Test-Path $themeDir)) { New-Item $themeDir -ItemType Directory -Force|Out-Null }
Remove-Item $themeFile -Force -ErrorAction SilentlyContinue
Invoke-RestMethod "$github/theme/aanestad.omp.json" -OutFile $themeFile -UseBasicParsing
Write-Host "   • $themeFile"

# 4) Profile
Write-Host "`n→ Writing PowerShell profile" -ForegroundColor Cyan
$hp = $PROFILE.CurrentUserCurrentHost
$hpd = Split-Path $hp -Parent
if (-not (Test-Path $hpd)) { New-Item $hpd -ItemType Directory -Force|Out-Null }

# This snippet will run _every_ new shell:
$stub = @'
# set theme path for this session
$Env:POSH_THEMES_PATH = "$env:USERPROFILE\Documents\PowerShell\PoshThemes"

# bootstrap the standalone Oh-My-Posh
& oh-my-posh init pwsh --config "$Env:POSH_THEMES_PATH\aanestad.omp.json" |
    Invoke-Expression
'@

Invoke-RestMethod "$github/profile/Microsoft.PowerShell_profile.ps1" -UseBasicParsing -OutVariable content
( $stub + "`r`n" + $content ) |
  Out-File $hp -Encoding UTF8 -Force

Write-Host "   • $hp"

# 5) PS modules
Write-Host "`n→ Installing PSReadLine & Terminal-Icons" -ForegroundColor Cyan
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
foreach($m in 'PSReadLine','Terminal-Icons'){
  if (Get-InstalledModule $m -ErrorAction SilentlyContinue){
    Update-Module $m -Force;    Write-Host "   • Updated $m"
  } else {
    Install-Module $m -Scope CurrentUser -Force; Write-Host "   • Installed $m"
  }
}

#────────────────────────── 6. Hack Nerd Font ───────────────────────────────
Write-Host "`n→ Installing & verifying Hack Nerd Font" -ForegroundColor Cyan

# A) Attempt Winget install
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Start-Process winget -ArgumentList @(
        'install','--id','SourceFoundry.HackFonts','-e','--silent',
        '--accept-source-agreements','--accept-package-agreements'
    ) -NoNewWindow -Wait
    Write-Host "   • winget exit code $LASTEXITCODE"
} else {
    Write-Warning "   • winget not found; will install manually"
}

# B) Check if Windows actually knows about “Hack Nerd Font”
$hasFont = [System.Drawing.FontFamily]::Families |
           Where-Object Name -Like '*Hack Nerd Font*'

if ($hasFont) {
    Write-Host "   • Hack Nerd Font registered: $($hasFont.Name -join ', ')"
} else {
    Write-Warning "   • Hack Nerd Font still missing—installing manually…"

    # Download the zip from upstream GitHub
    $zipUrl   = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v2.3.3/Hack.zip'
    $zipFile  = Join-Path $env:TEMP 'HackNerd.zip'
    Invoke-RestMethod -Uri $zipUrl -OutFile $zipFile -UseBasicParsing

    # Extract to per-user Fonts
    $userFontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    if (-not (Test-Path $userFontDir)) { New-Item -ItemType Directory -Path $userFontDir -Force | Out-Null }
    Expand-Archive -Path $zipFile -DestinationPath $userFontDir -Force

    # Copy into system Fonts (requires admin)
    $systemFontDir = "$env:WINDIR\Fonts"
    Copy-Item "$userFontDir\*.ttf" -Destination $systemFontDir -Force

    Write-Host "   • Hack Nerd Font files copied to user+system Fonts"
}


# 7) Oh-My-Posh CLI
Write-Host "`n→ Installing Oh-My-Posh CLI" -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue){
  Start-Process winget -ArgumentList @(
    'install','--id','JanDeDobbeleer.OhMyPosh','-e','--silent',
    '--accept-source-agreements','--accept-package-agreements'
  ) -NoNewWindow -Wait
  Write-Host "   • Winget code $LASTEXITCODE"
} else {
  Write-Warning "   • winget not found"
}

Write-Host "`n✅ Done! Please reboot or sign out/in before running PowerShell." -ForegroundColor Green

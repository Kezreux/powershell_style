<#
.SYNOPSIS
  Uninstalls all components installed by autotronic.ps1:
  - Oh My Posh
  - Terminal-Icons
  - Nerd Fonts (FiraCode, Hack, Meslo)
  - Theme JSONs & env var
  - PowerShell profile
  - Windows Terminal settings.json
#>

#region Helper: Log to console
function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')]$Level='INFO')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$ts] [$Level] $Message"
}
#endregion

# ─────────────────────────────────────────────────────────────
# 1) Remove Oh My Posh
# ─────────────────────────────────────────────────────────────
Write-Log "Removing Oh My Posh…" 'INFO'
if (Get-Command winget -ErrorAction SilentlyContinue) {
    winget uninstall --id JanDeDobbeleer.OhMyPosh -e --accept-package-agreements --accept-source-agreements -h | Out-Null
}
if (Get-Module -ListAvailable -Name oh-my-posh) {
    Uninstall-Module -Name oh-my-posh -AllVersions -Force -ErrorAction SilentlyContinue
}
Write-Log "Oh My Posh removal complete." 'INFO'

# ─────────────────────────────────────────────────────────────
# 2) Remove Terminal-Icons
# ─────────────────────────────────────────────────────────────
Write-Log "Removing Terminal-Icons…" 'INFO'
if (Get-Module -ListAvailable -Name 'Terminal-Icons') {
    Uninstall-Module -Name 'Terminal-Icons' -AllVersions -Force -ErrorAction SilentlyContinue
}
Write-Log "Terminal-Icons removal complete." 'INFO'

# ─────────────────────────────────────────────────────────────
# 3) Uninstall Nerd Fonts
# ─────────────────────────────────────────────────────────────
function Remove-NerdFont([string]$FontLabel) {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    # Remove registry entry
    if (Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
        Where-Object { $_.PSObject.Properties.Name -eq "$FontLabel (TrueType)" }) {
        Write-Log "Removing registry entry for $FontLabel" 'INFO'
        Remove-ItemProperty -Path $regPath -Name "$FontLabel (TrueType)" -ErrorAction SilentlyContinue
    }
    # Remove font files
    $fontsFolder = "$env:WINDIR\Fonts"
    Get-ChildItem $fontsFolder -Filter "*$($FontLabel.Replace(' ','*'))*.ttf" -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "Deleting font file $($_.Name)" 'INFO'
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
}
Write-Log "Uninstalling Nerd Fonts…" 'INFO'
@('FiraCode Nerd Font','Hack Nerd Font','Meslo Nerd Font') | ForEach-Object { Remove-NerdFont $_ }
Write-Log "Nerd Fonts removal complete." 'INFO'

# ─────────────────────────────────────────────────────────────
# 4) Remove theme JSONs & POSH_THEMES_PATH
# ─────────────────────────────────────────────────────────────
$themeDir = "$env:USERPROFILE\Documents\PowerShell\PoshThemes"
if (Test-Path $themeDir) {
    Write-Log "Deleting theme directory $themeDir" 'INFO'
    Remove-Item $themeDir -Recurse -Force
}
Write-Log "Clearing POSH_THEMES_PATH user env var" 'INFO'
[Environment]::SetEnvironmentVariable('POSH_THEMES_PATH',$null,'User')

# ─────────────────────────────────────────────────────────────
# 5) Remove PowerShell profile
# ─────────────────────────────────────────────────────────────
$profilePath = $Profile.CurrentUserAllHosts
if (Test-Path $profilePath) {
    Write-Log "Backing up and deleting profile $profilePath" 'INFO'
    Copy-Item $profilePath ($profilePath + '.uninstallbak') -Force
    Remove-Item $profilePath -Force
}

# ─────────────────────────────────────────────────────────────
# 6) Remove Windows Terminal settings.json
# ─────────────────────────────────────────────────────────────
$settingsDir  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$settingsFile = Join-Path $settingsDir 'settings.json'
if (Test-Path $settingsFile) {
    Write-Log "Backing up and deleting Windows Terminal settings.json" 'INFO'
    Copy-Item $settingsFile ($settingsFile + '.uninstallbak') -Force
    Remove-Item $settingsFile -Force
}

function Remove-OhMyPosh {
    Write-Log "=== Removing Oh My Posh ===" 'INFO'

    # 1) Winget uninstall (catches msstore & community source)
    Write-Log "Attempting winget uninstall of JanDeDobbeleer.OhMyPosh…" 'INFO'
    try {
        & winget uninstall --id JanDeDobbeleer.OhMyPosh -e `
            --accept-package-agreements --accept-source-agreements -h 2>&1 | Out-Null
        Write-Log "  winget uninstall complete (if it was installed)." 'INFO'
    }
    catch {
        Write-Log "  winget uninstall failed or not present: $($_.Exception.Message)" 'WARN'
    }

    # 2) Remove any Appx/MSIX if it still lingers
    Write-Log "Checking for Appx/MSIX package…" 'INFO'
    $appx = Get-AppxPackage -Name "*oh-my-posh*" -ErrorAction SilentlyContinue
    if ($appx) {
        Write-Log "  Found Appx package $($appx.PackageFullName); removing…" 'INFO'
        Remove-AppxPackage -Package $appx.PackageFullName -ErrorAction SilentlyContinue
        Write-Log "  Appx package removed." 'INFO'
    }
    else {
        Write-Log "  No Appx/MSIX package found." 'INFO'
    }

    # 3) Remove any shims in WindowsApps
    $winApps = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    Write-Log "Cleaning up any oh-my-posh shims in $winApps…" 'INFO'
    Get-ChildItem $winApps -Filter "oh-my-posh*" -Force -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Log "  Deleting shim $($_.FullName)" 'INFO'
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

    # 4) Remove any standalone install folder (e.g. if you used manual MSI fallback)
    $installDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh'
    if (Test-Path $installDir) {
        Write-Log "Removing leftover folder $installDir…" 'INFO'
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 5) Remove any modules under user profile
    $modDir = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\oh-my-posh'
    if (Test-Path $modDir) {
        Write-Log "Removing PSModule folder $modDir…" 'INFO'
        Remove-Item $modDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Oh My Posh teardown complete." 'INFO'
}

# Invoke it:
Remove-OhMyPosh


# ─────────────────────────────────────────────────────────────
# 7) Final cleanup
# ─────────────────────────────────────────────────────────────
Write-Log "Uninstall of all autotronic components complete." 'INFO'
Write-Host ""
Write-Host "⚠️  You may need to restart your shell/Windows Terminal for changes to fully apply." -ForegroundColor Yellow

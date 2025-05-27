<#
.SYNOPSIS
  Fully tears down everything installed by autotronic.ps1:
   - Oh My Posh (exe, PSGallery, WindowsApps shims)
   - Terminal-Icons (PowerShell module)
   - Nerd Fonts (FiraCode, Hack, Meslo) in registry + files
   - Themes directory + POSH_THEMES_PATH
   - All relevant PowerShell profiles
   - Windows Terminal settings.json
.DESCRIPTION
  Each step is idempotent, logged, and errors are isolated. 
  Backups of user-modified files (profiles, settings.json) are timestamped.
#>

#region — Helpers & Logging
function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO','WARN','ERROR')] 
        [string]$Level,
        [Parameter(Mandatory)][string]$Message
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $prefix = "[${ts}] [$Level]"
    if ($Level -eq 'ERROR') {
        Write-Host "$prefix $Message" -ForegroundColor Red
    } elseif ($Level -eq 'WARN') {
        Write-Host "$prefix $Message" -ForegroundColor Yellow
    } else {
        Write-Host "$prefix $Message"
    }
}

function Safe-RemoveItem {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recurse
    )
    try {
        if (Test-Path $Path) {
            if ($Recurse) { Remove-Item $Path -Recurse -Force }
            else         { Remove-Item $Path -Force }
            Write-Log INFO "Removed: $Path"
        }
    } catch {
        Write-Log WARN "Could not remove $Path — $($_.Exception.Message)"
    }
}

function Backup-File {
    param(
        [Parameter(Mandatory)][string]$FilePath
    )
    if (Test-Path $FilePath) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backup = "${FilePath}.bak-$stamp"
        try {
            Copy-Item $FilePath $backup -Force
            Write-Log INFO "Backed up $FilePath → $backup"
        } catch {
            Write-Log WARN "Failed to back up $FilePath — $($_.Exception.Message)"
        }
    }
}

function Remove-UserEnvPath {
    param([Parameter(Mandatory)][string]$Folder)
    $current = [Environment]::GetEnvironmentVariable('Path','User').Split(';')
    if ($current -contains $Folder) {
        $new = ($current | Where-Object { $_ -ne $Folder }) -join ';'
        [Environment]::SetEnvironmentVariable('Path',$new,'User')
        Write-Log INFO "Stripped user PATH entry: $Folder"
    }
}
#endregion

#region — 1) Oh My Posh
function Remove-OhMyPosh {
    Write-Log INFO "=== Removing Oh My Posh ==="

    # A) winget uninstall
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget uninstall --id=JanDeDobbeleer.OhMyPosh -e `
                --accept-package-agreements --accept-source-agreements -h |
                Out-Null
            Write-Log INFO "winget package removed (if it existed)."
        } catch {
            Write-Log WARN "winget uninstall failed: $($_.Exception.Message)"
        }
    }

    # B) PSGallery module
    if (Get-InstalledModule -Name oh-my-posh -ErrorAction SilentlyContinue) {
        try {
            Uninstall-Module -Name oh-my-posh -AllVersions -Force
            Write-Log INFO "PowerShell module 'oh-my-posh' removed."
        } catch {
            Write-Log WARN "Failed to remove PS module: $($_.Exception.Message)"
        }
    }

    # C) remove WindowsApps stubs
    $stubs = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh*'
    Get-ChildItem $stubs -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Safe-RemoveItem $_.FullName
    }

    # D) any loose exe in Programs
    $progs = Join-Path $env:LOCALAPPDATA 'Programs'
    Get-ChildItem $progs -Recurse -Filter 'oh-my-posh.exe' -ErrorAction SilentlyContinue |
        ForEach-Object { Safe-RemoveItem $_.FullName }

    # E) PATH cleanup
    $installDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
    Remove-UserEnvPath -Folder $installDir
}
Remove-OhMyPosh
#endregion

#region — 2) Terminal-Icons
Write-Log INFO "=== Removing Terminal-Icons ==="
if (Get-InstalledModule -Name Terminal-Icons -ErrorAction SilentlyContinue) {
    try {
        Uninstall-Module -Name Terminal-Icons -AllVersions -Force
        Write-Log INFO "Terminal-Icons module removed."
    } catch {
        Write-Log WARN "Failed to remove Terminal-Icons: $($_.Exception.Message)"
    }
}
#endregion

#region — 3) Nerd Fonts (Registry + Files)
Write-Log INFO "=== Removing Nerd Fonts ==="
$fonts = @('FiraCode Nerd Font','Hack Nerd Font','Meslo Nerd Font')
$regBases = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Fonts'

foreach ($label in $fonts) {
    foreach ($reg in $regBases) {
        $name = "$label (TrueType)"
        try {
            if ((Get-ItemProperty -Path $reg -Name $name -ErrorAction SilentlyContinue)) {
                Remove-ItemProperty -Path $reg -Name $name -ErrorAction SilentlyContinue
                Write-Log INFO "Removed registry font entry: $reg\$name"
            }
        } catch {
            Write-Log WARN "Reg cleanup failed at $reg\${name}: $($_.Exception.Message)"
        }
    }
    # Delete any matching .ttf under %windir%\Fonts
    Get-ChildItem "$env:WINDIR\Fonts" -Filter "*$($label.Replace(' ','*')).ttf" -Recurse |
        ForEach-Object { Safe-RemoveItem $_.FullName }
}
#endregion

#region — 4) Themes & POSH_THEMES_PATH
Write-Log INFO "=== Removing custom theme JSONs & env var ==="
$themeDir = Join-Path $env:USERPROFILE 'Documents\PowerShell\PoshThemes'
Backup-File $themeDir
Safe-RemoveItem $themeDir -Recurse
[Environment]::SetEnvironmentVariable('POSH_THEMES_PATH',$null,'User')
Write-Log INFO "Cleared user env var POSH_THEMES_PATH"
#endregion

#region — 5) PowerShell Profiles
Write-Log INFO "=== Removing PowerShell profiles ==="
$profiles = @(
    $Profile.CurrentUserAllHosts,
    $Profile.CurrentUserCurrentHost,
    $Profile.AllUsersAllHosts,
    $Profile.AllUsersCurrentHost
)
foreach ($p in $profiles | Where-Object { $_ }) {
    Backup-File $p
    Safe-RemoveItem $p
}
#endregion

#region — 6) Windows Terminal settings.json
Write-Log INFO "=== Removing Windows Terminal settings.json ==="
$wtDir  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$wtFile = Join-Path $wtDir 'settings.json'
Backup-File $wtFile
Safe-RemoveItem $wtFile
#endregion

Write-Log INFO "All components uninstalled. You may need to restart your shell/Windows Terminal."

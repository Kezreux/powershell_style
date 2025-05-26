<#
.SYNOPSIS
  Bootstrap-installer for mitt PowerShell-oppsett:
    - Admin-sjekk
    - Installerer PSReadLine
    - Installerer Terminal-Icons
    - Installerer Oh My Posh
    - Installerer Hack Nerd Font
    - Kopierer lokale profil- og tema-filer
    - Kopierer Windows Terminal settings.json (valgfritt)
#>

# Sørger for at alle stier er relative til der dette skriptet ligger
$ScriptDir = $PSScriptRoot

function Ensure-Admin {
    if (-not (
        [Security.Principal.WindowsPrincipal]::new(
          [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    )) {
        Write-Host "Starter som Administrator…" -ForegroundColor Yellow
        $exe    = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell.exe' }
        $script = $MyInvocation.MyCommand.Path
        Start-Process $exe "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs
        exit
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
  Write-Warning "PowerShell Core 7+ anbefales for best opplevelse."
}

Write-Host "Welcome to the PowerShell bootstrap installer to spice up your terminal experience!" -ForegroundColor Green

function Install-PSReadLine {
    Write-Host "Installing PSReadLine…" -ForegroundColor Cyan
    Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -PredictionSource History
    Write-Host "✔ PSReadLine installed and configured." -ForegroundColor Green
}

function Install-TerminalIcons {
    Write-Host "Installing Terminal-Icons…" -ForegroundColor Cyan
    Install-Module Terminal-Icons -Scope CurrentUser -Force -AllowClobber
    Import-Module Terminal-Icons
    Write-Host "✔ Terminal-Icons installed." -ForegroundColor Green
}

function Install-OhMyPosh {
    Write-Host "Installing Oh My Posh…" -ForegroundColor Cyan
    Install-Module oh-my-posh -Scope CurrentUser -Force -AllowClobber
    Import-Module oh-my-posh
    Write-Host "✔ Oh My Posh installed." -ForegroundColor Green
}

function Install-NerdFont {
    $url        = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip"
    $zipTmp     = Join-Path $env:TEMP "hack.zip"
    $extractDir = Join-Path $env:TEMP "Hack"

    Write-Host "Downloading Hack Nerd Font…" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $url -OutFile $zipTmp

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::ExtractToDirectory($zipTmp, $extractDir)

    Get-ChildItem -Path $extractDir -Filter '*.ttf' | ForEach-Object {
        $destFont = Join-Path "$env:WINDIR\Fonts" $_.Name
        if (Test-Path $destFont) {
            Write-Host "Skipping existing font: $($_.Name)" -ForegroundColor Yellow
        } else {
            Copy-Item $_.FullName -Destination "$env:WINDIR\Fonts" -Force
            New-ItemProperty `
              -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
              -Name $_.Name -Value $_.Name -PropertyType String -Force | Out-Null
            Write-Host "✔ Installed font: $($_.Name)" -ForegroundColor Green
        }
    }

    Remove-Item $zipTmp     -Force
    Remove-Item $extractDir -Recurse -Force

    Write-Host "✔ Hack Nerd Font installation complete." -ForegroundColor Green
}

function Copy-Themes-And-Profile {
    # Kopier .ps1-profiler, skip hvis allerede eksisterer
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir | Out-Null
    }
    Get-ChildItem -Path (Join-Path $ScriptDir 'profile') -Filter '*.ps1' | ForEach-Object {
        $dest = Join-Path $profileDir $_.Name
        if (Test-Path $dest) {
            Write-Host "Skipping existing profile: $($_.Name)" -ForegroundColor Yellow
        } else {
            Copy-Item -Path $_.FullName -Destination $dest
            Write-Host "✔ Copied profile: $($_.Name)" -ForegroundColor Green
        }
    }

    # Kopier .omp.json-temaer, skip hvis allerede eksisterer
    $themeDest = Join-Path $env:USERPROFILE 'Documents\PowerShell\PoshThemes'
    if (-not (Test-Path $themeDest)) {
        New-Item -ItemType Directory -Path $themeDest | Out-Null
    }
    Get-ChildItem -Path (Join-Path $ScriptDir 'theme') -Filter '*.omp.json' | ForEach-Object {
        $destTheme = Join-Path $themeDest $_.Name
        if (Test-Path $destTheme) {
            Write-Host "Skipping existing theme: $($_.Name)" -ForegroundColor Yellow
        } else {
            Copy-Item -Path $_.FullName -Destination $destTheme
            Write-Host "✔ Copied theme: $($_.Name)" -ForegroundColor Green
        }
    }
}

function Copy-TerminalSettings {
    $src = Join-Path $ScriptDir 'terminal\settings.json'
    if (-not (Test-Path $src)) {
        Write-Host "Windows Terminal settings.json not found (skipping)." -ForegroundColor Yellow
        return
    }

    $wtPath1 = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $wtPath2 = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal'

    foreach ($wtPath in @($wtPath1, $wtPath2)) {
        if (Test-Path $wtPath) {
            $destFile = Join-Path $wtPath 'settings.json'
            if (Test-Path $destFile) {
                Write-Host "Skipping existing Terminal settings in $wtPath" -ForegroundColor Yellow
            } else {
                Copy-Item -Path $src -Destination $destFile
                Write-Host "✔ Terminal settings.json copied to $wtPath" -ForegroundColor Green
            }
        }
    }
}

### === Hovedflyt === ###
Ensure-Admin
Install-PSReadLine
Install-TerminalIcons
Install-OhMyPosh

if ($IsWindows) {
    Install-NerdFont
    Copy-TerminalSettings
} else {
    Write-Warning "Skipping Windows-only steps on non-Windows host."
}

Copy-Themes-And-Profile

Write-Host "`nAll done, please restart your terminal." -ForegroundColor Magenta



#-----------------LOGGING PARAMETERS-----------------#

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO',
        [ConsoleColor]$Color
    )

    # Timestamp
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # If no explicit color, pick one by level
    if (-not $PSBoundParameters.ContainsKey('Color')) {
        switch ($Level) {
            'ERROR' { $Color = 'Red'    }
            'WARN'  { $Color = 'Yellow' }
            default { $Color = 'Green'  }
        }
    }

    # Emit with color
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $Color
}

#-----------------HELPERS-----------------#

function Update-RemoteFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    # 1) Backup existing
    if (Test-Path $DestinationPath) {
        $backupPath = "$DestinationPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Write-Log "Backing up existing file to $backupPath" 'INFO'
        Copy-Item -Path $DestinationPath -Destination $backupPath -Force
    }
    else {
        Write-Log "No existing file at $DestinationPath; skipping backup." 'WARN'
    }

    # 2) Download
    Write-Log "Downloading from $Url to $DestinationPath" 'INFO'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $DestinationPath -UseBasicParsing -ErrorAction Stop
        Write-Log "Successfully updated $DestinationPath" 'INFO'
    }
    catch {
        Write-Log "Failed to download ${Url}: $($_.Exception.Message)" 'ERROR'
        throw "Update-RemoteFile failed for $DestinationPath"
    }
}

#-----------------FETCH RELEASE-----------------#
function Get-LatestNerdFontsRelease {
    Write-Log "Fetching latest Nerd Fonts release info…" 'INFO'
    try {
        $resp = Invoke-RestMethod -Uri 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest' -UseBasicParsing
        return $resp.tag_name
    }
    catch {
        throw "Could not fetch latest Nerd Fonts release: $_"
    }
}



#-----------------INSTALL CHECK-----------------#
function Test-OhMyPoshInstalled {
    try {
        # oh-my-posh v3+ ships as an executable
        Get-Command 'oh-my-posh' -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-TerminalIconsInstalled {
    try {
        # The module ships a command named Get-FileIcon
        Get-Command -Name Get-FileIcon -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-NerdFontInstalled {
    param(
        [Parameter(Mandatory)][string]$FontName  # e.g. 'FiraCode Nerd Font'
    )
    # Check registry under HKLM 64-bit; falls back to HKCU if needed
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    foreach ($path in $regPaths) {
        if (Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties.Name -eq "$FontName (TrueType)" }) {
            return $true
        }
    }
    return $false
}

#-----------------INSTALLATION METHOD-----------------#
function Install-WithWinget {
    Write-Log "Attempting install via winget…" 'INFO' 
    try {
        winget install --id JanDeDobbeleer.OhMyPosh -e --accept-package-agreements --accept-source-agreements -h
        Write-Log "winget installation succeeded." 'INFO' 
        return $true
    }
    catch {
        Write-Log "winget install failed: $_" 'WARN' 
        return $false
    }
}

function Install-WithPSGallery {
    Write-Log "Attempting install via PowerShell Gallery module…" 'INFO'
    try {
        if (-not (Get-Module -ListAvailable -Name 'oh-my-posh')) {
            Install-Module -Name oh-my-posh -Scope CurrentUser -Force -AllowClobber
        }
        # Import so that the binary gets available
        Import-Module oh-my-posh -ErrorAction Stop
        Write-Log "PSGallery installation succeeded." 'INFO'
        return $true
    }
    catch {
        Write-Log "PSGallery install failed: $_" 'ERROR'
        return $false
    }
}

function Install-TerminalIcons {
    Write-Log "Attempting install of Terminal-Icons module from PSGallery…" 'INFO'
    try {
        if (-not (Get-Module -ListAvailable -Name 'Terminal-Icons')) {
            Install-Module -Name 'Terminal-Icons' -Scope CurrentUser -Force -AllowClobber
        }
        Import-Module 'Terminal-Icons' -ErrorAction Stop
        Write-Log "Terminal-Icons installation succeeded." 'INFO'
        return $true
    }
    catch {
        Write-Log "Failed to install Terminal-Icons: $_" 'ERROR'
        return $false
    }
}

function Install-NerdFonts {
    param(
        [Parameter(Mandatory)][string[]]$Fonts  # e.g. @('FiraCode', 'Hack')
    )

    # Ensure elevated
    if (-not ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        throw "Font installation requires elevation. Please run as Administrator."
    }

    $releaseTag = Get-LatestNerdFontsRelease
    $tmpDir = Join-Path $env:TEMP "nerd-fonts-$releaseTag"
    if (Test-Path $tmpDir) { Remove-Item $tmpDir -Recurse -Force }
    New-Item -Path $tmpDir -ItemType Directory | Out-Null

    foreach ($font in $Fonts) {
        $fontLabel = "$font Nerd Font"
        if (Test-NerdFontInstalled -FontName $fontLabel) {
            Write-Log "‘$fontLabel’ already installed. Skipping." 'INFO'
            continue
        }

        $zipName = "$font.zip"
        $url = "https://github.com/ryanoasis/nerd-fonts/releases/download/$releaseTag/$zipName"
        $zipPath = Join-Path $tmpDir $zipName

        Write-Log "Downloading $zipName from $releaseTag…" 'INFO'
        try {
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing
        }
        catch {
            Write-Log "Failed to download ${zipName}: $($_)" 'ERROR'
            continue
        }

        Write-Log "Extracting $zipName…" 'INFO'
        Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force

        # Copy all TTF/OTF files to Windows fonts folder
        $fontFiles = Get-ChildItem -Path $tmpDir -Recurse -Include "$font*.ttf","$font*.otf"
        foreach ($file in $fontFiles) {
            $destPath = Join-Path "$env:WINDIR\Fonts" $file.Name
            Write-Log "Installing font file $($file.Name)…" 'INFO'
            Copy-Item -Path $file.FullName -Destination $destPath -Force

            # Register in registry so Windows recognizes it
            $regKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
            New-ItemProperty -Path $regKey `
                             -Name "$fontLabel (TrueType)" `
                             -Value $file.Name `
                             -PropertyType String `
                             -Force | Out-Null
        }

        Write-Log "Successfully installed ‘$fontLabel’." 'INFO'
    }

    # Cleanup
    Remove-Item $tmpDir -Recurse -Force
    Write-Log "Cleaned up temporary files." 'INFO'
}

#-----------------MAIN ENTRY-----------------#
function Ensure-OhMyPosh {
    # 1) Already installed?
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Log "oh-my-posh.exe already on PATH. Skipping." 'INFO'
        return
    }

    # 2) Winget attempt
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "Installing Oh My Posh via winget…" 'INFO'
        $out = & winget install --id JanDeDobbeleer.OhMyPosh -e `
            --accept-package-agreements --accept-source-agreements -h 2>&1
        $code = $LASTEXITCODE
        Write-Log "Winget exit code: $code" 'INFO'
        Write-Log "Winget output:`n$out" 'INFO'

        Start-Sleep -Seconds 2  # allow WindowsApps registration
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            Write-Log "oh-my-posh.exe found on PATH after winget." 'INFO'
            return
        }
        else {
            Write-Log "oh-my-posh.exe still missing after winget." 'WARN'
        }
    }
    else {
        Write-Log "winget not found; skipping winget path." 'WARN'
    }

    # 3) PSGallery (module-only)
    Write-Log "Falling back to PSGallery module install…" 'INFO'
    try {
        Install-Module -Name oh-my-posh -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
        Import-Module oh-my-posh -ErrorAction Stop
        Write-Log "PSGallery oh-my-posh module installed." 'INFO'
    }
    catch {
        Write-Log "PSGallery install failed: $($_.Exception.Message)" 'ERROR'
    }

    # Check again for module cmdlets (Set-PoshPrompt etc), but no exe:
    if (Get-Command Set-PoshPrompt -ErrorAction SilentlyContinue) {
        Write-Log "Set-PoshPrompt available via module." 'INFO'
    }
    else {
        Write-Log "Set-PoshPrompt not available; module install failed." 'WARN'
    }

    # 4) Manual GitHub release fallback for the standalone binary
    Write-Log "Attempting manual download of oh-my-posh.exe from GitHub releases…" 'INFO'
    try {
        # Fetch latest tag
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest' -UseBasicParsing
        $tag     = $release.tag_name
        # Find the Windows amd64 zip asset
        $asset = $release.assets | Where-Object { $_.name -like '*windows-amd64.zip' } | Select-Object -First 1
        if (-not $asset) {
            throw "No windows-amd64.zip asset found in release $tag"
        }
        $tmpZip = Join-Path $env:TEMP $asset.name
        Write-Log "Downloading $($asset.name) from v$tag…" 'INFO'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmpZip -UseBasicParsing -ErrorAction Stop

        # Extract the exe
        $installDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh'
        $binDir     = Join-Path $installDir 'bin'
        Remove-Item $installDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -Path $binDir -ItemType Directory | Out-Null

        Expand-Archive -Path $tmpZip -DestinationPath $binDir -Force
        Remove-Item $tmpZip -Force

        # Ensure the binDir is on the current session PATH and persistently
        if (-not ($Env:Path.Split(';') -contains $binDir)) {
            Write-Log "Adding $binDir to PATH (User scope)" 'INFO'
            $newPath = ($Env:Path + ';' + $binDir).Trim(';')
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            $Env:Path = $newPath
        }

        # Final check
        if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            Write-Log "Manually downloaded oh-my-posh.exe and added to PATH." 'INFO'
            return
        }
        else {
            throw "oh-my-posh.exe still not found after manual download."
        }
    }
    catch {
        Write-Log "Manual download fallback failed: $($_.Exception.Message)" 'ERROR'
    }

    throw "Unable to install oh-my-posh via winget, PSGallery, or manual download."
}



function Ensure-TerminalIcons {
    if (Test-TerminalIconsInstalled) {
        Write-Log "Terminal-Icons is already installed. Skipping." 'INFO'
        return
    }

    Write-Log "Terminal-Icons not found. Installing…" 'INFO'

    if (Install-TerminalIcons) {
        Write-Log "Terminal-Icons is now installed and imported." 'INFO'
    }
    else {
        throw "Unable to install Terminal-Icons module."
    }
}

function Ensure-NerdFonts {
    param(
        [string[]]$Fonts = @('Hack')  # default set; modify as desired
    )
    Write-Log "Ensuring Nerd Fonts: $($Fonts -join ', ')" 'INFO'
    Install-NerdFonts -Fonts $Fonts
}

if ($MyInvocation.InvocationName -eq '.\Install-NerdFonts.ps1' -or $MyInvocation.MyCommand.Path) {
    Ensure-NerdFonts
}

$github    = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'
$themeDir  = "$env:USERPROFILE\Documents\PowerShell\PoshThemes"
$themeFile = Join-Path $themeDir 'aanestad.omp.json'

if (-not (Test-Path $themeDir)) {
    Write-Log "Creating theme directory $themeDir" 'INFO'
    New-Item -Path $themeDir -ItemType Directory | Out-Null
}

$themeUrl = "$github/theme/aanestad.omp.json"
Update-RemoteFile -Url $themeUrl -DestinationPath $themeFile


$remoteProfile = "$github/profile/Microsoft.PowerShell_profile.ps1"
$targetProfile = $Profile.CurrentUserAllHosts

$profileDir = Split-Path $targetProfile
if (-not (Test-Path $profileDir)) {
    Write-Log "Creating profile directory $profileDir" 'INFO'
    New-Item -Path $profileDir -ItemType Directory | Out-Null
}

Update-RemoteFile `
  -Url $remoteProfile `
  -DestinationPath $targetProfile

Write-Log "Replaced default profile with custom profile at:`n  $targetProfile" 'INFO'

$remoteSettings = "$github/terminal/settings.json"

$settingsDir  = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
$localSettings = Join-Path $settingsDir 'settings.json'

if (-not (Test-Path $settingsDir)) {
    Write-Log "Terminal settings directory not found; creating: $settingsDir" 'INFO'
    New-Item -Path $settingsDir -ItemType Directory | Out-Null
}

Update-RemoteFile `
    -Url $remoteSettings `
    -DestinationPath $localSettings

Write-Log "Windows Terminal settings.json updated at:`n  $localSettings" 'INFO'

#-----------------RUN THE INSTALLER-----------------#
Ensure-OhMyPosh
Ensure-TerminalIcons
Ensure-NerdFonts -Fonts @('FiraCode','Hack','Meslo')



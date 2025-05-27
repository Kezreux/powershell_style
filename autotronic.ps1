

#-----------------LOGGING PARAMETERS-----------------#

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR', 'DEBUG')][string]$Level = 'INFO',
        [ConsoleColor]$Color
    )

    # Timestamp
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # If no explicit color, pick one by level
    if (-not $PSBoundParameters.ContainsKey('Color')) {
        switch ($Level) {
            'ERROR' { $Color = 'Red'    }
            'WARN'  { $Color = 'Yellow' }
            'DEBUG' { $Color = 'Cyan'   }
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
    [CmdletBinding()]
    param()

    # Helper to add a folder to both this session's PATH and persist it for the user
    function Add-ToUserPath {
        param([string]$Folder)
        if (-not (Test-Path $Folder)) { return }
        $paths = [Environment]::GetEnvironmentVariable('Path', 'User').Split(';')
        if ($paths -notcontains $Folder) {
            # Persist for future sessions
            $new = ($paths + $Folder) -join ';'
            [Environment]::SetEnvironmentVariable('Path', $new, 'User')
        }
        # Update current session
        if ($env:Path.Split(';') -notcontains $Folder) {
            $env:Path = "$Folder;$env:Path"
        }
    }

    Write-Log "Checking for existing oh-my-posh.exe…" 'INFO'
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Log "✓ Found oh-my-posh.exe on PATH. Skipping install." 'INFO'
        return
    }

    # --- 1) Winget install attempt ---
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "✗ winget not found. Cannot install standalone exe." 'ERROR'
    }
    else {
        Write-Log "Installing/upgrading Oh My Posh via winget…" 'INFO'
        $install = winget install --id=JanDeDobbeleer.OhMyPosh -e --silent `
                    --accept-source-agreements --accept-package-agreements 2>&1
        Write-Log "Winget output:`n$install" 'DEBUG'

        # path where Winget drops the exe
        $wingetDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
        if (Test-Path (Join-Path $wingetDir 'oh-my-posh.exe')) {
            Write-Log "✓ Winget install succeeded." 'INFO'
            Add-ToUserPath $wingetDir
            return
        }
        Write-Log "✗ oh-my-posh.exe not found in $wingetDir after winget." 'WARN'
    }

    # --- 2) Fallback: Download latest GitHub release ---
    Write-Log "Attempting manual download from GitHub releases…" 'INFO'
    try {
        $api = 'https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest'
        $rel = Invoke-RestMethod -UseBasicParsing -Uri $api
        $asset = $rel.assets `
            | Where-Object { $_.name -match 'windows-amd64.exe$' } | Select-Object -First 1
        if (-not $asset) { throw 'No windows-amd64 executable found.' }

        $destDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\bin'
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        $dest = Join-Path $destDir 'oh-my-posh.exe'
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing

        if (Test-Path $dest) {
            Write-Log "✓ Downloaded oh-my-posh.exe to $destDir" 'INFO'
            Add-ToUserPath $destDir
            return
        }
        else {
            throw "Downloaded file not found at $dest"
        }
    }
    catch {
        Write-Log "✗ Manual download failed: $_" 'ERROR'
    }

    # --- 3) Final fallback to PSGallery (v3 module) ---
    Write-Log "Falling back to PSGallery module install…" 'WARN'
    # Remove any existing v3 module to avoid conflicts
    Write-Log "Cleaning up old oh-my-posh PowerShell module…" 'INFO'
    Remove-Item $env:POSH_PATH -Recurse -Force -ErrorAction SilentlyContinue
    Uninstall-Module oh-my-posh -AllVersions -ErrorAction SilentlyContinue

    if (Install-WithPSGallery) {
        Write-Log "✓ Installed oh-my-posh PowerShell module (no exe)." 'INFO'
        return
    }

    throw "Failed to install Oh My Posh via Winget, manual download, or PSGallery."
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

#-----------------SETUP THEMES AND PROFILES-----------------#

$github    = 'https://raw.githubusercontent.com/Kezreux/powershell_style/main'
$remoteProfile = "$github/profile/Microsoft.PowerShell_profile.ps1"

function Ensure-PoshTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GithubRoot,
        [Parameter()][string]$ThemeName = 'aanestad.omp.json'
    )

    $themeDir  = Join-Path $HOME 'Documents\PowerShell\PoshThemes'
    $themeFile = Join-Path $themeDir $ThemeName
    $themeUrl  = "$GithubRoot/theme/$ThemeName"

    Write-Log "Ensuring PoshTheme $ThemeName → $themeFile" 'INFO'

    if (-not (Test-Path $themeDir)) {
        Write-Log "Creating theme directory $themeDir" 'INFO'
        New-Item -Path $themeDir -ItemType Directory | Out-Null
    }

    Update-RemoteFile -Url $themeUrl -DestinationPath $themeFile
    Write-Log "PoshTheme updated at $themeFile" 'INFO'
}

function Ensure-PowerShellProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RemoteProfileUrl,

        [Parameter()]
        [string]$LocalProfilePath = $Profile.CurrentUserCurrentHost
    )

    Write-Log "Ensuring PowerShell profile at $LocalProfilePath" 'INFO'

    # Make sure the parent folder exists
    $profileDir = Split-Path $LocalProfilePath
    if (-not (Test-Path $profileDir)) {
        Write-Log "Creating profile directory $profileDir" 'INFO'
        New-Item -Path $profileDir -ItemType Directory | Out-Null
    }

    # Backup & download
    Update-RemoteFile -Url $RemoteProfileUrl -DestinationPath $LocalProfilePath

    Write-Log "Updated PowerShell profile at:`n  $LocalProfilePath" 'INFO'
}



function Ensure-WindowsTerminalSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GithubRoot,
        [Parameter()][string]$SettingsName = 'settings.json'
    )

    $settingsDir   = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState'
    $localSettings = Join-Path $settingsDir $SettingsName
    $remoteSettings= "$GithubRoot/terminal/$SettingsName"

    Write-Log "Ensuring Windows Terminal settings → $localSettings" 'INFO'

    if (-not (Test-Path $settingsDir)) {
        Write-Log "Creating Terminal settings directory $settingsDir" 'INFO'
        New-Item -Path $settingsDir -ItemType Directory | Out-Null
    }

    Update-RemoteFile -Url $remoteSettings -DestinationPath $localSettings
    Write-Log "Windows Terminal settings updated at $localSettings" 'INFO'
}


#-----------------RUN THE INSTALLER-----------------#
Ensure-OhMyPosh
Ensure-TerminalIcons
Ensure-NerdFonts -Fonts @('FiraCode','Hack','Meslo')
Ensure-PoshTheme -GithubRoot $github -ThemeName 'aanestad.omp.json'
Ensure-PowerShellProfile -RemoteProfileUrl $remoteProfile
Ensure-WindowsTerminalSettings -GithubRoot $github -SettingsName 'settings.json'

Write-Log "Installation complete! Please restart your terminal." 'INFO'



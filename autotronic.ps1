

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
            Write-Log "Failed to download $zipName: $_" 'ERROR'
            continue
        }

        Write-Log "Extracting $zipName…" 'INFO'
        Expand-Archive -Path $zipPath -DestinationPath $tmpDir

        # Copy all TTF/OTF files to Windows fonts folder
        $fontFiles = Get-ChildItem -Path $tmpDir -Recurse -Include '*.ttf','*.otf'
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
    if (Test-OhMyPoshInstalled) {
        Write-Log "Oh My Posh is already installed. Skipping." 'INFO' 
        return
    }

    Write-Log "Oh My Posh not found. Installing…" 'INFO'

    # Try winget first
    if (Get-Command 'winget' -ErrorAction SilentlyContinue) {
        if (Install-WithWinget) {
            Write-Log "Oh My Posh installation complete via winget." 'INFO'
            return
        }
    }
    else {
        Write-Log "winget not available on this system." 'WARN'
    }

    # Fallback to PowerShell Gallery
    if (Install-WithPSGallery) {
        Write-Log "Oh My Posh installation complete via PSGallery." 'INFO'
        return
    }

    throw "Failed to install Oh My Posh via both winget and PSGallery."
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
        [string[]]$Fonts = @('FiraCode','Hack')  # default set; modify as desired
    )
    Write-Log "Ensuring Nerd Fonts: $($Fonts -join ', ')" 'INFO'
    Install-NerdFonts -Fonts $Fonts
}

if ($MyInvocation.InvocationName -eq '.\Install-NerdFonts.ps1' -or $MyInvocation.MyCommand.Path) {
    Ensure-NerdFonts
}

#-----------------RUN THE INSTALLER-----------------#
Ensure-OhMyPosh
Ensure-TerminalIcons
Ensure-NerdFonts -Fonts @('FiraCode','Hack','Meslo')



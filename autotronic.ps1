

#-----------------LOGGING PARAMETERS-----------------#

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO','WARN','ERROR')] [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$timestamp] [$Level] $Message"
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

#-----------------INSTALLATION METHOD-----------------#
function Install-WithWinget {
    Write-Log "Attempting install via winget…" 'INFO' -ForegroundColor Cyan
    try {
        winget install --id JanDeDobbeleer.OhMyPosh -e --accept-package-agreements --accept-source-agreements -h
        Write-Log "winget installation succeeded." 'INFO' -ForegroundColor Green
        return $true
    }
    catch {
        Write-Log "winget install failed: $_" 'WARN' -ForegroundColor Red
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

#-----------------MAIN ENTRY-----------------#
function Ensure-OhMyPosh {
    if (Test-OhMyPoshInstalled) {
        Write-Log "Oh My Posh is already installed. Skipping." 'INFO' -ForegroundColor Red
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

#-----------------RUN THE INSTALLER-----------------#
Ensure-OhMyPosh
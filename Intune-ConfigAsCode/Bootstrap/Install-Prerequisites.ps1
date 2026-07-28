#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs the required PowerShell modules for the
    Intune Configuration-as-Code project.

.NOTES
    Version : 1.0.0
    Author  : Marquis Davis
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Installing Prerequisites" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Verify PowerShell Version
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or later is required. Current version: $($PSVersionTable.PSVersion)"
}

Write-Host "[✓] PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Host ""

# Required Microsoft Graph Modules
$RequiredModules = @(
    "Microsoft.Graph.Authentication",
    "Microsoft.Graph.DeviceManagement",
    "Microsoft.Graph.Identity.DirectoryManagement"
)

foreach ($Module in $RequiredModules) {

    Write-Host "Checking $Module..."

    if (-not (Get-Module -ListAvailable -Name $Module)) {

        Write-Host "Installing $Module..." -ForegroundColor Yellow

        Install-Module `
            -Name $Module `
            -Scope CurrentUser `
            -Repository PSGallery `
            -Force `
            -AllowClobber

        Write-Host "[+] Installed $Module" -ForegroundColor Green
    }
    else {
        Write-Host "[=] Already Installed" -ForegroundColor DarkGray
    }

    Import-Module $Module -Force
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Prerequisites Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
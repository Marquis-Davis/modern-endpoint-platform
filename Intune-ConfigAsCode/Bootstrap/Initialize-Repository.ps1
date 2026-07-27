#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Initializes the Intune Configuration-as-Code repository structure.

.DESCRIPTION
    Creates the standard folder structure and placeholder files required
    for the Intune Configuration-as-Code project.

.NOTES
    Version : 1.0.0
    Author  : Marquis Davis
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repository Root
$Root = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($Root)) {
    throw "Unable to determine repository root."
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Intune Configuration-as-Code Bootstrap" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository Root : $Root" -ForegroundColor Yellow
Write-Host ""

#------------------------------------------------------------
# Folder Structure
#------------------------------------------------------------

$Folders = @(
    "Applications",
    "Assignments",
    "CompliancePolicies",
    "ConfigurationProfiles",
    "DriverUpdates",
    "Export",
    "Export\Modules",
    "FeatureUpdates",
    "Filters",
    "Import",
    "Logs",
    "Remediations",
    "Scripts",
    "Security",
    "Security\ASR",
    "Security\BitLocker",
    "Security\Defender",
    "Security\Firewall",
    "Templates"
)

#------------------------------------------------------------
# Files
#------------------------------------------------------------

$Files = @(
    ".gitignore",
    "README.md",
    "Export\Export-Intune.ps1",
    "Import\Import-Intune.ps1"
)

#------------------------------------------------------------
# Create Folders
#------------------------------------------------------------

Write-Host "Creating folders..." -ForegroundColor Cyan
Write-Host ""

foreach ($Folder in $Folders)
{
    $Path = Join-Path -Path $Root -ChildPath $Folder

    if (Test-Path -LiteralPath $Path)
    {
        Write-Host "[=] Exists   $Folder" -ForegroundColor DarkGray
    }
    else
    {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "[+] Created  $Folder" -ForegroundColor Green
    }
}

Write-Host ""

#------------------------------------------------------------
# Create Files
#------------------------------------------------------------

Write-Host "Creating files..." -ForegroundColor Cyan
Write-Host ""

foreach ($File in $Files)
{
    $Path = Join-Path -Path $Root -ChildPath $File

    if (Test-Path -LiteralPath $Path)
    {
        Write-Host "[=] Exists   $File" -ForegroundColor DarkGray
    }
    else
    {
        New-Item -ItemType File -Path $Path -Force | Out-Null
        Write-Host "[+] Created  $File" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Repository initialization complete." -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
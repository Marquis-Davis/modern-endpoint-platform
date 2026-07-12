# ============================================================================
# Script: Initialize-ReferenceLibrary.ps1
# Purpose: Create the Modern Endpoint Platform Intune Reference Library
# ============================================================================

Clear-Host

#==============================================================================
# Determine Framework Root
#==============================================================================

if ($PSScriptRoot)
{
    $FrameworkRoot = $PSScriptRoot
}
else
{
    $FrameworkRoot = (Get-Location).Path
}

$ReferenceRoot = Join-Path $FrameworkRoot "Reference"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Creating Intune Reference Library"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Framework Root :" $FrameworkRoot -ForegroundColor Yellow
Write-Host "Reference Root :" $ReferenceRoot -ForegroundColor Yellow
Write-Host ""

#==============================================================================
# Folder Structure
#==============================================================================

$Folders = @(

    $ReferenceRoot,

    # Win32 Apps
    (Join-Path $ReferenceRoot "Win32App"),
    (Join-Path $ReferenceRoot "Win32App\Graph"),
    (Join-Path $ReferenceRoot "Win32App\Schema"),
    (Join-Path $ReferenceRoot "Win32App\Examples"),

    # WinGet
    (Join-Path $ReferenceRoot "WinGet"),
    (Join-Path $ReferenceRoot "WinGet\Graph"),
    (Join-Path $ReferenceRoot "WinGet\Schema"),

    # Microsoft Store Apps
    (Join-Path $ReferenceRoot "StoreApps"),
    (Join-Path $ReferenceRoot "StoreApps\Graph"),
    (Join-Path $ReferenceRoot "StoreApps\Schema"),

    # PowerShell Scripts
    (Join-Path $ReferenceRoot "PowerShellScripts"),
    (Join-Path $ReferenceRoot "PowerShellScripts\Graph"),
    (Join-Path $ReferenceRoot "PowerShellScripts\Schema"),

    # Proactive Remediations
    (Join-Path $ReferenceRoot "ProactiveRemediations"),
    (Join-Path $ReferenceRoot "ProactiveRemediations\Graph"),
    (Join-Path $ReferenceRoot "ProactiveRemediations\Schema"),

    # Configuration Profiles
    (Join-Path $ReferenceRoot "ConfigurationProfiles"),
    (Join-Path $ReferenceRoot "ConfigurationProfiles\Graph"),
    (Join-Path $ReferenceRoot "ConfigurationProfiles\Schema"),

    # Settings Catalog
    (Join-Path $ReferenceRoot "SettingsCatalog"),
    (Join-Path $ReferenceRoot "SettingsCatalog\Graph"),
    (Join-Path $ReferenceRoot "SettingsCatalog\Schema"),

    # Compliance Policies
    (Join-Path $ReferenceRoot "CompliancePolicies"),
    (Join-Path $ReferenceRoot "CompliancePolicies\Graph"),
    (Join-Path $ReferenceRoot "CompliancePolicies\Schema"),

    # Autopilot
    (Join-Path $ReferenceRoot "Autopilot"),
    (Join-Path $ReferenceRoot "Autopilot\Graph"),
    (Join-Path $ReferenceRoot "Autopilot\Schema"),

    # Enrollment Status Page
    (Join-Path $ReferenceRoot "EnrollmentStatusPage"),
    (Join-Path $ReferenceRoot "EnrollmentStatusPage\Graph"),
    (Join-Path $ReferenceRoot "EnrollmentStatusPage\Schema"),

    # Assignment Filters
    (Join-Path $ReferenceRoot "AssignmentFilters"),
    (Join-Path $ReferenceRoot "AssignmentFilters\Graph"),
    (Join-Path $ReferenceRoot "AssignmentFilters\Schema"),

    # Scope Tags
    (Join-Path $ReferenceRoot "ScopeTags"),
    (Join-Path $ReferenceRoot "ScopeTags\Graph"),
    (Join-Path $ReferenceRoot "ScopeTags\Schema"),

    # Administrative Templates
    (Join-Path $ReferenceRoot "AdministrativeTemplates"),
    (Join-Path $ReferenceRoot "AdministrativeTemplates\Graph"),
    (Join-Path $ReferenceRoot "AdministrativeTemplates\Schema")
)

#==============================================================================
# Create Folders
#==============================================================================

foreach ($Folder in $Folders)
{
    if (-not (Test-Path $Folder))
    {
        New-Item -ItemType Directory -Path $Folder -Force | Out-Null
        Write-Host "[Created] $Folder" -ForegroundColor Green
    }
    else
    {
        Write-Host "[Exists ] $Folder" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Reference Library Ready"
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
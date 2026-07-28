#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Exports the Intune tenant configuration.

.DESCRIPTION
    Entry point for the Intune Configuration-as-Code export process.

.NOTES
    Version : 1.0.0
    Author  : Marquis Davis
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Intune Configuration Export" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

#------------------------------------------------------------
# Verify Graph Connection
#------------------------------------------------------------

$Context = Get-MgContext

if (-not $Context) {
    throw "Not connected to Microsoft Graph. Run Bootstrap\Connect-Graph.ps1 first."
}

Write-Host "[✓] Connected to Microsoft Graph" -ForegroundColor Green
Write-Host ""

#------------------------------------------------------------
# Repository Root
#------------------------------------------------------------

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

#------------------------------------------------------------
# Load Modules
#------------------------------------------------------------

$ModulesRoot = Join-Path $PSScriptRoot "Modules"
$CommonRoot  = Join-Path $ModulesRoot "Common"

#
# Load Common helper modules first
#
if (Test-Path $CommonRoot) {

    Get-ChildItem `
        -Path $CommonRoot `
        -Filter "*.ps1" `
        -File |
        Sort-Object Name |
        ForEach-Object {

            Write-Host "Loading Common\$($_.Name)..."

            . $_.FullName
        }

    Write-Host ""
}

#
# Load Export modules
#
$ModuleFiles = Get-ChildItem `
    -Path $ModulesRoot `
    -Filter "*.ps1" `
    -File `
    -ErrorAction SilentlyContinue |
    Sort-Object Name

if ($ModuleFiles.Count -eq 0) {

    Write-Warning "No export modules found."

}
else {

    foreach ($Module in $ModuleFiles) {

        Write-Host "Loading $($Module.Name)..."

        . $Module.FullName
    }

    Write-Host ""
}

#------------------------------------------------------------
# Execute Exporters
#------------------------------------------------------------

if (Get-Command Export-ConfigurationProfiles -ErrorAction SilentlyContinue) {
    Export-ConfigurationProfiles -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-SettingsCatalog -ErrorAction SilentlyContinue) {
    Export-SettingsCatalog -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AdministrativeTemplates -ErrorAction SilentlyContinue) {
    Export-AdministrativeTemplates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-EndpointSecurity -ErrorAction SilentlyContinue) {
    Export-EndpointSecurity -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-CompliancePolicies -ErrorAction SilentlyContinue) {
    Export-CompliancePolicies -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-UpdateRings -ErrorAction SilentlyContinue) {
    Export-UpdateRings -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-FeatureUpdates -ErrorAction SilentlyContinue) {
    Export-FeatureUpdates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-DriverUpdates -ErrorAction SilentlyContinue) {
    Export-DriverUpdates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-QualityUpdates -ErrorAction SilentlyContinue) {
    Export-QualityUpdates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-PowerShellScripts -ErrorAction SilentlyContinue) {
    Export-PowerShellScripts -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-Remediations -ErrorAction SilentlyContinue) {
    Export-Remediations -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-ShellScripts -ErrorAction SilentlyContinue) {
    Export-ShellScripts -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-Win32Apps -ErrorAction SilentlyContinue) {
    Export-Win32Apps -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-MicrosoftStoreApps -ErrorAction SilentlyContinue) {
    Export-MicrosoftStoreApps -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-iOSApps -ErrorAction SilentlyContinue) {
    Export-iOSApps -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AndroidApps -ErrorAction SilentlyContinue) {
    Export-AndroidApps -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-macOSApps -ErrorAction SilentlyContinue) {
    Export-macOSApps -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AppProtectionPolicies -ErrorAction SilentlyContinue) {
    Export-AppProtectionPolicies -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AppConfigurationPolicies -ErrorAction SilentlyContinue) {
    Export-AppConfigurationPolicies -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-EnrollmentConfigurations -ErrorAction SilentlyContinue) {
    Export-EnrollmentConfigurations -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AutopilotProfiles -ErrorAction SilentlyContinue) {
    Export-AutopilotProfiles -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AutopilotDevices -ErrorAction SilentlyContinue) {
    Export-AutopilotDevices -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-ESPProfiles -ErrorAction SilentlyContinue) {
    Export-ESPProfiles -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-DeviceCategories -ErrorAction SilentlyContinue) {
    Export-DeviceCategories -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-AssignmentFilters -ErrorAction SilentlyContinue) {
    Export-AssignmentFilters -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-ScopeTags -ErrorAction SilentlyContinue) {
    Export-ScopeTags -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-RoleDefinitions -ErrorAction SilentlyContinue) {
    Export-RoleDefinitions -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-RoleAssignments -ErrorAction SilentlyContinue) {
    Export-RoleAssignments -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-TermsAndConditions -ErrorAction SilentlyContinue) {
    Export-TermsAndConditions -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-DeviceHealthScripts -ErrorAction SilentlyContinue) {
    Export-DeviceHealthScripts -RepositoryRoot $RepositoryRoot
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Export Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$Stopwatch.Stop()

Write-Host ""
Write-Host "Completed in $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Yellow
Write-Host ""
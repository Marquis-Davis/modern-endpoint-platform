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

$Exporters = @(
    'Export-ConfigurationProfiles',
    'Export-SettingsCatalog',
    'Export-AdministrativeTemplates',
    'Export-EndpointSecurity',
    'Export-CompliancePolicies',
    'Export-UpdateRings',
    'Export-FeatureUpdates',
    'Export-DriverUpdates',
    'Export-QualityUpdates',
    'Export-PowerShellScripts',
    'Export-Remediations',
    'Export-ShellScripts',
    'Export-Win32Apps',
    'Export-MicrosoftStoreApps',
    'Export-iOSApps',
    'Export-AndroidApps',
    'Export-macOSApps',
    'Export-AppProtectionPolicies',
    'Export-AppConfigurationPolicies',
    'Export-EnrollmentConfigurations',
    'Export-AutopilotProfiles',
    'Export-AutopilotDevices',
    'Export-ESPProfiles',
    'Export-DeviceCategories',
    'Export-AssignmentFilters',
    'Export-ScopeTags',
    'Export-RoleDefinitions',
    'Export-RoleAssignments',
    'Export-TermsAndConditions'
)

$MissingExporters = @($Exporters | Where-Object {
    -not (Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue)
})

if ($MissingExporters.Count -gt 0) {
    throw "Required exporter function(s) were not loaded: $($MissingExporters -join ', ')"
}

foreach ($Exporter in $Exporters) {
    & $Exporter -RepositoryRoot $RepositoryRoot
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Export Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$Stopwatch.Stop()

Write-Host ""
Write-Host "Completed in $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Yellow
Write-Host ""

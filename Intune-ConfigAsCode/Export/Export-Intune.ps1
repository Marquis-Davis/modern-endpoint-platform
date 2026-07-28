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
# Load Export Modules
#------------------------------------------------------------

$ExportModules = Join-Path $PSScriptRoot "Modules"

$ModuleFiles = @(Get-ChildItem `
    -Path $ExportModules `
    -Filter "*.ps1" `
    -ErrorAction SilentlyContinue |
    Sort-Object Name)

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

if (Get-Command Export-UpdateRings -ErrorAction SilentlyContinue) {
    Export-UpdateRings -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-FeatureUpdates -ErrorAction SilentlyContinue) {
    Export-FeatureUpdates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-DriverUpdates -ErrorAction SilentlyContinue) {
    Export-DriverUpdates -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-CompliancePolicies -ErrorAction SilentlyContinue) {
    Export-CompliancePolicies -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-PowerShellScripts -ErrorAction SilentlyContinue) {
    Export-PowerShellScripts -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-Remediations -ErrorAction SilentlyContinue) {
    Export-Remediations -RepositoryRoot $RepositoryRoot
}

if (Get-Command Export-EndpointSecurity -ErrorAction SilentlyContinue) {
    Export-EndpointSecurity -RepositoryRoot $RepositoryRoot
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Export Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green

$Stopwatch.Stop()

Write-Host ""
Write-Host "Completed in $($Stopwatch.Elapsed.ToString('mm\:ss\.fff'))" -ForegroundColor Yellow
Write-Host ""



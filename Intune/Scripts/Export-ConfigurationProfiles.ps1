<#
.SYNOPSIS
    Exports all Microsoft Intune Configuration Profiles to JSON.

.DESCRIPTION
    Connects to Microsoft Graph, retrieves all Intune Configuration Profiles,
    and exports each profile as an individual JSON file.

.NOTES
    Project: Modern Endpoint Platform
    Author: Your Name
#>

[CmdletBinding()]
param(
    [string]$ExportPath = "C:\modern-endpoint-platform\Intune\ConfigurationProfiles"
)

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All" -NoWelcome

Write-Host "Retrieving Configuration Profiles..." -ForegroundColor Cyan

$Profiles = (
    Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"
).value

if (-not $Profiles) {
    Write-Warning "No Configuration Profiles were found."
    return
}

if (!(Test-Path $ExportPath)) {
    New-Item -ItemType Directory -Path $ExportPath | Out-Null
}

foreach ($Profile in $Profiles) {

    $FileName = $Profile.name -replace '[\\/:*?"<>|]', '_'
    $OutputFile = Join-Path $ExportPath "$FileName.json"

    $Profile |
        ConvertTo-Json -Depth 100 |
        Set-Content -Path $OutputFile -Encoding UTF8

    Write-Host "Exported: $($Profile.name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Export complete." -ForegroundColor Cyan
Write-Host "Location: $ExportPath"
Write-Host "Profiles exported: $($Profiles.Count)"
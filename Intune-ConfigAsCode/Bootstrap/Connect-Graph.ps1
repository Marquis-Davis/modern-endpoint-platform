#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Connects to Microsoft Graph for the
    Intune Configuration-as-Code project.

.DESCRIPTION
    Authenticates the current user and verifies
    the required Microsoft Graph scopes.

.NOTES
    Version : 1.0.0
    Author  : Marquis Davis
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Connecting to Microsoft Graph" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw "Microsoft.Graph.Authentication is not installed. Run Install-Prerequisites.ps1 first."
}

Import-Module Microsoft.Graph.Authentication -Force

# Required Microsoft Graph scopes
$Scopes = @(
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Group.Read.All",
    "Policy.Read.All"
)

Write-Host "Connecting..." -ForegroundColor Cyan

Connect-MgGraph `
    -Scopes $Scopes `
    -NoWelcome

# Verify connection
$Context = Get-MgContext

if (-not $Context) {
    throw "Failed to connect to Microsoft Graph."
}

Write-Host ""
Write-Host "[✓] Connected Successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Tenant       : $($Context.TenantId)" -ForegroundColor Yellow
Write-Host "Account      : $($Context.Account)" -ForegroundColor Yellow
Write-Host "Environment  : $($Context.Environment)" -ForegroundColor Yellow
Write-Host "Auth Type    : $($Context.AuthType)" -ForegroundColor Yellow

Write-Host ""
Write-Host "Granted Scopes:" -ForegroundColor Cyan

foreach ($Scope in ($Context.Scopes | Sort-Object)) {
    Write-Host "  • $Scope"
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Microsoft Graph Connected" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
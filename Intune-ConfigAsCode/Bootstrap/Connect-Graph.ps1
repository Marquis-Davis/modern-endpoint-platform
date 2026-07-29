#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Connects to Microsoft Graph for the Intune Configuration-as-Code project.

.DESCRIPTION
    Authenticates using Interactive login, App Registration (Certificate/Secret), 
    or Azure Managed Identity depending on the passed parameters.

.NOTES
    Version : 2.0.0
    Author  : Marquis Davis
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Interactive')]
    [Parameter(ParameterSetName = 'AppRegistration')]
    [Parameter(ParameterSetName = 'ManagedIdentity')]
    [ValidateSet('Interactive', 'AppRegistration', 'ManagedIdentity')]
    [string]$AuthMethod = 'Interactive',

    [Parameter(Mandatory = $true, ParameterSetName = 'AppRegistration')]
    [string]$TenantId,

    [Parameter(Mandatory = $true, ParameterSetName = 'AppRegistration')]
    [string]$ClientId,

    [Parameter(Mandatory = $false, ParameterSetName = 'AppRegistration')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false, ParameterSetName = 'AppRegistration')]
    [securestring]$ClientSecret,

    [Parameter(Mandatory = $false, ParameterSetName = 'ManagedIdentity')]
    [string]$ManagedIdentityClientId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Connecting to Microsoft Graph ($AuthMethod)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure authentication module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
    throw "Microsoft.Graph.Authentication is not installed. Run Install-Prerequisites.ps1 first."
}

Import-Module Microsoft.Graph.Authentication -Force

# Required Delegated Scopes (Only used during Interactive Auth)
$DelegatedScopes = @(
    "DeviceManagementApps.ReadWrite.All",
    "DeviceManagementConfiguration.ReadWrite.All",
    "DeviceManagementManagedDevices.Read.All",
    "DeviceManagementServiceConfig.ReadWrite.All",
    "Group.Read.All",
    "Policy.Read.All",
    "DeviceManagementScripts.Read.All",
    "DeviceManagementManagedDevices.ReadWrite.All"
)

Write-Host "Connecting via $AuthMethod..." -ForegroundColor Cyan

switch ($AuthMethod) {
    'Interactive' {
        # Developer local testing in VS Code
        Connect-MgGraph -Scopes $DelegatedScopes -NoWelcome
    }

    'AppRegistration' {
        # Automation via GitHub Actions / Azure DevOps using App Registration
        if ($CertificateThumbprint) {
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -NoWelcome
        }
        elseif ($ClientSecret) {
            $Credential = [System.Management.Automation.PSCredential]::new($ClientId, $ClientSecret)
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -ClientSecret $Credential -NoWelcome
        }
        else {
            throw "You must supply either -CertificateThumbprint or -ClientSecret when using AppRegistration auth."
        }
    }

    'ManagedIdentity' {
        # Automation running inside Azure (Automation Accounts / VMs / Azure Functions)
        if ($ManagedIdentityClientId) {
            Connect-MgGraph -Identity -ClientId $ManagedIdentityClientId -NoWelcome
        }
        else {
            Connect-MgGraph -Identity -NoWelcome
        }
    }
}

# Verify connection context
$Context = Get-MgContext

if (-not $Context) {
    throw "Failed to connect to Microsoft Graph."
}

Write-Host ""
Write-Host "[✓] Connected Successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Tenant       : $($Context.TenantId)" -ForegroundColor Yellow
Write-Host "Account/App  : $($Context.Account)" -ForegroundColor Yellow
Write-Host "Environment  : $($Context.Environment)" -ForegroundColor Yellow
Write-Host "Auth Type    : $($Context.AuthType)" -ForegroundColor Yellow

if ($Context.AuthType -eq 'Delegated') {
    Write-Host ""
    Write-Host "Granted Scopes:" -ForegroundColor Cyan
    foreach ($Scope in ($Context.Scopes | Sort-Object)) {
        Write-Host "  • $Scope"
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " Microsoft Graph Connected" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
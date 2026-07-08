param(
    [Parameter(Mandatory)]
    [string]$Application
)

#============================================================
# Load Modules
#============================================================

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Groups -ErrorAction Stop
Import-Module IntuneWin32App -ErrorAction Stop

. "$PSScriptRoot\Modules\Publish-Win32App.ps1"

Clear-Host

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " Publishing $Application" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

#============================================================
# Repository
#============================================================

$RepositoryRoot = Split-Path $PSScriptRoot -Parent
$ApplicationFolder = Join-Path $RepositoryRoot "Applications\$Application"

$Manifest = Join-Path $ApplicationFolder "app.json"
$Package  = Join-Path $ApplicationFolder "Package\Install.intunewin"

Write-Host "Repository Root : $RepositoryRoot"
Write-Host "Application     : $Application"
Write-Host "ApplicationFolder: $ApplicationFolder"
Write-Host ""

#============================================================
# Validation
#============================================================

if (!(Test-Path $Manifest)) {
    throw "Unable to locate manifest: $Manifest"
}

if (!(Test-Path $Package)) {
    throw "Unable to locate package: $Package"
}

#============================================================
# Read Manifest
#============================================================

$App = Get-Content $Manifest -Raw | ConvertFrom-Json

Write-Host "Application : $($App.Application.Name)"
Write-Host "Publisher   : $($App.Application.Publisher)"
Write-Host "Version     : $($App.Application.Version)"
Write-Host "Category    : $($App.Application.Category)"
Write-Host "Intent      : $($App.Deployment.Intent)"
Write-Host "Group       : $($App.Deployment.AssignmentGroup)"
Write-Host ""

#============================================================
# Connect Microsoft Graph
#============================================================

$env:AZURE_IDENTITY_DISABLE_WAM = "true"

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow

Connect-MgGraph `
    -Scopes @(
        "DeviceManagementApps.ReadWrite.All",
        "Group.Read.All"
    ) `
    -ContextScope Process `
    -NoWelcome

Write-Host "Connected Graph: $((Get-MgContext).Account)" -ForegroundColor Green
Write-Host ""

#============================================================
# Connect IntuneWin32App Module
#============================================================

Write-Host "Connecting IntuneWin32App..." -ForegroundColor Yellow

$TenantID = (Get-MgContext).TenantId
$ClientID = (Get-MgContext).ClientId


Connect-MSIntuneGraph `
    -TenantID $TenantID `
    -ClientID $ClientID `
    -Interactive

Write-Host "Connected IntuneWin32App." -ForegroundColor Green
Write-Host ""

#============================================================
# Lookup Deployment Group
#============================================================

Write-Host "Looking up deployment group..." -ForegroundColor Yellow

$DeploymentGroup = Get-MgGroup -All |
    Where-Object DisplayName -eq $App.Deployment.AssignmentGroup

if (-not $DeploymentGroup) {
    throw "Deployment group '$($App.Deployment.AssignmentGroup)' not found."
}

Write-Host ""
Write-Host "Deployment Group"
Write-Host "----------------"
Write-Host "Name      : $($DeploymentGroup.DisplayName)"
Write-Host "Object ID : $($DeploymentGroup.Id)"
Write-Host ""

#============================================================
# Publish
#============================================================

Publish-Win32App `
    -Manifest $App `
    -ApplicationFolder $ApplicationFolder `
    -Package $Package `
    -DeploymentGroup $DeploymentGroup
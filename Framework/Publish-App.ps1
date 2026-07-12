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

$RepositoryRoot    = Split-Path $PSScriptRoot -Parent
$ApplicationFolder = Join-Path $RepositoryRoot "Applications\$Application"

$Manifest = Join-Path $ApplicationFolder "app.json"

$Package = Get-ChildItem `
    -Path (Join-Path $ApplicationFolder "Package") `
    -Filter *.intunewin |
    Select-Object -First 1

if (-not $Package)
{
    throw "Unable to locate a .intunewin package in '$ApplicationFolder\Package'."
}

$Package = $Package.FullName

Write-Host "Repository Root  : $RepositoryRoot"
Write-Host "Application      : $Application"
Write-Host "ApplicationFolder: $ApplicationFolder"
Write-Host ""

#============================================================
# Validation
#============================================================

if (!(Test-Path $Manifest))
{
    throw "Unable to locate manifest: $Manifest"
}

if (!(Test-Path $Package))
{
    throw "Unable to locate package: $Package"
}

#============================================================
# Read Manifest
#============================================================

$App = Get-Content $Manifest -Raw | ConvertFrom-Json

# Automatically generate deployment group name
$GroupName = "APP-$($App.Application.Name)-$($App.Deployment.Intent)"

Write-Host "Application : $($App.Application.Name)"
Write-Host "Publisher   : $($App.Application.Publisher)"
Write-Host "Version     : $($App.Application.Version)"
Write-Host "Category    : $($App.Application.Category)"
Write-Host "Intent      : $($App.Deployment.Intent)"
Write-Host "Group       : $GroupName"
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
# Connect IntuneWin32App
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
# Lookup / Create Deployment Group
#============================================================

Write-Host "Looking up deployment group..." -ForegroundColor Yellow

$DeploymentGroup = Get-MgGroup `
    -Filter "displayName eq '$GroupName'" `
    -ConsistencyLevel eventual

if (-not $DeploymentGroup)
{
    Write-Host "Group not found. Creating '$GroupName'..." -ForegroundColor Yellow

    $DeploymentGroup = New-MgGroup `
        -DisplayName $GroupName `
        -MailEnabled:$false `
        -MailNickname ($GroupName -replace '[^a-zA-Z0-9]', '') `
        -SecurityEnabled:$true

    Write-Host "Group created." -ForegroundColor Green
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
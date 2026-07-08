param(
    [Parameter(Mandatory)]
    [string]$Application
)

Write-Host ""
Write-Host "=========================="
Write-Host " Publishing $Application"
Write-Host "=========================="
Write-Host ""

# Repository

$RepositoryRoot = Split-Path $PSScriptRoot -Parent

$ApplicationFolder = Join-Path $RepositoryRoot "Applications\$Application"

$Manifest = Join-Path $ApplicationFolder "app.json"

$Package = Join-Path $ApplicationFolder "Package\Install.intunewin"

if (!(Test-Path $Manifest))
{
    throw "Unable to locate app.json"
}

if (!(Test-Path $Package))
{
    throw "Unable to locate Install.intunewin"
}

$App = Get-Content $Manifest -Raw | ConvertFrom-Json

Write-Host "Application : $($App.Application.Name)"
Write-Host "Publisher   : $($App.Application.Publisher)"
Write-Host "Version     : $($App.Application.Version)"
Write-Host "Category    : $($App.Application.Category)"
Write-Host "Ring        : $($App.Deployment.Ring)"

Write-Host ""
Write-Host "Package"
Write-Host "-------"
Write-Host $Package
Write-Host ""

# Connect to Microsoft Graph

Write-Host ""
Write-Host "Connecting to Microsoft Graph..."
Write-Host ""

$env:AZURE_IDENTITY_DISABLE_WAM = "true"

Connect-MgGraph `
    -Scopes @(
        "DeviceManagementApps.ReadWrite.All"
        "Group.Read.All"
    ) `
    -ContextScope Process `
    -NoWelcome
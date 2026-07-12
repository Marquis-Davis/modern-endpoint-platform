param(
    [Parameter(Mandatory)]
    [string]$Application
)

# Banner

Write-Host ""
Write-Host "=========================="
Write-Host " Building $Application"
Write-Host "=========================="
Write-Host ""

# Repository

$RepositoryRoot   = Split-Path $PSScriptRoot -Parent
$ApplicationFolder = Join-Path $RepositoryRoot "Applications\$Application"
$Manifest          = Join-Path $ApplicationFolder "app.json"

if (!(Test-Path $Manifest))
{
    throw "Unable to locate $Manifest"
}

# Read Manifest

$App = Get-Content $Manifest -Raw | ConvertFrom-Json

# Validate

$SourceFolder  = Join-Path $ApplicationFolder $App.Source.SourceFolder
$PackageFolder = Join-Path $ApplicationFolder $App.Source.PackageFolder
$SetupFile = Join-Path $SourceFolder $App.Source.SetupFile

Write-Host "Validating application structure..."

if (!(Test-Path $SourceFolder))
{
    throw "Source folder not found: $SourceFolder"
}

if (!(Test-Path $PackageFolder))
{
    New-Item -ItemType Directory -Path $PackageFolder | Out-Null
    Write-Host "Created Package folder."
}

if (!(Test-Path $SetupFile))
{
    throw "Setup file not found: $SetupFile"
}

Write-Host ""
Write-Host "Validation complete."
Write-Host ""

# Application Information

Write-Host "Application : $($App.Application.Name)"
Write-Host "Publisher   : $($App.Application.Publisher)"
Write-Host "Version     : $($App.Application.Version)"
Write-Host "Category    : $($App.Application.Category)"
Write-Host "Intent      : $($App.Deployment.Intent)"
Write-Host "Group       : $($App.Deployment.AssignmentGroup)"

# Locate Tools

$ToolsFolder = Join-Path $RepositoryRoot "Tools\Microsoft-Win32-Content-Prep-Tool-master"
$IntuneWinAppUtil = Join-Path $ToolsFolder "IntuneWinAppUtil.exe"

if (!(Test-Path $IntuneWinAppUtil))
{
    throw "Unable to locate IntuneWinAppUtil.exe"
}

# Package the application
# Build Package

$OutputFile = Get-ChildItem $PackageFolder -Filter *.intunewin |
    Select-Object -First 1

if (-not $OutputFile)
{
    throw "Package creation failed."
}

Write-Host ""
Write-Host "Package created successfully!" -ForegroundColor Green
Write-Host "Output: $($OutputFile.FullName)"

Write-Host ""
Write-Host "Packaging application..."
Write-Host ""
Write-Host "Source Folder : $SourceFolder"
Write-Host "Setup File    : $($App.Source.SetupFile)"
Write-Host "Output Folder : $PackageFolder"
Write-Host "Full Setup    : $SetupFile"
Write-Host ""
& $IntuneWinAppUtil `
    -c $SourceFolder `
    -s $App.Source.SetupFile `
    -o $PackageFolder `
    -q

    # Verify 
    if (!(Test-Path $OutputFile))
{
    throw "Package creation failed."
}

Write-Host ""
Write-Host "Package created successfully!"
Write-Host "Output: $OutputFile"
Write-Host ""
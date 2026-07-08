param(
    [Parameter(Mandatory)]
    [string]$Name
)

$RepositoryRoot = Split-Path $PSScriptRoot -Parent

$TemplateFolder = Join-Path $RepositoryRoot "Applications\Template"
$NewAppFolder   = Join-Path $RepositoryRoot "Applications\$Name"

if (!(Test-Path $TemplateFolder))
{
    throw "Template folder not found: $TemplateFolder"
}

if (Test-Path $NewAppFolder)
{
    throw "Application '$Name' already exists."
}

Write-Host ""
Write-Host "Creating application..." -ForegroundColor Yellow

Copy-Item `
    -Path $TemplateFolder `
    -Destination $NewAppFolder `
    -Recurse

Write-Host "Created:"
Write-Host "  $NewAppFolder"

#----------------------------------------------------
# Update app.json
#----------------------------------------------------

$Manifest = Join-Path $NewAppFolder "app.json"

if (Test-Path $Manifest)
{
    $Json = Get-Content $Manifest -Raw | ConvertFrom-Json

    $Json.Application.Name = $Name

    $Json | ConvertTo-Json -Depth 20 |
        Set-Content $Manifest -Encoding UTF8

    Write-Host "Updated app.json"
}

#----------------------------------------------------
# Create Package folder
#----------------------------------------------------

$Package = Join-Path $NewAppFolder "Package"

if (!(Test-Path $Package))
{
    New-Item `
        -ItemType Directory `
        -Path $Package | Out-Null
}

#----------------------------------------------------
# Create Source folder
#----------------------------------------------------

$Source = Join-Path $NewAppFolder "Source"

if (!(Test-Path $Source))
{
    New-Item `
        -ItemType Directory `
        -Path $Source | Out-Null
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green

Invoke-Item $NewAppFolder
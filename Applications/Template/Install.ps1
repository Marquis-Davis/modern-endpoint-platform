# ============================================================================
# Generic Install Script
# ============================================================================

$Manifest = Get-Content (Join-Path $PSScriptRoot "app.json") -Raw | ConvertFrom-Json

$Installer = Join-Path $PSScriptRoot ("Source\" + $Manifest.Source.SetupFile)

if (!(Test-Path $Installer))
{
    throw "The installer not found: $Installer"
}

Write-Host "Installing $($Manifest.Application.Name)..."

Start-Process `
    -FilePath $Installer `
    -Wait

exit $LASTEXITCODE
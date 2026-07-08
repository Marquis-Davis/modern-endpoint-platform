# ============================================================================
# Generic Uninstall Script
# ============================================================================

$Manifest = Get-Content (Join-Path $PSScriptRoot "app.json") -Raw | ConvertFrom-Json

$Application = $Manifest.Application.Name
$Uninstaller = Join-Path $PSScriptRoot ("Source\" + $Manifest.Install.UninstallFile)

Write-Host "Uninstalling $Application..."

if (!(Test-Path $Uninstaller))
{
    throw "Uninstaller not found: $Uninstaller"
}

Start-Process `
    -FilePath $Uninstaller `
    -ArgumentList $Manifest.Install.UninstallArguments `
    -Wait `
    -NoNewWindow

exit $LASTEXITCODE
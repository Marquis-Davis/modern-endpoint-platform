param(
    [Parameter(Mandatory)]
    [string]$Application
)

$RepoRoot = Split-Path $PSScriptRoot -Parent

$AppRoot = Join-Path $RepoRoot "Applications\$Application"

$Tool = Join-Path $RepoRoot "Tools\IntuneWinAppUtil.exe"

$Output = Join-Path $AppRoot "Package"

$Setup = "Scripts\Install.ps1"

Write-Host ""
Write-Host "Building $Application..."
Write-Host ""

& $Tool `
    -c $AppRoot `
    -s $Setup `
    -o $Output `
    -q

Write-Host ""
Write-Host "Done."
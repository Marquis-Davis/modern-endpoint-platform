# ============================================================================
# Application : CMTrace
# Purpose     : Install CMTrace
# Author      : Your Name
# ============================================================================

$Source = Join-Path $PSScriptRoot "..\Source\CMTrace.exe"
$Destination = "$env:ProgramFiles\CMTrace.exe"

Write-Host "Installing CMTrace..."

Copy-Item `
    -Path $Source `
    -Destination $Destination `
    -Force

Write-Host "Installation Complete."

exit 0
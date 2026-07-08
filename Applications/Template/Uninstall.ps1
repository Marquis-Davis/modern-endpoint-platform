# ============================================================================
# Application : CMTrace
# Purpose     : Uninstall CMTrace
# ============================================================================

$Destination = "$env:ProgramFiles\CMTrace.exe"

Write-Host "Removing CMTrace..."

if (Test-Path $Destination)
{
    Remove-Item $Destination -Force
}

Write-Host "Removal Complete."

exit 0
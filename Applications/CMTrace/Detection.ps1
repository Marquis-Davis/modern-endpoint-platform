# ============================================================================
# Application : CMTrace
# Purpose     : Detection Script
# ============================================================================

$Destination = "$env:ProgramFiles\CMTrace.exe"

if (Test-Path $Destination)
{
    Write-Output "Installed"
    exit 0
}

exit 1
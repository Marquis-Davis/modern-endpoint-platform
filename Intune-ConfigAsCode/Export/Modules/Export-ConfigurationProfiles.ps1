function Export-ConfigurationProfiles {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Configuration Profiles..." -ForegroundColor Cyan
}
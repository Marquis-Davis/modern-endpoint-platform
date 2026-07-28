function Export-ConfigurationProfiles {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Configuration Profiles..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "ConfigurationProfiles"

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations"

    $Count = 0

    foreach ($Policy in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Policy.displayName)) {
            $Policy.id
        }
        else {
            $Policy.displayName
        }

        # Create a safe filename
        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Policy.PSObject.Properties.Remove('@odata.context')
        $Policy.PSObject.Properties.Remove('@odata.type')

        # Save JSON
        $Json = $Policy | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Configuration Profile(s)." -ForegroundColor Green
    Write-Host ""
}
function Export-EndpointSecurity {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Endpoint Security Policies..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Security"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"

    $Count = 0

    #
    # We'll determine the correct filter after we inspect
    # what your tenant returns.
    #

foreach ($Policy in $Response.value) {

    $Name = if ([string]::IsNullOrWhiteSpace($Policy.name)) {
        $Policy.id
    }
    else {
        $Policy.name
    }

    $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

    # Remove Graph metadata
    $Policy.PSObject.Properties.Remove('@odata.context')
    $Policy.PSObject.Properties.Remove('@odata.type')

    $Json = $Policy | ConvertTo-Json -Depth 100

    $File = Join-Path $ExportPath "$SafeName.json"

    $Json | Set-Content `
        -Path $File `
        -Encoding UTF8

    Write-Host "   [+] $SafeName" -ForegroundColor Green

    $Count++
}

    Write-Host ""
    Write-Host "Discovered $Count Configuration Polic(ies)." -ForegroundColor Green
    Write-Host ""
}
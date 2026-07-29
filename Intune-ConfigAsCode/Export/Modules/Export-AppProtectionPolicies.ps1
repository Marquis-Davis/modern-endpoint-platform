function Export-AppProtectionPolicies {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting App Protection Policies..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "AppProtectionPolicies"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Uris = @(
        "https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections",
        "https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections",
        "https://graph.microsoft.com/beta/deviceAppManagement/windowsManagedAppProtections",
        "https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies"
    )

    $Count = 0

    foreach ($Uri in $Uris) {

        $Response = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $Uri

        foreach ($Policy in $Response.value) {

            $Name = if ([string]::IsNullOrWhiteSpace($Policy.displayName)) {
                $Policy.id
            }
            else {
                $Policy.displayName
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
    }

    Write-Host ""
    Write-Host "Exported $Count App Protection Policy(s)." -ForegroundColor Green
    Write-Host ""
}
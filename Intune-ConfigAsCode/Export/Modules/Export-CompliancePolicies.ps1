function Export-CompliancePolicies {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Compliance Policies..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "CompliancePolicies"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies"

    $Count = 0

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

    Write-Host ""
    Write-Host "Exported $Count Compliance Policy(s)." -ForegroundColor Green
    Write-Host ""
}
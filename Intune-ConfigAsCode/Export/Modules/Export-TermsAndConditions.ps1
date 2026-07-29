function Export-TermsAndConditions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Terms and Conditions..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "TermsAndConditions"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/termsAndConditions"

    $Count = 0

    foreach ($Terms in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Terms.displayName)) {
            $Terms.id
        }
        else {
            $Terms.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Terms.PSObject.Properties.Remove('@odata.context')
        $Terms.PSObject.Properties.Remove('@odata.type')

        $Json = $Terms | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Terms and Condition(s)." -ForegroundColor Green
    Write-Host ""
}
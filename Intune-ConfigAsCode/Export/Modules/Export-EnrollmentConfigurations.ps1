function Export-EnrollmentConfigurations {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Enrollment Configurations..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "EnrollmentConfigurations"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations"

    $Count = 0

    foreach ($Configuration in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Configuration.displayName)) {
            $Configuration.id
        }
        else {
            $Configuration.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Configuration.PSObject.Properties.Remove('@odata.context')
        $Configuration.PSObject.Properties.Remove('@odata.type')

        $Json = $Configuration | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Enrollment Configuration(s)." -ForegroundColor Green
    Write-Host ""
}
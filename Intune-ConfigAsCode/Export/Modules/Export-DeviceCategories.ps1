function Export-DeviceCategories {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Device Categories..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "DeviceCategories"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCategories"

    $Count = 0

    foreach ($Category in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Category.displayName)) {
            $Category.id
        }
        else {
            $Category.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Category.PSObject.Properties.Remove('@odata.context')
        $Category.PSObject.Properties.Remove('@odata.type')

        $Json = $Category | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Device Categor$(if ($Count -eq 1) {'y'} else {'ies'})." -ForegroundColor Green
    Write-Host ""
}
function Export-MicrosoftStoreApps {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Microsoft Store Apps..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Applications\MicrosoftStore"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

    $StoreApps = $Response.value | Where-Object {
        $_.'@odata.type' -eq "#microsoft.graph.microsoftStoreForBusinessApp" -or
        $_.'@odata.type' -eq "#microsoft.graph.winGetApp"
    }

    $Count = 0

    foreach ($App in $StoreApps) {

        $Name = if ([string]::IsNullOrWhiteSpace($App.displayName)) {
            $App.id
        }
        else {
            $App.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $App.PSObject.Properties.Remove('@odata.context')
        $App.PSObject.Properties.Remove('@odata.type')

        $Json = $App | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Microsoft Store App(s)." -ForegroundColor Green
    Write-Host ""
}
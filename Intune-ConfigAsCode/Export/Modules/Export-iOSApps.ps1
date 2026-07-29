function Export-iOSApps {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting iOS Apps..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Applications\iOS"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

    $iOSApps = $Response.value | Where-Object {
        $_.'@odata.type' -in @(
            "#microsoft.graph.iosStoreApp",
            "#microsoft.graph.iosLobApp",
            "#microsoft.graph.managedIOSStoreApp",
            "#microsoft.graph.managedMobileLobApp"
        )
    }

    $Count = 0

    foreach ($App in $iOSApps) {

        $Name = if ([string]::IsNullOrWhiteSpace($App.displayName)) {
            $App.id
        }
        else {
            $App.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

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
    Write-Host "Exported $Count iOS App(s)." -ForegroundColor Green
    Write-Host ""
}
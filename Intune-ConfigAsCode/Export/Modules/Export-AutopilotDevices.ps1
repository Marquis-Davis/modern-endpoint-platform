function Export-AutopilotDevices {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Autopilot Devices..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Autopilot\Devices"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"

    $Count = 0

    foreach ($Device in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Device.serialNumber)) {
            $Device.id
        }
        else {
            $Device.serialNumber
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Device.PSObject.Properties.Remove('@odata.context')
        $Device.PSObject.Properties.Remove('@odata.type')

        $Json = $Device | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Autopilot Device(s)." -ForegroundColor Green
    Write-Host ""
}
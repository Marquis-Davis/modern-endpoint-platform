function Export-Win32Apps {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Win32 Apps..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Applications\Win32"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"

    $Win32Apps = $Response.value | Where-Object {
        $_.'@odata.type' -eq "#microsoft.graph.win32LobApp"
    }

    $Count = 0

    foreach ($App in $Win32Apps) {

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
    Write-Host "Exported $Count Win32 App(s)." -ForegroundColor Green
    Write-Host ""
}
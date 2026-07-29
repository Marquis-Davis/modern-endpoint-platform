function Export-RoleDefinitions {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Role Definitions..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "RBAC\RoleDefinitions"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions"

    $Count = 0

    foreach ($Role in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Role.displayName)) {
            $Role.id
        }
        else {
            $Role.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Role.PSObject.Properties.Remove('@odata.context')
        $Role.PSObject.Properties.Remove('@odata.type')

        $Json = $Role | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Role Definition(s)." -ForegroundColor Green
    Write-Host ""
}
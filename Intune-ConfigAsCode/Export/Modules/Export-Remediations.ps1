function Export-Remediations {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Remediations..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "Remediations"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts"

    $Count = 0

    foreach ($Script in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Script.displayName)) {
            $Script.id
        }
        else {
            $Script.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Script.PSObject.Properties.Remove('@odata.context')
        $Script.PSObject.Properties.Remove('@odata.type')

        $Json = $Script | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Remediation(s)." -ForegroundColor Green
    Write-Host ""
}
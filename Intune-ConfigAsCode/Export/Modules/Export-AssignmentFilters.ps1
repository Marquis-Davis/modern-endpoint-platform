function Export-AssignmentFilters {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Assignment Filters..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "AssignmentFilters"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"

    $Count = 0

    foreach ($Filter in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($Filter.displayName)) {
            $Filter.id
        }
        else {
            $Filter.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Filter.PSObject.Properties.Remove('@odata.context')
        $Filter.PSObject.Properties.Remove('@odata.type')

        $Json = $Filter | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Assignment Filter(s)." -ForegroundColor Green
    Write-Host ""
}
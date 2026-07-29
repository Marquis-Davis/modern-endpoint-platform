function Export-ScopeTags {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Scope Tags..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "ScopeTags"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/roleScopeTags"

    $Count = 0

    foreach ($ScopeTag in $Response.value) {

        $Name = if ([string]::IsNullOrWhiteSpace($ScopeTag.displayName)) {
            $ScopeTag.id
        }
        else {
            $ScopeTag.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $ScopeTag.PSObject.Properties.Remove('@odata.context')
        $ScopeTag.PSObject.Properties.Remove('@odata.type')

        $Json = $ScopeTag | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Scope Tag(s)." -ForegroundColor Green
    Write-Host ""
}
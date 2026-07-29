function Export-ESPProfiles {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Enrollment Status Page Profiles..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "EnrollmentStatusPage"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations"

    $ESPProfiles = $Response.value | Where-Object {
        $_.'@odata.type' -eq "#microsoft.graph.windows10EnrollmentCompletionPageConfiguration"
    }

    $Count = 0

    foreach ($Profile in $ESPProfiles) {

        $Name = if ([string]::IsNullOrWhiteSpace($Profile.displayName)) {
            $Profile.id
        }
        else {
            $Profile.displayName
        }

        $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

        # Remove Graph metadata
        $Profile.PSObject.Properties.Remove('@odata.context')
        $Profile.PSObject.Properties.Remove('@odata.type')

        $Json = $Profile | ConvertTo-Json -Depth 100

        $File = Join-Path $ExportPath "$SafeName.json"

        $Json | Set-Content `
            -Path $File `
            -Encoding UTF8

        Write-Host "   [+] $SafeName" -ForegroundColor Green

        $Count++
    }

    Write-Host ""
    Write-Host "Exported $Count Enrollment Status Page Profile(s)." -ForegroundColor Green
    Write-Host ""
}
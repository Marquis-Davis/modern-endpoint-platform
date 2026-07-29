function Export-RoleAssignments {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Role Assignments..." -ForegroundColor Cyan

    $ExportPath = Join-Path $RepositoryRoot "RoleAssignments"

    if (-not (Test-Path $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    # Get all Intune role definitions
    $RoleDefinitions = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions"

    $Count = 0

    foreach ($Role in $RoleDefinitions.value) {

        $Assignments = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions/$($Role.id)/roleAssignments"

        foreach ($Assignment in $Assignments.value) {

            $Name = if ([string]::IsNullOrWhiteSpace($Assignment.displayName)) {
                $Assignment.id
            }
            else {
                $Assignment.displayName
            }

            $SafeName = $Name -replace '[\\/:*?"<>|]', '_'

            # Remove Graph metadata
            $Assignment.PSObject.Properties.Remove('@odata.context')
            $Assignment.PSObject.Properties.Remove('@odata.type')

            $Json = $Assignment | ConvertTo-Json -Depth 100

            $File = Join-Path $ExportPath "$SafeName.json"

            $Json | Set-Content `
                -Path $File `
                -Encoding UTF8

            Write-Host "   [+] $SafeName" -ForegroundColor Green

            $Count++
        }
    }

    Write-Host ""
    Write-Host "Exported $Count Role Assignment(s)." -ForegroundColor Green
    Write-Host ""
}
function Export-SettingsCatalog {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryRoot
    )

    Write-Host "Exporting Settings Catalog..." -ForegroundColor Cyan

    $OutputFolder = Join-Path $RepositoryRoot "SettingsCatalog"

    Initialize-ExportFolder -Path $OutputFolder

    $Uri = "https://graph.microsoft.com/beta/deviceManagement/configurationPolicies"

    $Policies = @()

    while ($Uri) {

        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri

        if ($Response -is [hashtable]) {

            if ($Response.ContainsKey("value")) {
                $Policies += $Response["value"]
            }

            $Uri = if ($Response.ContainsKey("@odata.nextLink")) {
                $Response["@odata.nextLink"]
            }
            else {
                $null
            }
        }
        else {

            if ($null -ne $Response.value) {
                $Policies += $Response.value
            }

            if ($Response.PSObject.Properties.Match('@odata.nextLink').Count -gt 0) {
                $Uri = $Response.'@odata.nextLink'
            }
            else {
                $Uri = $null
            }
        }
    }

    $SettingsCatalogPolicies = $Policies | Where-Object {
        $_.templateReference.templateFamily -eq 'none'
    }

    foreach ($Policy in $SettingsCatalogPolicies) {

        $FileName = ($Policy.name -replace '[\\/:*?"<>|]', '_') + ".json"

        $Policy |
            ConvertTo-Json -Depth 100 |
            Set-Content -Path (Join-Path $OutputFolder $FileName) -Encoding UTF8

        Write-Host "   [+] $($Policy.name)"
    }

    Write-Host "Exported $($SettingsCatalogPolicies.Count) Settings Catalog policy(s)." -ForegroundColor Green
}
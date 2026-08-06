# Requires HP Client Management Script Library
# Install-Module HPCMSL -Force

Import-Module HPCMSL

$ExportCsv = "$env:USERPROFILE\Desktop\HP-PlatformIDs.csv"

try {
    Write-Host "Retrieving HP platform IDs..." -ForegroundColor Cyan

    $Platforms = Get-HPDeviceDetails -Name '*' |
        Select-Object SystemID, Name, FamilyID, DriverPackSupport |
        Where-Object {
            $_.SystemID -match '^[A-Fa-f0-9]{4}$'
        } |
        Sort-Object Name, SystemID -Unique

    if (-not $Platforms) {
        throw "No HP platform IDs were returned."
    }

    $Platforms |
        Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8

    Write-Host "Found $($Platforms.Count) platform records." -ForegroundColor Green
    Write-Host "Exported to: $ExportCsv" -ForegroundColor Green

    $Platforms |
        Out-GridView -Title "HP Models and Platform IDs"
}
catch {
    Write-Error "Failed: $($_.Exception.Message)"
}
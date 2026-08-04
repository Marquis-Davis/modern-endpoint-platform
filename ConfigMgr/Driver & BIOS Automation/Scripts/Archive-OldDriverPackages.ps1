$ErrorActionPreference = "Stop"

# Create: Archive folder under Packages. This script will archive old Drivers/BIOS packages
# so you can safely review and manuall delete.
# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------

$SiteCode = "ABC"
$Provider = "CM01.contoso.com"

$ArchiveFolder = "Package\Driver Packages\Archive"

$LogFolder = "C:\Program Files\MSEndpointMgr\Driver Automation Tool\Logs"
$LogFile = Join-Path $LogFolder "Archive-OldDriverPackages_$SiteCode.log"

# ------------------------------------------------------------
# LOG FUNCTION
# ------------------------------------------------------------

function Write-Log {
    param([string]$Message)

    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entry = "$TimeStamp - $Message"

    Write-Host $Entry
    Add-Content -Path $LogFile -Value $Entry
}

Write-Log "Starting driver archive cleanup."

try {

    # ------------------------------------------------------------
    # CONNECT TO SCCM
    # ------------------------------------------------------------

    Write-Log "Connecting to SCCM Site: $SiteCode"

    $CMModule = Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1'

    if (-not $env:SMS_ADMIN_UI_PATH -or -not (Test-Path $CMModule)) {
        $CMModule = "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"
    }

    Import-Module $CMModule -Force

    # Ensure the CM PSDrive exists, then switch to it
    if (-not (Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $Provider -ErrorAction Stop | Out-Null
    }

    Set-Location "$($SiteCode):"

    # ------------------------------------------------------------
    # GET DRIVER PACKAGES (FAST + SAFE)
    # ------------------------------------------------------------

    $DriverPackages = Get-CMPackage -Fast |
        Select-Object Name, PackageID, Version, Manufacturer |
        Where-Object {
            $_.Name -like "Drivers - *" -and
            $_.Manufacturer -in @("Dell", "HP", "Lenovo", "Microsoft")
        }

    if (!$DriverPackages) {
        Write-Log "No driver packages found."
        return
    }

    # ------------------------------------------------------------
    # GROUP BY MODEL
    # ------------------------------------------------------------

    $GroupedModels = $DriverPackages | Group-Object {
        ($_.Name -replace " - Windows.*", "")
    }

    $ArchivedCount = 0

    foreach ($Group in $GroupedModels) {

        if ($Group.Group[0].Manufacturer -eq "HP") {

            # HP version format: 10.00 A1
            $Packages = $Group.Group | Sort-Object {

                $parts = $_.Version -split ' '

                $major = if ($parts[0] -match '\d+(\.\d+)?') {
                    [double]$matches[0]
                }
                else {
                    0
                }

                $rev = if ($parts.Count -gt 1 -and $parts[1] -match '\d+') {
                    [int]$matches[0]
                }
                else {
                    0
                }

                ($major * 100) + $rev

            } -Descending
        }
        else {

            # Dell, Lenovo, Microsoft, etc.
            $Packages = $Group.Group | Sort-Object {
                if ($_.Version -match '\d+') {
                    [int]$matches[0]
                }
                else {
                    0
                }
            } -Descending
        }

        if ($Packages.Count -le 1) {
            continue
        }

        $LatestPackage = $Packages | Select-Object -First 1
        $OldPackages = $Packages | Select-Object -Skip 1

        Write-Log "Latest package kept: Name='$($LatestPackage.Name)' PackageID='$($LatestPackage.PackageID)' Version='$($LatestPackage.Version)'"

        foreach ($Pkg in $OldPackages) {

            Write-Log "Archiving package: Name='$($Pkg.Name)' PackageID='$($Pkg.PackageID)' Version='$($Pkg.Version)'"

            Move-CMObject `
                -InputObject (Get-CMPackage -Fast -Id $Pkg.PackageID) `
                -FolderPath $ArchiveFolder

            $ArchivedCount++
        }
    }

    # ------------------------------------------------------------
    # BIOS PACKAGES
    # ------------------------------------------------------------

    $BiosPackages = Get-CMPackage -Fast |
        Select-Object Name, PackageID, Version, Manufacturer |
        Where-Object {
            $_.Name -like "BIOS Update - *" -and
            $_.Manufacturer -in @("Dell", "HP", "Lenovo", "Microsoft")
        }

    if ($BiosPackages) {

        $GroupedBiosModels = $BiosPackages | Group-Object {
            $_.Name -replace "^BIOS Update - ", ""
        }

        foreach ($Group in $GroupedBiosModels) {

            $Packages = $Group.Group | Sort-Object {
                [version]($_.Version -replace '[^\d\.]', '')
            } -Descending

            if ($Packages.Count -le 1) {
                continue
            }

            $LatestPackage = $Packages | Select-Object -First 1
            $OldPackages = $Packages | Select-Object -Skip 1

            Write-Log "Latest BIOS package kept: Name='$($LatestPackage.Name)' PackageID='$($LatestPackage.PackageID)' Version='$($LatestPackage.Version)'"

            foreach ($Pkg in $OldPackages) {

                Write-Log "Archiving BIOS package: Name='$($Pkg.Name)' PackageID='$($Pkg.PackageID)' Version='$($Pkg.Version)'"

                Move-CMObject `
                    -InputObject (Get-CMPackage -Fast -Id $Pkg.PackageID) `
                    -FolderPath "Package\BIOS Packages\Archive"

                $ArchivedCount++
            }
        }
    }

    # ------------------------------------------------------------
    # SUMMARY
    # ------------------------------------------------------------

    if ($ArchivedCount -eq 0) {
        Write-Log "No old Drivers/BIOS packages found."
    }
    else {
        Write-Log "$ArchivedCount packages archived successfully."
    }
}
catch {
    Write-Log "ERROR: $($_.Exception.Message)"
}
finally {
    Pop-Location
    Write-Log "Driver archive cleanup completed."
}

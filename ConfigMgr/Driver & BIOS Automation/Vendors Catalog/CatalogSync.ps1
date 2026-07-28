# =============================================
# CONFIG
# =============================================

$CatalogRoot = "C:\Program Files\MSEndpointMgr\Driver Automation Tool\Catalogs"
$TempRoot    = "C:\Program Files\MSEndpointMgr\Driver Automation Tool\Temp"
$LogFile     = "C:\Program Files\MSEndpointMgr\Driver Automation Tool\Logs\CatalogSync.log"

$Vendors = @("Dell","HP","Lenovo","Microsoft","Asus")

# =============================================
# ENSURE FOLDER STRUCTURE
# =============================================

foreach ($Path in @($CatalogRoot, $TempRoot, (Split-Path $LogFile))) {
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    }
}

foreach ($Vendor in $Vendors) {
    $VendorPath = Join-Path $CatalogRoot $Vendor
    if (-not (Test-Path $VendorPath)) {
        New-Item -Path $VendorPath -ItemType Directory -Force | Out-Null
    }
}

# =============================================
# START TRANSCRIPT
# =============================================

Start-Transcript -Path $LogFile -Append
Write-Host "========== Catalog Sync Started: $(Get-Date) =========="

# =============================================
# DOWNLOAD + PROCESS FUNCTION
# =============================================

function Download-Replace {
    param(
        [string]$Url,
        [string]$Destination
    )

    try {
        Write-Host ""
        Write-Host "Downloading: $Url"

        $TempDownload = "$Destination.tmp"

        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $TempDownload `
            -UseBasicParsing `
            -ErrorAction Stop

        Move-Item -Path $TempDownload -Destination $Destination -Force
        Write-Host "Updated Catalog: $Destination"

        $Extension = [System.IO.Path]::GetExtension($Destination)

        # =====================================================
        # IF CAB → EXTRACT XML AND COPY XML TO TEMP
        # =====================================================
        if ($Extension -ieq ".cab") {

            $VendorName = Split-Path (Split-Path $Destination -Parent) -Leaf
            $ExtractPath = Join-Path $TempRoot "$VendorName-Extract"

            if (Test-Path $ExtractPath) {
                Remove-Item $ExtractPath -Recurse -Force
            }

            New-Item -Path $ExtractPath -ItemType Directory -Force | Out-Null

            Write-Host "Extracting CAB..."

            $ExpandProcess = Start-Process `
                -FilePath "$env:SystemRoot\System32\expand.exe" `
                -ArgumentList "`"$Destination`" -F:* `"$ExtractPath`"" `
                -Wait -PassThru -NoNewWindow

            if ($ExpandProcess.ExitCode -ne 0) {
                Write-Host "ERROR: CAB extraction failed with exit code $($ExpandProcess.ExitCode)"
                return
            }

            $XmlFiles = Get-ChildItem -Path $ExtractPath -Recurse -Filter *.xml

            if (-not $XmlFiles) {
                Write-Host "WARNING: No XML found inside CAB."
            }
            else {
                foreach ($Xml in $XmlFiles) {
                    $TempDestination = Join-Path $TempRoot $Xml.Name
                    Copy-Item -Path $Xml.FullName -Destination $TempDestination -Force
                    Write-Host "Copied XML to Temp: $TempDestination"
                }
            }

            Remove-Item $ExtractPath -Recurse -Force
        }
        else {
            # =====================================================
            # NON-CAB → COPY DIRECTLY TO TEMP
            # =====================================================
            $TempDestination = Join-Path $TempRoot (Split-Path $Destination -Leaf)
            Copy-Item -Path $Destination -Destination $TempDestination -Force
            Write-Host "Copied to Temp: $TempDestination"
        }
    }
    catch {
        Write-Host "FAILED: $Url"
        if (Test-Path $TempDownload) {
            Remove-Item $TempDownload -Force
        }
    }
}

# =============================================
# DELL
# =============================================

Download-Replace `
    -Url "https://downloads.dell.com/catalog/DriverPackCatalog.cab" `
    -Destination "$CatalogRoot\Dell\DriverPackCatalog.cab"

Download-Replace `
    -Url "https://downloads.dell.com/catalog/CatalogPC.cab" `
    -Destination "$CatalogRoot\Dell\CatalogPC.cab"

# =============================================
# HP
# =============================================

Download-Replace `
    -Url "https://ftp.hp.com/pub/caps-softpaq/cmit/HP_Driverpack_Matrix_x64.html" `
    -Destination "$CatalogRoot\HP\HP_Driverpack_Matrix_x64.html"

Download-Replace `
    -Url "https://ftp.hp.com/pub/caps-softpaq/cmit/HPClientDriverPackCatalog.cab" `
    -Destination "$CatalogRoot\HP\HPClientDriverPackCatalog.cab"

# =============================================
# LENOVO
# =============================================

Download-Replace `
    -Url "https://download.lenovo.com/cdrt/td/catalogv2.xml" `
    -Destination "$CatalogRoot\Lenovo\catalogv2.xml"

# =============================================
# MICROSOFT SURFACE
# =============================================

Download-Replace `
    -Url "https://support.microsoft.com/en-us/surface/surface-update-history-xml-feed" `
    -Destination "$CatalogRoot\Microsoft\Surface_Update_History.xml"

# =============================================
# ASUS
# =============================================

Download-Replace `
    -Url "https://www.asus.com/support/" `
    -Destination "$CatalogRoot\Asus\SupportLanding.html"

Write-Host ""
Write-Host "========== Catalog Sync Completed: $(Get-Date) =========="

# =============================================
# END TRANSCRIPT
# =============================================

Stop-Transcript
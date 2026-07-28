#requires -Version 5.1
<#
.SYNOPSIS
    Builds and distributes HP BIOS packages in Microsoft Configuration Manager.

.DESCRIPTION
    Reads a CSV containing HP model, platform ID, latest BIOS version, and download URL.
    For each row, the script:
      - validates the CSV data
      - downloads and extracts the HP BIOS SoftPaq
      - stages content on a ConfigMgr content share using safe .NET file copy
      - creates the ConfigMgr package when it does not already exist
      - moves the package into the configured ConfigMgr console folder
      - distributes content to the configured distribution point group
      - records success/failure results
      - optionally invokes a separate reporting script
      - archives the CSV only when all models succeed

.NOTES
    Update only the CONFIG section before use.

.EXAMPLE
    .\Build-HPBIOSPackages.ps1

.EXAMPLE
    .\Build-HPBIOSPackages.ps1 -CsvPath "C:\Automation\Config\HPBIOSUpdates.csv"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath = "C:\Program Files\MSEndpointMgr\Driver Automation Tool\Config\HP\HPBIOSUpdates.csv",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$DownloadRoot = "C:\Temp\HP-BIOS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============================================================================
# CONFIG - UPDATE THESE VALUES
# ============================================================================

$Vendor              = "HP"
$SiteCode            = "ABC"
$ProviderMachineName = "CM01.contoso.com"

$ContentShareRoot = "\\fileserver\Source\OSD\BIOS\HP"
$ConfigMgrFolder  = "Package\BIOS Packages\HP"
$DPGroupName      = "Driver Distribution Points"

$ToolRoot   = "C:\Program Files\MSEndpointMgr\Driver Automation Tool"
$LogFolder  = Join-Path $ToolRoot "Logs\Build-HPBIOSPackages"
$SevenZip   = "C:\Program Files\7-Zip\7z.exe"

$ReportScript = Join-Path $ToolRoot "Scripts\Modules\Invoke-BIOSAutomationReport.ps1"
$EnableReport = $false

# ============================================================================
# INITIALIZATION
# ============================================================================

$ScriptStartTime = Get-Date
$SuccessModels   = [System.Collections.Generic.List[string]]::new()
$FailedModels    = [System.Collections.Generic.List[string]]::new()

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile  = Join-Path $LogFolder "Build-HPBIOSPackages_$RunStamp.log"

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter()]
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp [$Level] $Message"

    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Ensure-Folder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not [System.IO.Directory]::Exists($Path)) {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
    }
}

function Get-SafeName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name
    )

    return (($Name -replace '[\\/:*?"<>|]', '') -replace '\s+', ' ').Trim()
}

function Import-ConfigMgr {
    [CmdletBinding()]
    param()

    $cmModule = Join-Path $env:SMS_ADMIN_UI_PATH "..\ConfigurationManager.psd1"

    if (-not (Test-Path -LiteralPath $cmModule -PathType Leaf)) {
        $cmModule = "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1"
    }

    if (-not (Test-Path -LiteralPath $cmModule -PathType Leaf)) {
        throw "ConfigurationManager.psd1 was not found."
    }

    Import-Module $cmModule -Force -ErrorAction Stop

    if (-not (Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
        New-PSDrive `
            -Name $SiteCode `
            -PSProvider CMSite `
            -Root $ProviderMachineName `
            -ErrorAction Stop | Out-Null
    }

    Set-Location "$SiteCode`:" -ErrorAction Stop
    $null = Get-CMSite -ErrorAction Stop

    Write-Log "Connected to ConfigMgr site $SiteCode."
}

function Get-FileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function Copy-DirectorySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Source folder not found: $SourcePath"
    }

    Ensure-Folder -Path $DestinationPath

    $sourceFiles = @(Get-ChildItem -LiteralPath $SourcePath -Recurse -File -ErrorAction Stop)
    if ($sourceFiles.Count -eq 0) {
        throw "Source folder contains no files: $SourcePath"
    }

    foreach ($file in $sourceFiles) {
        $relativePath = $file.FullName.Substring($SourcePath.Length).TrimStart('\')
        $targetFile   = Join-Path $DestinationPath $relativePath
        $targetDir    = [System.IO.Path]::GetDirectoryName($targetFile)

        Ensure-Folder -Path $targetDir

        if ([System.IO.File]::Exists($targetFile)) {
            $sourceHash = Get-FileSha256 -Path $file.FullName
            $targetHash = Get-FileSha256 -Path $targetFile

            if ($sourceHash -eq $targetHash) {
                Write-Log "Skipping unchanged file: $relativePath"
                continue
            }

            Write-Log "Updating changed file: $relativePath"
        }
        else {
            Write-Log "Copying new file: $relativePath"
        }

        [System.IO.File]::Copy($file.FullName, $targetFile, $true)
    }

    $destinationFiles = @(Get-ChildItem -LiteralPath $DestinationPath -Recurse -File -ErrorAction Stop)

    if ($destinationFiles.Count -lt $sourceFiles.Count) {
        throw "Copy verification failed. Source files: $($sourceFiles.Count); destination files: $($destinationFiles.Count)."
    }

    Write-Log "Content copy completed successfully."
}

function Invoke-SevenZipExtract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ArchivePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SevenZip -PathType Leaf)) {
        throw "7-Zip was not found: $SevenZip"
    }

    & $SevenZip x $ArchivePath "-o$DestinationPath" -y | Out-Null
    $exitCode = $LASTEXITCODE

    if ($exitCode -notin 0, 1) {
        throw "7-Zip extraction failed with exit code $exitCode."
    }

    $extractedFiles = @(Get-ChildItem -LiteralPath $DestinationPath -Recurse -File -ErrorAction Stop)
    if ($extractedFiles.Count -eq 0) {
        throw "No files were extracted from $ArchivePath."
    }
}

function New-UniqueStagingFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $safeModel   = Get-SafeName -Name $Model
    $safeVersion = Get-SafeName -Name $Version
    $baseName    = "BIOS_${safeModel}_${safeVersion}_Rev_A"
    $path        = Join-Path $DownloadRoot $baseName

    if (-not (Test-Path -LiteralPath $path)) {
        Ensure-Folder -Path $path
        return $path
    }

    $index = 1
    do {
        $candidate = Join-Path $DownloadRoot "${baseName}_Repack$index"
        $index++
    } while (Test-Path -LiteralPath $candidate)

    Ensure-Folder -Path $candidate
    return $candidate
}

function Get-ExistingPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    return Get-CMPackage -Fast -ErrorAction Stop |
        Where-Object {
            $_.Name -eq $PackageName -and
            $_.Version -eq $Version
        } |
        Select-Object -First 1
}

function New-HPBiosPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Model,

        [Parameter(Mandatory)]
        [string]$Version,

        [Parameter(Mandatory)]
        [string]$ContentPath,

        [Parameter(Mandatory)]
        [string[]]$SystemIDs
    )

    $packageName = "BIOS Update - $Vendor $Model"
    $description = "Models included: $($SystemIDs -join ';')"

    $existing = Get-ExistingPackage -PackageName $packageName -Version $Version
    if ($existing) {
        Write-Log "Package already exists. Skipping creation: $packageName $Version" -Level Warning

        return [PSCustomObject]@{
            Package  = $existing
            Created  = $false
            Message  = "Package already exists"
        }
    }

    $package = New-CMPackage `
        -Name $packageName `
        -Manufacturer $Vendor `
        -Language "English" `
        -Version $Version `
        -Path $ContentPath `
        -Description $description `
        -ErrorAction Stop

    Write-Log "Created package: $packageName | PackageID: $($package.PackageID)"
    Write-Log "Package description: $description"

    try {
        Move-CMObject `
            -InputObject $package `
            -FolderPath $ConfigMgrFolder `
            -ErrorAction Stop

        Write-Log "Moved package to ConfigMgr folder: $ConfigMgrFolder"
    }
    catch {
        Write-Log "Could not move package to ConfigMgr folder: $($_.Exception.Message)" -Level Warning
    }

    Start-CMContentDistribution `
        -PackageId $package.PackageID `
        -DistributionPointGroupName $DPGroupName `
        -ErrorAction Stop

    Write-Log "Distribution started for package: $packageName"

    return [PSCustomObject]@{
        Package  = $package
        Created  = $true
        Message  = "Package created and distribution started"
    }
}

function ConvertTo-StringArray {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Value
    )

    return @(
        $Value |
        ForEach-Object { [string]$_ } |
        ForEach-Object { $_ -split '[,;]' } |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
    )
}

# ============================================================================
# MAIN
# ============================================================================

Ensure-Folder -Path $LogFolder
Ensure-Folder -Path $DownloadRoot
Write-Log "===== HP BIOS AUTOMATION START ====="

$originalLocation = Get-Location

try {
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) {
        throw "CSV file not found: $CsvPath"
    }

    if (-not (Test-Path -LiteralPath $ContentShareRoot -PathType Container)) {
        throw "Content share is unavailable: $ContentShareRoot"
    }

    $models = @(Import-Csv -LiteralPath $CsvPath -ErrorAction Stop)
    if ($models.Count -eq 0) {
        throw "The CSV contains no rows: $CsvPath"
    }

    Import-ConfigMgr

    foreach ($modelRow in $models) {
        $modelName = [string]$modelRow.Model
        $platform  = [string]$modelRow.PlatformID
        $version   = [string]$modelRow.LatestVersion
        $url       = [string]$modelRow.DownloadUrl

        if ([string]::IsNullOrWhiteSpace($modelName) -or
            [string]::IsNullOrWhiteSpace($platform) -or
            [string]::IsNullOrWhiteSpace($version) -or
            [string]::IsNullOrWhiteSpace($url)) {

            $displayName = if ($modelName) { $modelName } else { "<unknown model>" }
            Write-Log "Skipping invalid CSV row for $displayName. Required values are missing." -Level Error
            $FailedModels.Add($displayName)
            continue
        }

        try {
            Write-Log "Processing model: $modelName"

            $device = Get-HPDeviceDetails -Platform $platform -ErrorAction Stop
            if (-not $device) {
                throw "Device lookup failed for platform $platform."
            }

            $systemIDs = ConvertTo-StringArray -Value $device.SystemID
            if ($systemIDs.Count -eq 0) {
                throw "No SystemID values were returned for platform $platform."
            }

            $bios = Get-SoftpaqList -Platform $platform -Category BIOS -ErrorAction Stop |
                Sort-Object ReleaseDate -Descending |
                Select-Object -First 1

            if (-not $bios) {
                throw "No BIOS SoftPaq was found for platform $platform."
            }

            $softPaqVersion = [string]$bios.Version
            $softPaqUrl     = [string]$bios.Url

            if ([string]::IsNullOrWhiteSpace($softPaqUrl)) {
                throw "The BIOS SoftPaq URL is empty for $modelName."
            }

            Write-Log "BIOS SoftPaq selected: $softPaqUrl | Version: $softPaqVersion"

            $stagingPath = New-UniqueStagingFolder -Model $modelName -Version $version
            $exeName     = Split-Path $softPaqUrl -Leaf
            $exePath     = Join-Path $stagingPath $exeName

            Write-Log "Downloading BIOS: $exeName"
            Invoke-WebRequest -Uri $softPaqUrl -OutFile $exePath -UseBasicParsing -ErrorAction Stop

            if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
                throw "BIOS download did not create the expected file: $exePath"
            }

            Write-Log "Extracting BIOS."
            Invoke-SevenZipExtract -ArchivePath $exePath -DestinationPath $stagingPath

            $safeModel   = Get-SafeName -Name $modelName
            $safeVersion = Get-SafeName -Name $version
            $folderName  = "BIOS_${safeModel}_${safeVersion}_Rev_A"
            $packagePath = Join-Path $ContentShareRoot $folderName

            Write-Log "Copying staged content to: $packagePath"
            Copy-DirectorySafe -SourcePath $stagingPath -DestinationPath $packagePath

            $packageResult = New-HPBiosPackage `
                -Model $modelName `
                -Version $version `
                -ContentPath $packagePath `
                -SystemIDs $systemIDs

            $SuccessModels.Add($modelName)
            Write-Log "SUCCESS: $modelName"

            Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Log "FAILED: $modelName" -Level Error
            Write-Log "Error: $($_.Exception.Message)" -Level Error
            $FailedModels.Add($modelName)
            continue
        }
    }
}
catch {
    Write-Log "CRITICAL: $($_.Exception.Message)" -Level Error
}
finally {
    Set-Location $originalLocation
}

# ============================================================================
# SUMMARY / REPORTING
# ============================================================================

$runtime = "{0:mm\:mm} {0:ss\:ss}" -f ((Get-Date) - $ScriptStartTime)

Write-Log "===== HP BIOS Package Builder Finished ====="
Write-Log "Success Models: $($SuccessModels.Count)"
Write-Log "Failed Models: $($FailedModels.Count)"
Write-Log "Runtime: $runtime"

if ($EnableReport -and (Test-Path -LiteralPath $ReportScript -PathType Leaf)) {
    try {
        & $ReportScript `
            -Vendor $Vendor `
            -Models $SuccessModels.ToArray() `
            -Success $SuccessModels.ToArray() `
            -Failed $FailedModels.ToArray() `
            -Runtime $runtime
    }
    catch {
        Write-Log "Reporting script failed: $($_.Exception.Message)" -Level Warning
    }
}

if ($FailedModels.Count -eq 0) {
    try {
        $processedPath = Join-Path `
            (Split-Path $CsvPath) `
            "HPBIOSUpdates_Processed_$(Get-Date -Format 'yyyyMMddHHmmss').csv"

        Move-Item -LiteralPath $CsvPath -Destination $processedPath -Force -ErrorAction Stop
        Write-Log "CSV archived to: $processedPath"
    }
    catch {
        Write-Log "Failed to archive CSV: $($_.Exception.Message)" -Level Warning
    }
}
else {
    Write-Log "Failures detected. CSV was not archived." -Level Warning
}

Write-Log "===== HP BIOS AUTOMATION COMPLETE ====="

[PSCustomObject]@{
    Success       = ($FailedModels.Count -eq 0)
    Vendor        = $Vendor
    Total         = $models.Count
    Successful    = $SuccessModels.Count
    Failed        = $FailedModels.Count
    SuccessModels = $SuccessModels.ToArray()
    FailedModels  = $FailedModels.ToArray()
    Runtime       = $runtime
    LogFile       = $LogFile
    Message       = if ($FailedModels.Count -eq 0) {
        "All HP BIOS packages processed successfully."
    }
    else {
        "One or more HP BIOS packages failed. Review the log."
    }
}

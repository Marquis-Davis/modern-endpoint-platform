#requires -Version 5.1

<#
.SYNOPSIS
    Audits HP Windows 11 driver packages in Microsoft Configuration Manager.

.DESCRIPTION
    Loads HP driver packages from Configuration Manager, reads the HP Driver Pack
    Matrix, compares the latest HP driver-pack version against the package version
    in Configuration Manager, exports models with updates available, and optionally
    posts a JSON summary to a webhook.

    This public version contains no organization-specific names, server names,
    site codes, credentials, or webhook URLs.

.PARAMETER SiteCode
    Configuration Manager site code.

.PARAMETER ProviderMachineName
    Configuration Manager SMS Provider server.

.PARAMETER PackageNamePattern
    Wildcard used to identify HP driver packages in Configuration Manager.

.PARAMETER MatrixUrl
    HP Driver Pack Matrix URL.

.PARAMETER MatrixCachePath
    Local cache path for the downloaded HP matrix HTML.

.PARAMETER MatrixMaxAgeDays
    Maximum cache age before the matrix is downloaded again.

.PARAMETER ExportPath
    CSV path for packages with UPDATE AVAILABLE status.

.PARAMETER LogDirectory
    Directory used for transcript and error logs.

.PARAMETER WebhookUrl
    Optional HTTP endpoint that receives the JSON summary.

.PARAMETER SkipWebhook
    Prevents webhook submission even when WebhookUrl is supplied.

.EXAMPLE
    .\HP-Endpoint-Driver-Governance.ps1 `
        -SiteCode "ABC" `
        -ProviderMachineName "cm01.contoso.com"

.EXAMPLE
    .\HP-Endpoint-Driver-Governance.ps1 `
        -SiteCode "ABC" `
        -ProviderMachineName "cm01.contoso.com" `
        -SkipWebhook
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ProviderMachineName,

    [ValidateNotNullOrEmpty()]
    [string]$PackageNamePattern = "Drivers - HP *",

    [ValidateNotNullOrEmpty()]
    [string]$MatrixUrl = "https://ftp.hp.com/pub/caps-softpaq/cmit/HP_Driverpack_Matrix_x64.html",

    [ValidateNotNullOrEmpty()]
    [string]$MatrixCachePath = "$env:ProgramData\HPDriverGovernance\HP_Driverpack_Matrix_x64.html",

    [ValidateRange(1, 365)]
    [int]$MatrixMaxAgeDays = 7,

    [ValidateNotNullOrEmpty()]
    [string]$ExportPath = "$env:ProgramData\HPDriverGovernance\HPUpdates.csv",

    [ValidateNotNullOrEmpty()]
    [string]$LogDirectory = "$env:ProgramData\HPDriverGovernance\Logs",

    [string]$WebhookUrl,

    [switch]$SkipWebhook
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Ensure-Directory {
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

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "$timestamp [$Level] $Message"
    Write-Host $line

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    }
}

function Import-ConfigMgr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SiteCode,

        [Parameter(Mandatory)]
        [string]$ProviderMachineName
    )

    $cmModule = if ($env:SMS_ADMIN_UI_PATH) {
        Join-Path $env:SMS_ADMIN_UI_PATH '..\ConfigurationManager.psd1'
    }
    else {
        'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'
    }

    if (-not (Test-Path -LiteralPath $cmModule -PathType Leaf)) {
        throw "ConfigurationManager.psd1 was not found: $cmModule"
    }

    Import-Module $cmModule -Force -ErrorAction Stop

    if (-not (Get-PSDrive -Name $SiteCode -ErrorAction SilentlyContinue)) {
        New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName -ErrorAction Stop | Out-Null
    }

    Set-Location "$SiteCode`:" -ErrorAction Stop
    Write-Log "Connected to Configuration Manager site $SiteCode."
}

function Initialize-HPMatrix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$MatrixUrl,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [int]$MaxAgeDays
    )

    Ensure-Directory -Path (Split-Path -Path $CachePath -Parent)

    $downloadRequired = $true

    if (Test-Path -LiteralPath $CachePath -PathType Leaf) {
        $age = (Get-Date) - (Get-Item -LiteralPath $CachePath).LastWriteTime
        if ($age.TotalDays -lt $MaxAgeDays) {
            Write-Log "Using cached HP matrix: $CachePath"
            $downloadRequired = $false
        }
    }

    if ($downloadRequired) {
        Write-Log "Downloading HP Driver Pack Matrix."
        Invoke-WebRequest -Uri $MatrixUrl -OutFile $CachePath -UseBasicParsing -ErrorAction Stop
    }

    $html = Get-Content -LiteralPath $CachePath -Raw -ErrorAction Stop
    $rows = [regex]::Matches($html, '<tr.*?>.*?</tr>', 'Singleline')

    if (-not $rows -or $rows.Count -eq 0) {
        throw 'Failed to parse rows from the HP Driver Pack Matrix.'
    }

    [pscustomobject]@{
        Html = $html
        Rows = $rows
    }
}

function Normalize-HPModelName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $model = $PackageName
    $model = $model -replace '(?i)^\s*Drivers\s*-\s*HP\s*', ''
    $model = $model -replace '(?i)\s*-\s*Windows\s*\d+.*$', ''
    $model = ($model -replace '\s+', ' ').Trim()
    return $model
}

function Get-HPVersionNumber {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return -1
    }

    if ($Value -match '(?i)\bA\s*0*(\d+)\b') {
        return [int]$Matches[1]
    }

    if ($Value -match '(\d+)') {
        return [int]$Matches[1]
    }

    return -1
}

function ConvertTo-VersionValue {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [version]'0.0'
    }

    $match = [regex]::Match($Value, '\d+(?:\.\d+){0,3}')
    if ($match.Success) {
        try {
            return [version]$match.Value
        }
        catch {
            return [version]'0.0'
        }
    }

    return [version]'0.0'
}

function Get-HPDriverPackInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelInput,

        [Parameter(Mandatory)]
        [string]$MatrixHtml
    )

    $baseModel = ($ModelInput -replace '\s*-\s*Windows.*$', '').Trim()
    $modelRegex = [regex]::Escape($baseModel)

    $softPaqMatches = [regex]::Matches(
        $MatrixHtml,
        "$modelRegex.*?(sp\d{5,6})\.exe",
        'Singleline,IgnoreCase'
    )

    if ($softPaqMatches.Count -eq 0) {
        return $null
    }

    $latestSoftPaq = $softPaqMatches |
        ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } |
        Sort-Object { [int]($_ -replace 'sp', '') } -Descending |
        Select-Object -First 1

    $numberOnly = [int]($latestSoftPaq -replace 'sp', '')
    $rangeStart = [math]::Floor($numberOnly / 500) * 500 + 1
    $rangeEnd = $rangeStart + 499
    $rangeFolder = "sp{0}-{1}" -f $rangeStart, $rangeEnd
    $softPaqUrl = "https://ftp.hp.com/pub/softpaq/$rangeFolder/$latestSoftPaq.html"

    $cacheRoot = Join-Path $env:ProgramData 'HPDriverGovernance\SoftPaq'
    Ensure-Directory -Path $cacheRoot
    $softPaqCacheFile = Join-Path $cacheRoot "$latestSoftPaq.html"

    try {
        if (Test-Path -LiteralPath $softPaqCacheFile -PathType Leaf) {
            $pageContent = Get-Content -LiteralPath $softPaqCacheFile -Raw
        }
        else {
            Invoke-WebRequest -Uri $softPaqUrl -OutFile $softPaqCacheFile -UseBasicParsing -ErrorAction Stop
            $pageContent = Get-Content -LiteralPath $softPaqCacheFile -Raw
        }
    }
    catch {
        Write-Log "Unable to retrieve SoftPaq page for $baseModel: $($_.Exception.Message)" -Level Warning
        return $null
    }

    $cleanText = $pageContent `
        -replace '<br\s*/?>', "`n" `
        -replace '<[^>]+>', '' `
        -replace '&nbsp;', ' '

    $lines = $cleanText -split "`n" | ForEach-Object { $_.Trim() }

    $version = $null
    $releaseDate = $null

    foreach ($line in $lines) {
        if (-not $version -and $line -match '(?i)^Version:\s*(.+)') {
            $version = $Matches[1].Trim()
        }

        if (-not $releaseDate -and $line -match '(?i)^Effective Date:\s*(.+)') {
            $releaseDate = $Matches[1].Trim()
        }

        if ($version -and $releaseDate) {
            break
        }
    }

    if (-not $version) {
        return $null
    }

    [pscustomobject]@{
        VendorLatest = $version
        ReleaseDate  = $releaseDate
        SoftPaq       = $latestSoftPaq
        SoftPaqUrl    = $softPaqUrl
    }
}

function Get-HPConsoleInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageNamePattern
    )

    $packages = @(Get-CMPackage -Fast | Where-Object {
        $_.Manufacturer -eq 'HP' -and
        $_.Name -like $PackageNamePattern -and
        $_.Name -match '(?i)Windows\s*11'
    })

    if ($packages.Count -eq 0) {
        return @()
    }

    $parsed = foreach ($package in $packages) {
        $os = if ($package.Name -match '(?i)\b25H2\b') {
            'Windows 11 25H2 x64'
        }
        else {
            'Windows 11 x64'
        }

        [pscustomobject]@{
            PackageID   = $package.PackageID
            Name        = $package.Name
            Model       = Normalize-HPModelName -PackageName $package.Name
            OS          = $os
            CMVersion   = [string]$package.Version
            VersionSort = Get-HPVersionNumber -Value ([string]$package.Version)
            SourceDate  = $package.SourceDate
        }
    }

    $parsed |
        Group-Object Model, OS |
        ForEach-Object {
            $_.Group |
                Sort-Object VersionSort, SourceDate -Descending |
                Select-Object -First 1
        }
}

function New-HPComplianceResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ConsolePackage,
        $VendorData
    )

    $latestVersion = if ($VendorData) { [string]$VendorData.VendorLatest } else { $null }

    if ([string]::IsNullOrWhiteSpace($latestVersion)) {
        $status = 'NOT FOUND'
    }
    elseif ((ConvertTo-VersionValue -Value $latestVersion) -gt
            (ConvertTo-VersionValue -Value $ConsolePackage.CMVersion)) {
        $status = 'UPDATE AVAILABLE'
    }
    else {
        $status = 'UP TO DATE'
    }

    [pscustomobject]@{
        PackageID     = $ConsolePackage.PackageID
        Model         = $ConsolePackage.Model
        OS            = $ConsolePackage.OS
        CMVersion     = $ConsolePackage.CMVersion
        LatestVersion = if ($latestVersion) { $latestVersion } else { 'UNKNOWN' }
        ReleaseDate   = if ($VendorData) { $VendorData.ReleaseDate } else { $null }
        SoftPaq        = if ($VendorData) { $VendorData.SoftPaq } else { $null }
        Status         = $status
        CMName         = $ConsolePackage.Name
    }
}

$originalLocation = Get-Location
$script:LogFile = $null
$transcriptStarted = $false

try {
    Ensure-Directory -Path $LogDirectory
    Ensure-Directory -Path (Split-Path -Path $ExportPath -Parent)

    $runStamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    $script:LogFile = Join-Path $LogDirectory "HP-Endpoint-Driver-Governance_$runStamp.log"
    $transcriptPath = Join-Path $LogDirectory "HP-Endpoint-Driver-Governance_$runStamp.transcript.log"

    try {
        Start-Transcript -Path $transcriptPath -Force | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Log "Transcript could not be started: $($_.Exception.Message)" -Level Warning
    }

    Write-Log 'HP endpoint driver governance started.'

    Import-ConfigMgr -SiteCode $SiteCode -ProviderMachineName $ProviderMachineName

    $matrix = Initialize-HPMatrix `
        -MatrixUrl $MatrixUrl `
        -CachePath $MatrixCachePath `
        -MaxAgeDays $MatrixMaxAgeDays

    $consolePackages = @(Get-HPConsoleInventory -PackageNamePattern $PackageNamePattern)

    if ($consolePackages.Count -eq 0) {
        throw 'No HP Windows 11 driver packages were found in Configuration Manager.'
    }

    Write-Log "Found $($consolePackages.Count) unique HP model/OS package combinations."

    $results = foreach ($consolePackage in $consolePackages) {
        Write-Log "Evaluating $($consolePackage.Model)."

        $vendorData = Get-HPDriverPackInventory `
            -ModelInput $consolePackage.Model `
            -MatrixHtml $matrix.Html

        New-HPComplianceResult `
            -ConsolePackage $consolePackage `
            -VendorData $vendorData
    }

    $cleanResults = @(
        $results |
            Sort-Object @{
                Expression = {
                    switch ($_.Status) {
                        'UPDATE AVAILABLE' { 1 }
                        'UP TO DATE'       { 2 }
                        'NOT FOUND'        { 3 }
                        default            { 4 }
                    }
                }
            }, Model
    )

    $cleanResults |
        Format-Table PackageID, Model, OS, CMVersion, LatestVersion, Status -AutoSize

    $verifiedUpdates = @(
        $cleanResults |
            Where-Object Status -eq 'UPDATE AVAILABLE' |
            Select-Object `
                @{Name='Model'; Expression={$_.Model.Trim()}},
                @{Name='ConsoleVersion'; Expression={$_.CMVersion.Trim()}},
                @{Name='HPVersion'; Expression={$_.LatestVersion.Trim()}},
                OS,
                PackageID
    )

    if ($verifiedUpdates.Count -eq 0) {
        Write-Log 'No UPDATE AVAILABLE models were found.'
        if (Test-Path -LiteralPath $ExportPath) {
            Remove-Item -LiteralPath $ExportPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        $verifiedUpdates |
            Sort-Object Model |
            Export-Csv -LiteralPath $ExportPath -NoTypeInformation -Encoding UTF8

        Write-Log "Exported $($verifiedUpdates.Count) models to $ExportPath."
    }

    $total = $cleanResults.Count
    $outdated = @($cleanResults | Where-Object Status -eq 'UPDATE AVAILABLE').Count
    $compliance = if ($total -gt 0) {
        [math]::Round((($total - $outdated) / $total) * 100, 1)
    }
    else {
        0
    }

    $body = [ordered]@{
        Vendor     = 'HP'
        Total      = [int]$total
        Outdated   = [int]$outdated
        Compliance = $compliance
        Results    = $cleanResults
        Generated  = (Get-Date).ToString('o')
    }

    if (-not $SkipWebhook -and -not [string]::IsNullOrWhiteSpace($WebhookUrl)) {
        Write-Log 'Posting governance summary to webhook.'

        Invoke-RestMethod `
            -Method Post `
            -Uri $WebhookUrl `
            -ContentType 'application/json' `
            -Body ($body | ConvertTo-Json -Depth 8) `
            -ErrorAction Stop | Out-Null
    }

    Write-Log "Completed. Total=$total; Outdated=$outdated; Compliance=$compliance%."

    [pscustomobject]@{
        Success     = $true
        Vendor      = 'HP'
        Total       = $total
        Outdated    = $outdated
        Compliance  = $compliance
        ExportPath  = $ExportPath
        LogFile     = $script:LogFile
        Results     = $cleanResults
        Message     = 'HP driver governance completed successfully.'
    }
}
catch {
    $message = $_.Exception.Message
    Write-Log "FAILED: $message" -Level Error

    [pscustomobject]@{
        Success     = $false
        Vendor      = 'HP'
        Total       = 0
        Outdated    = 0
        Compliance  = 0
        ExportPath  = $ExportPath
        LogFile     = $script:LogFile
        Results     = @()
        Message     = $message
    }
}
finally {
    if ($transcriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }

    try {
        Set-Location $originalLocation
    }
    catch {
    }
}

<#
.SYNOPSIS
ConfigMgr Boot Image Automation

.DESCRIPTION
Builds a clean ConfigMgr WinPE boot image from the Microsoft ADK winpe.wim.
Supports any site code defined in the configuration section.
Builds from scratch every time and writes CMTrace-compatible logs.

Version 3.2 includes WinPEGen/BITSACP configuration:
- Site codes are loaded from the Environments configuration.
- New sites can be added by copying one environment block.
- Paths are centralized in the configuration section.
- SharePoint driver settings are centralized for future Graph/API integration.

.NOTES
Update the configuration section before running in your environment.
#>

# ============================================================
# Tool settings
# ============================================================

$Global:ToolName    = "ConfigMgr Boot Image Automation"
$Global:ToolVersion = "3.2.0"
$Global:CompanyName = "Preferred Home Offers"

# ============================================================
# Configuration
# ============================================================
#
# Most future updates should happen in this section only.
#
# To add a new site:
#   1. Copy one block under Environments.
#   2. Change the site code/name.
#   3. Set BootDriverProfile.
#   4. Set BranchCacheEnabled.
#   5. Update BootExtraFilesSource. Drivers are read from SharePoint when enabled,
#      or from the fallback driver path template until SharePoint access is approved.
#
# To change Windows source:
#   Update General.WindowsSourceName and General.WindowsInstallWim.
#
# To change WinPEGen or BITSACP:
#   Update General.WinPEGenExe or General.BITSACPSource.
#   WinPEGen is used by Invoke-BranchCacheInjection only.
#   BootExtraFilesSource copies the full site-specific folder to the mounted WIM root.
#
# To enable SharePoint driver lookup later:
#   Update General.SharePointDriverManifest.
#
# The engine below this configuration should not need changes for normal
# site additions, path changes, or Windows source updates.
# ============================================================

$Global:Config = @{
    General = @{
        WorkingRoot         = "C:\Temp\ConfigMgrBootImageAutomation"
        MaxBootImageSizeKB  = 370000
        RequiredFreeSpaceGB = 15
        # WinPE source selection.
        # PrimarySite is preferred so builds match the ADK/WinPE version used by ConfigMgr.
        # LocalWorkstation is available for disaster recovery or isolated testing.
        DefaultWinPESource  = "PrimarySite" # PrimarySite or LocalWorkstation
        PrimarySiteServer   = "primary"
        PrimarySiteADKRoot  = '\\primary\d$\Program Files (x86)\Windows Kits\10'
        LocalADKRoot        = "C:\Program Files (x86)\Windows Kits\10"

        # Backward-compatible local ADK root used by system checks.
        ADKRoot             = "C:\Program Files (x86)\Windows Kits\10"
        DISMPath            = "$env:SystemRoot\System32\dism.exe"

        # Update this when the Windows source version changes.
        # The script copies this WIM locally before running BranchCache injection.
        WindowsSourceName   = "Windows 11 Current"
        WindowsInstallWim   = "\\DataSource.preferredhomeoffers.com\DataSource\Shared\OSD\Windows11\sources\install.wim"

        # WinPEGen executable.
        # Used by Invoke-BranchCacheInjection for PHO/PHQ only.
        # This is separate from BootExtraFilesSource.
        WinPEGenExe         = "\\DataSource\Shared\Packages\OSD\BootImageExtraFiles\Workstations_x64\WinPEGen.exe"

        # Updated copy of BITSACP.exe copied into the mounted WinPE image.
        BITSACPSource       = "\\DataSource\Shared\Packages\OSD\BootImageExtraFiles\Workstations_x64\2PintTools\BITSACP.exe"

        # SharePoint driver manifest placeholder.
        # Leave Enabled = $false until the app registration has Sites.Selected read access.
        SharePointDriverManifest = @{
            Enabled          = $false
            TenantId         = ""
            ClientId         = ""
            SiteId           = ""
            ListId           = ""

            ColumnSiteCode   = "SiteCode"
            ColumnDriverPath = "Driver Path"
            ColumnEnabled    = "Enabled"

            # Fallback driver source until SharePoint access is approved.
            # {Profile} resolves to BootDriverProfile, for example PHO or PHO.
            FallbackDriverRoot         = "\\DataSource.preferredhomeoffers.com\DataSource"
            FallbackDriverPathTemplate = "{Profile}\OSD\Boot\Drivers"
        }

        # UI/report labels. Change labels here instead of changing build functions.
        Labels = @{
            BranchCacheComponents = "BranchCache Components"
            BootDrivers           = "OSD Boot Drivers"
            BootExtraFiles        = "OSD Boot Extra Files"
            TSBackground          = "OSD TSBackground"
            BuildSource           = "Build Source"
        }
    }

    Environments = @{
        PHO = @{
            Name                 = "PHO - Production"
            SiteCode             = "PHO"
            BootImageName        = "PHO_Enterprise Boot Image"

            # PHO uses its own boot extra files and PHO driver profile.
            BootDriverProfile    = "PHO"
            BranchCacheEnabled   = $true

            # Copy everything in this folder to the root of the mounted WIM.
            BootExtraFilesSource = "\\DataSource.preferredhomeoffers.com\DataSource\Shared\Packages\OSD\BootImageExtraFiles\PHO\Workstations_x64"
        }

        PHQ = @{
            Name                 = "PHQ - QA"
            SiteCode             = "PHQ"
            BootImageName        = "PHQ_Enterprise Boot Image"

            # PHQ shares the PHO driver profile but has its own boot extra files.
            BootDriverProfile    = "PHO"
            BranchCacheEnabled   = $true

            # Copy everything in this folder to the root of the mounted WIM.
            BootExtraFilesSource = "\\DataSource.preferredhomeoffers.com\DataSource\Shared\Packages\OSD\BootImageExtraFiles\PHQ\Workstations_x64"
        }

        PHS = @{
            Name                 = "PHS - Production"
            SiteCode             = "PHS"
            BootImageName        = "PHS_Enterprise Boot Image"

            # PHO uses its own driver profile and does not run BranchCache/WinPEGen.
            BootDriverProfile    = "PHS"
            BranchCacheEnabled   = $false

            # Copy root-level content to the mounted WIM root.
            # If this folder contains a child folder named Windows, its contents are copied into mounted WIM\Windows.
            BootExtraFilesSource = "\\DataSource.preferredhomeoffers.com\DataSource\Shared\Packages\OSD\BootImageExtraFiles\Servers_x64"
        }
    }
}

# ============================================================
# Console helpers
# ============================================================

function Write-Header {
    param([string]$Title)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host (" {0}" -f $Title) -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)

    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
}

function Write-Field {
    param(
        [string]$Name,
        [string]$Value
    )

    Write-Host ("{0,-15}: {1}" -f $Name, $Value)
}

function Write-CheckResult {
    param(
        [string]$Name,
        [ValidateSet("OK", "FAIL", "WARN")]
        [string]$Status
    )

    $Label = $Name.PadRight(40, '.')

    switch ($Status) {
        "OK" {
            Write-Host ("[ OK ] {0} " -f $Label) -NoNewline -ForegroundColor White
            Write-Host "PASS" -ForegroundColor Green
        }
        "FAIL" {
            Write-Host ("[FAIL] {0} " -f $Label) -NoNewline -ForegroundColor White
            Write-Host "FAIL" -ForegroundColor Red
        }
        "WARN" {
            Write-Host ("[WARN] {0} " -f $Label) -NoNewline -ForegroundColor White
            Write-Host "WARN" -ForegroundColor Yellow
        }
    }
}

function Write-StepResult {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Name,
        [ValidateSet("Critical", "Required", "Optional")]
        [string]$Severity = "Required",
        [ValidateSet("OK", "FAIL", "WARN")]
        [string]$Status,
        [string]$Detail = ""
    )

    $Prefix = ("[{0}/{1}]" -f $Step, $Total).PadRight(8, ' ')
    $SeverityLabel = $Severity.PadRight(8, ' ')
    $Label = $Name.PadRight(32, '.')

    if (-not $Global:BuildSteps) {
        $Global:BuildSteps = New-Object System.Collections.ArrayList
    }

    $null = $Global:BuildSteps.Add([pscustomobject]@{
        Step     = ("{0}/{1}" -f $Step, $Total)
        Name     = $Name
        Severity = $Severity
        Status   = $Status
        Detail   = $Detail
    })

    switch ($Status) {
        "OK" {
            Write-Host ("{0} [{1}] {2} " -f $Prefix, $SeverityLabel, $Label) -NoNewline -ForegroundColor White
            Write-Host "OK" -ForegroundColor Green
        }
        "FAIL" {
            Write-Host ("{0} [{1}] {2} " -f $Prefix, $SeverityLabel, $Label) -NoNewline -ForegroundColor White
            Write-Host "FAIL" -ForegroundColor Red
            if (-not [string]::IsNullOrWhiteSpace($Detail)) {
                Write-Host ("        {0}" -f $Detail) -ForegroundColor Red
            }
        }
        "WARN" {
            Write-Host ("{0} [{1}] {2} " -f $Prefix, $SeverityLabel, $Label) -NoNewline -ForegroundColor White
            Write-Host "WARN" -ForegroundColor Yellow
            if (-not [string]::IsNullOrWhiteSpace($Detail)) {
                Write-Host ("        {0}" -f $Detail) -ForegroundColor Yellow
            }
        }
    }
}


function Format-ElapsedTime {
    param([timespan]$Elapsed)

    if ($Elapsed.TotalSeconds -lt 1) {
        return ("{0} ms" -f [math]::Round($Elapsed.TotalMilliseconds))
    }

    if ($Elapsed.TotalHours -ge 1) {
        return ("{0:00}:{1:00}:{2:00}" -f [math]::Floor($Elapsed.TotalHours), $Elapsed.Minutes, $Elapsed.Seconds)
    }

    return ("{0:00}:{1:00}" -f [math]::Floor($Elapsed.TotalMinutes), $Elapsed.Seconds)
}

function Write-Footer {
    param(
        [ValidateSet("Success", "Error", "Cancelled", "Warning")]
        [string]$Result
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ("{0} v{1}" -f $Global:ToolName, $Global:ToolVersion) -ForegroundColor White
    Write-Host ""

    switch ($Result) {
        "Success"   { Write-Host "Completed Successfully" -ForegroundColor Green }
        "Error"     { Write-Host "Completed with Errors" -ForegroundColor Red }
        "Cancelled" { Write-Host "Cancelled" -ForegroundColor Yellow }
        "Warning"   { Write-Host "Completed with Warnings" -ForegroundColor Yellow }
    }

    Write-Host "============================================================" -ForegroundColor Cyan
}

function Pause-ForExit {
    try {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        $null = Read-Host "Press Enter to exit"
    }
}

# ============================================================
# Detection helpers
# ============================================================

function Test-IsAdministrator {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-WinPESourcePath {
    $Root = $Global:SelectedADKRoot

    if ([string]::IsNullOrWhiteSpace($Root)) {
        switch ($Global:Config.General.DefaultWinPESource) {
            "PrimarySite"      { $Root = $Global:Config.General.PrimarySiteADKRoot }
            "LocalWorkstation" { $Root = $Global:Config.General.LocalADKRoot }
            default            { $Root = $Global:Config.General.LocalADKRoot }
        }
    }

    return (Join-Path $Root "Assessment and Deployment Kit\Windows Preinstallation Environment\amd64\en-us\winpe.wim")
}

function Select-WinPESource {
    $PrimaryRoot = $Global:Config.General.PrimarySiteADKRoot
    $LocalRoot   = $Global:Config.General.LocalADKRoot

    $DefaultChoice = "1"
    if ($Global:Config.General.DefaultWinPESource -eq "LocalWorkstation") {
        $DefaultChoice = "2"
    }

    do {
        Write-Header $Global:ToolName
        Write-Host "WinPE Source Selection" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "The source WinPE.wim is copied locally before customization."
        Write-Host "The source is never mounted or modified directly."
        Write-Host ""
        Write-Host "  1. Primary Site ADK  - Preferred for ConfigMgr ADK/WinPE version alignment"
        Write-Host "     $PrimaryRoot"
        Write-Host ""
        Write-Host "  2. Local Workstation ADK - Fallback for recovery/testing"
        Write-Host "     $LocalRoot"
        Write-Host ""
        Write-Host "  3. Exit"
        Write-Host ""

        $Selection = (Read-Host "Select WinPE source [1-3] or press Enter for default [$DefaultChoice]").Trim()

        if ([string]::IsNullOrWhiteSpace($Selection)) {
            $Selection = $DefaultChoice
        }

        switch ($Selection) {
            "1" {
                $Global:WinPESourceMode = "Primary Site ADK"
                $Global:SelectedADKRoot = $PrimaryRoot
                $Global:SourceBootWim = Get-WinPESourcePath
            }
            "2" {
                $Global:WinPESourceMode = "Local Workstation ADK"
                $Global:SelectedADKRoot = $LocalRoot
                $Global:SourceBootWim = Get-WinPESourcePath
            }
            "3" {
                Write-Host ""
                Write-Host "Exiting $Global:ToolName." -ForegroundColor Yellow
                exit 0
            }
            default {
                $Global:WinPESourceMode = $null
                Write-Host ""
                Write-Host "Invalid selection. Enter 1, 2, or 3." -ForegroundColor Red
            }
        }
    } until (-not [string]::IsNullOrWhiteSpace($Global:WinPESourceMode))
}

function Get-RegistryProductVersion {
    param([string[]]$NamePatterns)

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($RegistryPath in $RegistryPaths) {
        foreach ($Pattern in $NamePatterns) {
            $Products = Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.PSObject.Properties.Name -contains "DisplayName" -and
                    $_.DisplayName -like $Pattern
                } |
                Sort-Object {
                    if ($_.PSObject.Properties.Name -contains "DisplayVersion") { $_.DisplayVersion }
                    elseif ($_.PSObject.Properties.Name -contains "Version") { $_.Version }
                    else { "" }
                } -Descending

            foreach ($Product in $Products) {
                if ($Product.PSObject.Properties.Name -contains "DisplayVersion" -and $Product.DisplayVersion) {
                    return $Product.DisplayVersion
                }

                if ($Product.PSObject.Properties.Name -contains "Version" -and $Product.Version) {
                    return $Product.Version
                }
            }
        }
    }

    return $null
}

function Get-WindowsADKVersion {
    $Version = Get-RegistryProductVersion -NamePatterns @(
        "Windows Assessment and Deployment Kit*",
        "*Windows Assessment and Deployment Kit*"
    )

    if ($Version) { return $Version }

    $Oscdimg = Join-Path $Global:Config.General.ADKRoot "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    if (Test-Path $Oscdimg) {
        try {
            $FileVersion = (Get-Item $Oscdimg -ErrorAction Stop).VersionInfo.ProductVersion
            if ($FileVersion) { return $FileVersion }
        }
        catch {}
    }

    if (Test-Path (Join-Path $Global:Config.General.ADKRoot "Assessment and Deployment Kit")) {
        return "Detected"
    }

    return "Not detected"
}

function Get-WinPEAddonVersion {
    $Version = Get-RegistryProductVersion -NamePatterns @(
        "Windows Preinstallation Environment Add-ons*",
        "Windows PE add-on*",
        "*Windows Preinstallation Environment*",
        "*Windows PE Add-on*"
    )

    if ($Version) { return $Version }

    $WinPESource = Get-WinPESourcePath
    if (Test-Path $WinPESource) {
        try {
            $FileVersion = (Get-Item $WinPESource -ErrorAction Stop).VersionInfo.ProductVersion
            if ($FileVersion) { return $FileVersion }
        }
        catch {}

        return "Detected"
    }

    return "Not detected"
}

function Get-DISMVersion {
    if (Test-Path $Global:Config.General.DISMPath) {
        try {
            $Version = (Get-Item $Global:Config.General.DISMPath -ErrorAction Stop).VersionInfo.ProductVersion
            if ($Version) { return $Version }
        }
        catch {}

        return "Detected"
    }

    return "Not detected"
}

function Get-OperatingSystemName {
    try {
        $OS = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $DisplayVersion = $null

        try {
            $CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction Stop
            if ($CurrentVersion.DisplayVersion) {
                $DisplayVersion = $CurrentVersion.DisplayVersion
            }
            elseif ($CurrentVersion.ReleaseId) {
                $DisplayVersion = $CurrentVersion.ReleaseId
            }
        }
        catch {}

        if ($DisplayVersion) {
            return ("{0} {1}" -f $OS.Caption, $DisplayVersion)
        }

        return $OS.Caption
    }
    catch {
        return [System.Environment]::OSVersion.VersionString
    }
}

function Get-FileCountSafe {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return 0 }

    try {
        return @(Get-ChildItem -Path $Path -Recurse -File -ErrorAction Stop).Count
    }
    catch {
        return 0
    }
}

function Get-DriverInfCountSafe {
    param([string]$Path)

    if (-not (Test-Path $Path)) { return 0 }

    try {
        return @(Get-ChildItem -Path $Path -Recurse -Filter "*.inf" -File -ErrorAction Stop).Count
    }
    catch {
        return 0
    }
}

# ============================================================
# Logging
# ============================================================

function Initialize-LogPath {
    $RunId = Get-Date -Format "MM-dd-yyyy_hh.mm.ss_tt"
    $Root = Join-Path $Global:Config.General.WorkingRoot "Logs"

    if (-not (Test-Path $Root)) {
        New-Item -Path $Root -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    $Global:RunId = $RunId
    $Global:StartupLogFile = Join-Path $Root ("Startup_{0}.log" -f $RunId)
}

function Write-Log {
    param(
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info",

        [string]$Component = "Main"
    )

    if ($null -eq $Message) {
        $Message = ""
    }

    $Type = switch ($Level) {
        "Info"    { 1 }
        "Warning" { 2 }
        "Error"   { 3 }
    }

    $Bias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
    if ($Bias -ge 0) { $Bias = "+$Bias" }

    $Time    = "$(Get-Date -Format "HH:mm:ss.fff")$Bias"
    $Date    = Get-Date -Format "MM-dd-yyyy"
    $Thread  = [System.Threading.Thread]::CurrentThread.ManagedThreadId
    $Context = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    $Line = "<![LOG[$Message]LOG]!>" +
            "<time=`"$Time`" " +
            "date=`"$Date`" " +
            "component=`"$Component`" " +
            "context=`"$Context`" " +
            "type=`"$Type`" " +
            "thread=`"$Thread`" " +
            "file=`"`">"

    $TargetLog = $Global:LogFile
    if ([string]::IsNullOrWhiteSpace($TargetLog)) {
        $TargetLog = $Global:StartupLogFile
    }

    try {
        $Folder = Split-Path $TargetLog -Parent
        if (-not (Test-Path $Folder)) {
            New-Item -Path $Folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }

        Add-Content -Path $TargetLog -Value $Line -Encoding Default -ErrorAction Stop
    }
    catch {}
}

function Write-AuditLine {
    param(
        [AllowEmptyString()]
        [string]$Message = "",

        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )

    if ($null -eq $Message) {
        $Message = ""
    }

    Write-Log -Message $Message -Level $Level -Component "Audit"
}

function ConvertTo-HtmlSafe {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-HtmlReportPath {
    param(
        [ValidateSet("Validation", "Build", "Cleanup")]
        [string]$ReportType
    )

    if (-not (Test-Path $Global:ReportFolder)) {
        New-Item -Path $Global:ReportFolder -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    }

    return (Join-Path $Global:ReportFolder ("{0}_{1}_{2}.html" -f $ReportType, $Global:Environment, $Global:RunId))
}

function Write-HtmlReport {
    param(
        [ValidateSet("Validation", "Build", "Cleanup")]
        [string]$ReportType,

        [ValidateSet("Success", "Failed", "Cancelled", "Warning")]
        [string]$Status,

        [datetime]$Started,

        [datetime]$Completed,

        [array]$ValidationResults = @(),

        [hashtable]$BuildInfo = @{},

        [array]$DriverInventory = @()
    )

    $Elapsed = New-TimeSpan -Start $Started -End $Completed
    $ReportPath = New-HtmlReportPath -ReportType $ReportType

    $StatusClass = "success"
    $StatusText = "$ReportType PASSED"
    $StatusIcon = "&#10004;"
    if ($Status -eq "Failed") {
        $StatusClass = "failed"
        $StatusText = "$ReportType FAILED"
        $StatusIcon = "&#10006;"
    }
    if ($Status -eq "Cancelled") {
        $StatusClass = "warning"
        $StatusText = "$ReportType CANCELLED"
        $StatusIcon = "&#9888;"
    }
    if ($Status -eq "Warning") {
        $StatusClass = "warning"
        $StatusText = "$ReportType COMPLETED WITH WARNINGS"
        $StatusIcon = "&#9888;"
    }

    $PassedCount = 0
    $FailedCount = 0
    $TotalCount = 0

    if ($ValidationResults -and $ValidationResults.Count -gt 0) {
        $PassedCount = @($ValidationResults | Where-Object { $_.Passed }).Count
        $FailedCount = @($ValidationResults | Where-Object { -not $_.Passed }).Count
        $TotalCount = $ValidationResults.Count
    }

    $Rows = ""
    foreach ($Result in $ValidationResults) {
        if ($Result.Passed) {
            $Rows += "<tr class='success'><td>$(ConvertTo-HtmlSafe $Result.Name)</td><td><span class='status-pill success'>&#10004; PASS</span></td><td>$(ConvertTo-HtmlSafe $Result.Expected)</td><td></td></tr>`r`n"
        }
        else {
            $Rows += "<tr class='failed'><td>$(ConvertTo-HtmlSafe $Result.Name)</td><td><span class='status-pill failed'>&#10006; FAIL</span></td><td>$(ConvertTo-HtmlSafe $Result.Expected)</td><td>$(ConvertTo-HtmlSafe $Result.Reason)</td></tr>`r`n"
        }
    }

    $ValidationSection = ""
    if ($ValidationResults -and $ValidationResults.Count -gt 0) {
        $ValidationSection = @"
<section class="card">
<h2>Validation</h2>
<table>
<tr><th>Check</th><th>Status</th><th>Expected</th><th>Reason</th></tr>
$Rows
</table>
</section>
"@
    }

    $BuildRows = ""
    foreach ($Key in ($BuildInfo.Keys | Sort-Object)) {
        if ($Key -notin @("OutputFolder", "OutputFile", "OutputPath", "SizeMB", "SHA256", "Created", "Status")) {
            $BuildRows += "<tr><td>$(ConvertTo-HtmlSafe $Key)</td><td>$(ConvertTo-HtmlSafe $BuildInfo[$Key])</td></tr>`r`n"
        }
    }

    $BuildSummarySection = ""
    if ($ReportType -eq "Build" -and -not [string]::IsNullOrWhiteSpace($BuildRows)) {
        $BuildSummarySection = @"
<section class="card">
<h2>Build Summary</h2>
<table>
<tr><th>Item</th><th>Value</th></tr>
$BuildRows
</table>
</section>
"@
    }

    $BuildOutputSection = ""
    if ($ReportType -eq "Build") {
        $OutputFolder = ConvertTo-HtmlSafe $BuildInfo["OutputFolder"]
        $OutputFile = ConvertTo-HtmlSafe $BuildInfo["OutputFile"]
        $OutputPath = ConvertTo-HtmlSafe $BuildInfo["OutputPath"]
        $SizeMB = ConvertTo-HtmlSafe $BuildInfo["SizeMB"]
        $SHA256 = ConvertTo-HtmlSafe $BuildInfo["SHA256"]
        $Created = ConvertTo-HtmlSafe $BuildInfo["Created"]

        $BuildOutputSection = @"
<section class="card">
<h2>Build Output</h2>
<table>
<tr><td>Output Folder</td><td>$OutputFolder</td></tr>
<tr><td>Output File</td><td>$OutputFile</td></tr>
<tr><td>Full Path</td><td>$OutputPath</td></tr>
<tr><td>Size</td><td>$SizeMB</td></tr>
<tr><td>SHA256</td><td><code>$SHA256</code></td></tr>
<tr><td>Created</td><td>$Created</td></tr>
</table>
</section>
"@
    }

    $StepRows = ""
    if ($ReportType -eq "Build" -and $Global:BuildSteps) {
        foreach ($Step in $Global:BuildSteps) {
            $RowClass = "success"
            $StepStatus = "<span class='status-pill success'>&#10004; SUCCESS</span>"
            if ($Step.Status -eq "FAIL") {
                $RowClass = "failed"
                $StepStatus = "<span class='status-pill failed'>&#10006; FAILED</span>"
            }
            elseif ($Step.Status -eq "WARN") {
                $RowClass = "warning"
                $StepStatus = "<span class='status-pill warning'>&#9888; WARNING</span>"
            }

            $StepRows += "<tr class='$RowClass'><td>$(ConvertTo-HtmlSafe $Step.Step)</td><td>$(ConvertTo-HtmlSafe $Step.Name)</td><td>$(ConvertTo-HtmlSafe $Step.Severity)</td><td>$StepStatus</td><td>$(ConvertTo-HtmlSafe $Step.Detail)</td></tr>`r`n"
        }
    }

    $DeploymentSection = ""
    if ($ReportType -eq "Build" -and -not [string]::IsNullOrWhiteSpace($StepRows)) {
        $DeploymentSection = @"
<section class="card">
<h2>Deployment Report</h2>
<table>
<tr><th>Step</th><th>Action</th><th>Severity</th><th>Status</th><th>Detail</th></tr>
$StepRows
</table>
</section>
"@
    }

    $DriverRows = ""
    $TotalInf = 0
    foreach ($Item in $DriverInventory) {
        $TotalInf += [int]$Item.InfCount
        $PackageName = if ($Item.PackageName) { $Item.PackageName } else { $Item.Group }
        $DriverRows += "<tr><td><strong>$(ConvertTo-HtmlSafe $PackageName)</strong></td><td>$(ConvertTo-HtmlSafe $Item.InfCount)</td><td>$(ConvertTo-HtmlSafe $Item.DriverTypes)</td><td>$(ConvertTo-HtmlSafe $Item.Providers)</td><td><code>$(ConvertTo-HtmlSafe $Item.Path)</code></td></tr>`r`n"
    }

    $DriverSection = ""
    if ($ReportType -eq "Build" -and -not [string]::IsNullOrWhiteSpace($DriverRows)) {
        $DriverSection = @"
<section class="card">
<h2>Driver Packages Injected</h2>
<div class="summary-line"><strong>$($DriverInventory.Count)</strong> Driver Packages &nbsp; | &nbsp; <strong>$TotalInf</strong> INF Files</div>
<table>
<tr><th>Package</th><th>INF Files</th><th>Driver Type</th><th>Provider</th><th>Source Path</th></tr>
$DriverRows
</table>
</section>
"@
    }

    $PackageSection = ""
    if ($ReportType -eq "Build") {
        $DriverPackages = 0
        if ($DriverInventory) { $DriverPackages = $DriverInventory.Count }
        $PackageSection = @"
<section class="card">
<h2>Package Summary</h2>
<table>
<tr><td>Driver Packages</td><td>$DriverPackages</td></tr>
<tr><td>INF Files</td><td>$TotalInf</td></tr>
<tr><td>Extra Files</td><td>$(ConvertTo-HtmlSafe $BuildInfo["ExtraFiles"])</td></tr>
<tr><td>Background</td><td>$(ConvertTo-HtmlSafe $BuildInfo["Background"])</td></tr>
<tr><td>WinPEGen</td><td>$(ConvertTo-HtmlSafe $BuildInfo["WinPEGen"])</td></tr>
</table>
</section>
"@
    }

    $ChecksCard = $TotalCount
    if ($ReportType -eq "Build") {
        $ChecksCard = if ($Global:BuildSteps) { $Global:BuildSteps.Count } else { 0 }
        $PassedCount = if ($Global:BuildSteps) { @($Global:BuildSteps | Where-Object { $_.Status -eq "OK" }).Count } else { 0 }
        $FailedCount = if ($Global:BuildSteps) { @($Global:BuildSteps | Where-Object { $_.Status -eq "FAIL" }).Count } else { 0 }
    }

    $BuildScoreCard = ""
    if ($ReportType -eq "Build") {
        $BuildScoreCard = '<div class="metric"><div class="label">Build Score</div><div class="value">' + (ConvertTo-HtmlSafe $BuildInfo["BuildScore"]) + '</div></div>'
    }

    $SystemInfoSection = @"
    <section class="card">
        <h2>System Information</h2>
        <table>
            <tr><td>Computer</td><td>$(ConvertTo-HtmlSafe $env:COMPUTERNAME)</td></tr>
            <tr><td>User</td><td>$(ConvertTo-HtmlSafe ([Security.Principal.WindowsIdentity]::GetCurrent().Name))</td></tr>
            <tr><td>Operating Sys.</td><td>$(ConvertTo-HtmlSafe (Get-OperatingSystemName))</td></tr>
            <tr><td>PowerShell</td><td>$(ConvertTo-HtmlSafe $PSVersionTable.PSVersion.ToString())</td></tr>
            <tr><td>Windows ADK</td><td>$(ConvertTo-HtmlSafe (Get-WindowsADKVersion))</td></tr>
            <tr><td>WinPE Add-on</td><td>$(ConvertTo-HtmlSafe (Get-WinPEAddonVersion))</td></tr>
            <tr><td>DISM</td><td>$(ConvertTo-HtmlSafe (Get-DISMVersion))</td></tr>
        </table>
    </section>
"@


    $Html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8" />
<title>$($Global:ToolName) $ReportType Report</title>
<style>
:root {
    --preferredhomeoffers-green: #80BB46;
    --preferredhomeoffers-dark-green: #5E9F2E;
    --preferredhomeoffers-light-green: #F0F8EA;
    --danger: #B91C1C;
    --warning: #B45309;
    --text: #1F2937;
    --muted: #6B7280;
    --border: #D1D5DB;
    --background: #F3F4F6;
    --card: #FFFFFF;
}
* { box-sizing: border-box; }
body {
    margin: 0;
    background: var(--background);
    color: var(--text);
    font-family: "Segoe UI Variable", "Segoe UI", Arial, sans-serif;
}
.header {
    background: linear-gradient(135deg, #5E9F2E, #80BB46);
    color: #fff;
    padding: 28px 36px;
}
.header h1 { margin: 0; font-size: 28px; font-weight: 700; }
.header .subtitle { margin-top: 6px; font-size: 16px; opacity: 0.95; }
.header .team { margin-top: 2px; font-size: 14px; opacity: 0.85; }
.container { max-width: 1200px; margin: 24px auto; padding: 0 24px; }
.banner {
    border-radius: 10px;
    padding: 18px 22px;
    color: #fff;
    font-size: 20px;
    font-weight: 700;
    box-shadow: 0 6px 20px rgba(15,23,42,0.12);
}
.banner.success { background: var(--preferredhomeoffers-green); }
.banner.failed { background: var(--danger); }
.banner.warning { background: var(--warning); }
.dashboard {
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    gap: 16px;
    margin: 20px 0;
}
.metric {
    background: var(--card);
    border-radius: 10px;
    padding: 16px;
    box-shadow: 0 2px 10px rgba(15,23,42,0.08);
    border-left: 5px solid var(--preferredhomeoffers-green);
}
.metric .label { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
.metric .value { font-size: 28px; font-weight: 700; margin-top: 6px; }
.metric.failed { border-left-color: var(--danger); }
.metric.warning { border-left-color: var(--warning); }
.card {
    background: var(--card);
    border-radius: 10px;
    padding: 20px;
    margin: 18px 0;
    box-shadow: 0 2px 10px rgba(15,23,42,0.08);
}
h2 { margin: 0 0 14px 0; font-size: 20px; color: var(--preferredhomeoffers-dark-green); }
table { border-collapse: collapse; width: 100%; }
th {
    background: #111827;
    color: #fff;
    text-align: left;
    padding: 10px;
    font-weight: 600;
}
td { border: 1px solid var(--border); padding: 10px; vertical-align: top; }
tr:nth-child(even) td { background: #FAFAFA; }
.status-pill {
    display: inline-block;
    border-radius: 999px;
    color: #fff;
    font-weight: 700;
    padding: 4px 10px;
    font-size: 12px;
}
.status-pill.success { background: var(--preferredhomeoffers-green); }
.status-pill.failed { background: var(--danger); }
.status-pill.warning { background: var(--warning); }
code {
    background: #F3F4F6;
    border: 1px solid #E5E7EB;
    border-radius: 4px;
    padding: 2px 4px;
    word-break: break-all;
}
.summary-line {
    background: var(--preferredhomeoffers-light-green);
    border-left: 4px solid var(--preferredhomeoffers-green);
    padding: 10px 12px;
    margin-bottom: 12px;
    border-radius: 6px;
}
.footer { margin: 26px 0; color: var(--muted); font-size: 12px; text-align: center; }
@media (max-width: 800px) {
    .dashboard { grid-template-columns: 1fr 1fr; }
}
@media (max-width: 520px) {
    .dashboard { grid-template-columns: 1fr; }
    .container { padding: 0 12px; }
}
</style>
</head>
<body>
<div class="header">
    <h1>$($Global:ToolName)</h1>
    <div class="subtitle">Enterprise Boot Image Build Report</div>
    <div class="team">$($Global:CompanyName) Endpoint Engineering</div>
</div>

<div class="container">
    <div class="banner $StatusClass">$StatusIcon $StatusText</div>

    <div class="dashboard">
        <div class="metric $StatusClass"><div class="label">Status</div><div class="value">$Status</div></div>
        <div class="metric"><div class="label">Checks</div><div class="value">$ChecksCard</div></div>
        <div class="metric"><div class="label">Passed</div><div class="value">$PassedCount</div></div>
        <div class="metric failed"><div class="label">Failed</div><div class="value">$FailedCount</div></div>
        $BuildScoreCard
    </div>

    $SystemInfoSection

    <section class="card">
        <h2>Run Details</h2>
        <table>
            <tr><td>Environment</td><td>$(ConvertTo-HtmlSafe $Global:Environment)</td></tr>
            <tr><td>Boot Image</td><td>$(ConvertTo-HtmlSafe $Global:EnvConfig.BootImageName)</td></tr>
            <tr><td>WinPE Source Mode</td><td>$(ConvertTo-HtmlSafe $Global:WinPESourceMode)</td></tr>
            <tr><td>Selected ADK Root</td><td>$(ConvertTo-HtmlSafe $Global:SelectedADKRoot)</td></tr>
            <tr><td>Source WinPE</td><td>$(ConvertTo-HtmlSafe $Global:SourceBootWim)</td></tr>
            <tr><td>Computer</td><td>$(ConvertTo-HtmlSafe $env:COMPUTERNAME)</td></tr>
            <tr><td>User</td><td>$(ConvertTo-HtmlSafe ([Security.Principal.WindowsIdentity]::GetCurrent().Name))</td></tr>
            <tr><td>Started</td><td>$(ConvertTo-HtmlSafe $Started.ToString("MM/dd/yyyy hh:mm:ss tt"))</td></tr>
            <tr><td>Completed</td><td>$(ConvertTo-HtmlSafe $Completed.ToString("MM/dd/yyyy hh:mm:ss tt"))</td></tr>
            <tr><td>Elapsed</td><td>$(ConvertTo-HtmlSafe (Format-ElapsedTime -Elapsed $Elapsed))</td></tr>
            <tr><td>CMTrace Log</td><td>$(ConvertTo-HtmlSafe $Global:LogFile)</td></tr>
        </table>
    </section>

    $ValidationSection
    $DeploymentSection
    $BuildSummarySection
    $BuildOutputSection
    $DriverSection
    $PackageSection

    <div class="footer">Generated by $($Global:ToolName) v$($Global:ToolVersion)</div>
</div>
</body>
</html>
"@

    try {
        $Html | Out-File -FilePath $ReportPath -Encoding UTF8 -Force
        Write-AuditLine "HTML report created: $ReportPath"
        return $ReportPath
    }
    catch {
        Write-AuditLine "HTML report failed: $($_.Exception.Message)" "Warning"
        return $null
    }
}



function Resolve-InfStringValue {
    param(
        [string]$Text,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $CleanValue = $Value.Trim().Trim('"')

    if ($CleanValue -match '^%(.+)%$') {
        $Key = [regex]::Escape($Matches[1])
        $Match = [regex]::Match($Text, "(?im)^\s*$Key\s*=\s*(.+?)\s*$")
        if ($Match.Success) {
            return $Match.Groups[1].Value.Trim().Trim('"')
        }
    }

    return $CleanValue
}

function Get-InfFieldValue {
    param(
        [string]$InfPath,
        [string]$FieldName
    )

    try {
        $Text = Get-Content -Path $InfPath -Raw -ErrorAction Stop
        $Field = [regex]::Escape($FieldName)
        $Match = [regex]::Match($Text, "(?im)^\s*$Field\s*=\s*(.+?)\s*$")

        if ($Match.Success) {
            return (Resolve-InfStringValue -Text $Text -Value $Match.Groups[1].Value)
        }
    }
    catch {}

    return ""
}

function Get-DriverPackageMetadata {
    param([string]$PackagePath)

    $InfFiles = @(Get-ChildItem -Path $PackagePath -Recurse -Filter "*.inf" -File -ErrorAction SilentlyContinue)
    $Providers = New-Object System.Collections.ArrayList
    $Classes = New-Object System.Collections.ArrayList

    foreach ($Inf in $InfFiles) {
        $Provider = Get-InfFieldValue -InfPath $Inf.FullName -FieldName "Provider"
        $Class = Get-InfFieldValue -InfPath $Inf.FullName -FieldName "Class"

        if (-not [string]::IsNullOrWhiteSpace($Provider) -and $Providers -notcontains $Provider) {
            $null = $Providers.Add($Provider)
        }

        if (-not [string]::IsNullOrWhiteSpace($Class) -and $Classes -notcontains $Class) {
            $null = $Classes.Add($Class)
        }
    }

    $InfFileNames = @($InfFiles | Select-Object -ExpandProperty Name -Unique | Sort-Object)
    $InfPreview = ""
    if ($InfFileNames.Count -gt 0) {
        $FirstFiles = @($InfFileNames | Select-Object -First 12)
        $InfPreview = ($FirstFiles -join ", ")
        if ($InfFileNames.Count -gt 12) {
            $InfPreview = "$InfPreview, ... (+$($InfFileNames.Count - 12) more)"
        }
    }

    return [pscustomobject]@{
        InfCount    = $InfFiles.Count
        Providers   = if ($Providers.Count -gt 0) { (@($Providers | Sort-Object) -join ", ") } else { "Unknown" }
        DriverTypes = if ($Classes.Count -gt 0) { (@($Classes | Sort-Object) -join ", ") } else { "Unknown" }
        InfFiles    = $InfPreview
    }
}

function Get-DriverInventory {
    param([string]$Path)

    $Inventory = New-Object System.Collections.ArrayList

    if (-not (Test-Path $Path)) {
        return @()
    }

    try {
        $ChildFolders = @(Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue)

        if ($ChildFolders.Count -gt 0) {
            foreach ($Folder in $ChildFolders) {
                $Metadata = Get-DriverPackageMetadata -PackagePath $Folder.FullName
                $null = $Inventory.Add([pscustomobject]@{
                    PackageName = $Folder.Name
                    Group       = $Folder.Name
                    InfCount    = $Metadata.InfCount
                    Providers   = $Metadata.Providers
                    DriverTypes = $Metadata.DriverTypes
                    InfFiles    = $Metadata.InfFiles
                    Path        = $Folder.FullName
                })
            }
        }
        else {
            $Metadata = Get-DriverPackageMetadata -PackagePath $Path
            $PackageName = Split-Path -Path $Path -Leaf
            if ([string]::IsNullOrWhiteSpace($PackageName)) { $PackageName = "Root" }

            $null = $Inventory.Add([pscustomobject]@{
                PackageName = $PackageName
                Group       = $PackageName
                InfCount    = $Metadata.InfCount
                Providers   = $Metadata.Providers
                DriverTypes = $Metadata.DriverTypes
                InfFiles    = $Metadata.InfFiles
                Path        = $Path
            })
        }
    }
    catch {}

    return @($Inventory | Sort-Object PackageName)
}

function Write-DriverInjectionSummary {
    param([array]$Inventory)

    Write-Section "Driver Packages to Inject"
    Write-Field "OSD Boot Driver Source" $Global:EnvConfig.BootDriverSource
    Write-Host ""

    if (-not $Inventory -or $Inventory.Count -eq 0) {
        Write-Host "No driver inventory found." -ForegroundColor Yellow
        Write-AuditLine "Driver Inventory | TotalPackages=0 | TotalInf=0" "Warning"
        return
    }

    $TotalInf = 0
    foreach ($Item in $Inventory) {
        $TotalInf += [int]$Item.InfCount
        $Name = if ($Item.PackageName) { $Item.PackageName } else { $Item.Group }
        $Label = $Name.PadRight(34, '.')
        Write-Host ("[ OK ] {0} " -f $Label) -NoNewline -ForegroundColor White
        Write-Host ("{0} INF" -f $Item.InfCount) -ForegroundColor Green

        if ($Item.DriverTypes -and $Item.DriverTypes -ne "Unknown") {
            Write-Host ("       Type     : {0}" -f $Item.DriverTypes) -ForegroundColor DarkGray
        }
        if ($Item.Providers -and $Item.Providers -ne "Unknown") {
            Write-Host ("       Provider : {0}" -f $Item.Providers) -ForegroundColor DarkGray
        }

        Write-AuditLine ("Driver Package | Name={0} | InfCount={1} | Type={2} | Provider={3} | Path={4}" -f $Name, $Item.InfCount, $Item.DriverTypes, $Item.Providers, $Item.Path)
    }

    Write-Host ""
    Write-Field "Total Packages" $Inventory.Count
    Write-Field "Total INF" $TotalInf
    Write-AuditLine ("Driver Inventory | TotalPackages={0} | TotalInf={1}" -f $Inventory.Count, $TotalInf)
}

function Write-AuditExecutionStart {
    Write-AuditLine "============================================================"
    Write-AuditLine ("{0} v{1}" -f $Global:ToolName, $Global:ToolVersion)
    Write-AuditLine "============================================================"
    Write-AuditLine ""
    Write-AuditLine "Execution Started"
    Write-AuditLine "-----------------"
    Write-AuditLine ("Company............. {0}" -f $Global:CompanyName)
    Write-AuditLine ("Environment......... {0}" -f $Global:Environment)
    Write-AuditLine ("Boot Image.......... {0}" -f $Global:EnvConfig.BootImageName)
    Write-AuditLine ("User................ {0}" -f ([Security.Principal.WindowsIdentity]::GetCurrent().Name))
    Write-AuditLine ("Computer............ {0}" -f $env:COMPUTERNAME)
    Write-AuditLine ("Action.............. {0}" -f $Global:Action)
    Write-AuditLine ("Log................. {0}" -f $Global:LogFile)
    Write-AuditLine ""
}


function Write-AuditValidationSummary {
    param(
        [array]$Results,
        [int]$PassedCount,
        [int]$FailedCount,
        [int]$TotalCount
    )

    Write-AuditLine "Validation"
    Write-AuditLine "----------"

    foreach ($Result in $Results) {
        if ($Result.Passed) {
            Write-AuditLine ("PASS  {0}" -f $Result.Name)
        }
        else {
            Write-AuditLine ("FAIL  {0}" -f $Result.Name) "Error"
            Write-AuditLine ("      Expected: {0}" -f $Result.Expected) "Error"
            Write-AuditLine ("      Reason..: {0}" -f $Result.Reason) "Error"
        }
    }

    Write-AuditLine ""
    Write-AuditLine "Summary"
    Write-AuditLine "-------"
    Write-AuditLine ("Passed.............. {0}" -f $PassedCount)
    Write-AuditLine ("Failed.............. {0}" -f $FailedCount)
    Write-AuditLine ("Total............... {0}" -f $TotalCount)

    if ($FailedCount -eq 0) {
        Write-AuditLine "Result.............. PASSED"
    }
    else {
        Write-AuditLine "Result.............. FAILED" "Error"
    }

    Write-AuditLine ""
}


function Show-StartupBanner {
    Initialize-LogPath

    $Computer = $env:COMPUTERNAME
    $User = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $Date = Get-Date -Format "MM/dd/yyyy hh:mm tt"
    $OSName = Get-OperatingSystemName
    $PSVersion = $PSVersionTable.PSVersion.ToString()
    $ADKVersion = Get-WindowsADKVersion
    $WinPEAddonVersion = Get-WinPEAddonVersion
    $DISMVersion = Get-DISMVersion
    $WinPESource = $Global:SourceBootWim

    if ([string]::IsNullOrWhiteSpace($WinPESource)) {
        $WinPESource = Get-WinPESourcePath
        $Global:SourceBootWim = $WinPESource
    }

    Write-Header $Global:ToolName
    Write-Field "Version" $Global:ToolVersion
    Write-Field "Company" $Global:CompanyName
    Write-Host ""
    Write-Field "Computer" $Computer
    Write-Field "User" $User
    Write-Host ""
    Write-Field "Operating Sys." $OSName
    Write-Field "PowerShell" $PSVersion
    Write-Host ""
    Write-Field "Windows ADK" $ADKVersion
    Write-Field "WinPE Add-on" $WinPEAddonVersion
    Write-Field "DISM" $DISMVersion
    Write-Host ""
    Write-Field "Build Source" $Global:WinPESourceMode
    Write-Field "Source WIM" $WinPESource
    Write-Host ""
    Write-Field "Date" $Date

    Write-Section "System Check"

    $SystemCheckFailed = $false

    if (Test-IsAdministrator) {
        Write-CheckResult -Name "Administrator" -Status "OK"
    }
    else {
        Write-CheckResult -Name "Administrator" -Status "FAIL"
        $SystemCheckFailed = $true
    }

    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Write-CheckResult -Name "PowerShell" -Status "OK"
    }
    else {
        Write-CheckResult -Name "PowerShell" -Status "FAIL"
        $SystemCheckFailed = $true
    }

    if (Test-Path (Join-Path $Global:SelectedADKRoot "Assessment and Deployment Kit")) {
        Write-CheckResult -Name "Windows ADK" -Status "OK"
    }
    else {
        Write-CheckResult -Name "Windows ADK" -Status "FAIL"
        $SystemCheckFailed = $true
    }

    if (Test-Path $Global:Config.General.DISMPath) {
        Write-CheckResult -Name "DISM" -Status "OK"
    }
    else {
        Write-CheckResult -Name "DISM" -Status "FAIL"
        $SystemCheckFailed = $true
    }

    if (Test-Path $WinPESource) {
        Write-CheckResult -Name "Build Source" -Status "OK"
    }
    else {
        Write-CheckResult -Name "Build Source" -Status "FAIL"
        $SystemCheckFailed = $true
    }

    if ($SystemCheckFailed) {
        Write-Host ""
        Write-Host "System check failed. Review the failed item above." -ForegroundColor Red
        Write-Host ""
        Write-Host "Selected build source:" -ForegroundColor Yellow
        Write-Host $WinPESource
        Write-Host ""
        Write-Host "If the Primary Site Server is unavailable, restart the tool and select Local Workstation ADK." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Press any key to exit..." -ForegroundColor Yellow
        Pause-ForExit
        exit 1
    }

    Write-Host ""
    Write-Host "System check completed successfully." -ForegroundColor Green

    Write-Log "Startup banner displayed"
    Write-Log "Windows ADK: $ADKVersion"
    Write-Log "WinPE Add-on: $WinPEAddonVersion"
    Write-Log "DISM: $DISMVersion"
    Write-Log "Build Source Mode: $Global:WinPESourceMode"
    Write-Log "Build Source WIM: $WinPESource"
}

function Select-Environment {
    $ValidEnvironments = @($Global:Config.Environments.Keys | Sort-Object)

    do {
        Write-Header $Global:ToolName
        Write-Host "Available Site Codes:"

        foreach ($SiteCode in $ValidEnvironments) {
            $Name = $Global:Config.Environments[$SiteCode].Name
            if ([string]::IsNullOrWhiteSpace($Name)) { $Name = $SiteCode }
            Write-Host ("  {0,-6} {1}" -f $SiteCode, $Name)
        }

        Write-Host ""

        $Selection = (Read-Host "Enter Site Code").ToUpper().Trim()

        if ($Selection -notin $ValidEnvironments) {
            Write-Host "Invalid Site Code. Try again." -ForegroundColor Red
        }
    } until ($Selection -in $ValidEnvironments)

    $Global:Environment = $Selection
    $Global:EnvConfig = $Global:Config.Environments[$Global:Environment]

    if ([string]::IsNullOrWhiteSpace($Global:EnvConfig.BootImageName)) {
        $Global:EnvConfig.BootImageName = "$Global:Environment`_Enterprise Boot Image"
    }

    # Derived values used by the build engine.
    $Global:EnvConfig.ExtraFilesSource = $Global:EnvConfig.BootExtraFilesSource

    # Fallback driver path until SharePoint driver manifest access is approved.
    $ManifestConfig = $Global:Config.General.SharePointDriverManifest
    if ([string]::IsNullOrWhiteSpace($Global:EnvConfig.BootDriverSource)) {
        $RelativeDriverPath = $ManifestConfig.FallbackDriverPathTemplate.Replace("{Profile}", $Global:EnvConfig.BootDriverProfile)
        $Global:EnvConfig.BootDriverSource = Join-Path $ManifestConfig.FallbackDriverRoot $RelativeDriverPath
    }

    $Global:BootDriverProfile = $Global:EnvConfig.BootDriverProfile
    if ([string]::IsNullOrWhiteSpace($Global:BootDriverProfile)) {
        $Global:BootDriverProfile = $Global:Environment
    }

    $Global:SourceBootWim = Get-WinPESourcePath
    $Global:WorkingRoot = Join-Path $Global:Config.General.WorkingRoot $Global:Environment
    $Global:MountFolder = Join-Path $Global:WorkingRoot "Mount"
    $Global:BuildFolder = Join-Path $Global:WorkingRoot "Build"
    $Global:LogFolder = Join-Path $Global:WorkingRoot "Logs"
    $Global:ReportFolder = Join-Path $Global:WorkingRoot "Reports"
    $Global:OutputFolder = Join-Path (Join-Path $Global:Config.General.WorkingRoot "Output") $Global:Environment

    $Global:LogFile = Join-Path $Global:LogFolder ("BootImageBuild_{0}_{1}.log" -f $Global:Environment, $Global:RunId)
    $Global:BuildWim = Join-Path $Global:BuildFolder "$($Global:EnvConfig.BootImageName).wim"
    $Global:FinalWim = Join-Path $Global:OutputFolder "$($Global:EnvConfig.BootImageName).wim"
}

function Show-CurrentConfiguration {
    Write-Section "Current Configuration"

    Write-Field "Environment" $Global:Environment
    Write-Field "Site Code" $Global:EnvConfig.SiteCode
    Write-Field "Boot Image" $Global:EnvConfig.BootImageName
    Write-Host ""
    Write-Field "Working Folder" $Global:WorkingRoot
    Write-Field "Output Folder" $Global:OutputFolder
    Write-Field "WinPE Source Mode" $Global:WinPESourceMode
    Write-Field "Selected ADK Root" $Global:SelectedADKRoot
    Write-Field "Source WinPE" $Global:SourceBootWim
    if ($Global:EnvConfig.BranchCacheEnabled) {
        Write-Field "Windows Source" $Global:Config.General.WindowsInstallWim
    }
    else {
        Write-Field "BranchCache" "Disabled for this environment"
    }
    Write-Field "Boot Driver Profile" $Global:BootDriverProfile
    Write-Host ""
    Write-Host "Content"
    Write-Host ""
    if ($Global:EnvConfig.BranchCacheEnabled) {
        Write-CheckResult -Name "BranchCache Components" -Status "OK"
    }
    Write-CheckResult -Name "OSD Boot Drivers" -Status "OK"
    Write-CheckResult -Name "OSD Boot Extra Files" -Status "OK"
    Write-CheckResult -Name "OSD TSBackground" -Status "OK"
}

function Select-Action {
    do {
        Write-Header $Global:ToolName
        Write-Field "Environment" $Global:Environment
        Write-Field "Boot Image" $Global:EnvConfig.BootImageName
        Write-Host ""
        Write-Host "Available Actions" -ForegroundColor Cyan
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  1. Build Boot Image" -ForegroundColor Green
        Write-Host "     Builds a new boot image from the Microsoft ADK."
        Write-Host ""
        Write-Host "  2. Validate Environment" -ForegroundColor Green
        Write-Host "     Checks prerequisites without mounting the WIM."
        Write-Host ""
        Write-Host "  3. Cleanup Workspace" -ForegroundColor Green
        Write-Host "     Clears stale mounts, build files, and optional output/logs."
        Write-Host ""
        Write-Host "  4. Exit" -ForegroundColor Green
        Write-Host ""

        $Selection = (Read-Host "Select an option [1-4]").Trim()

        switch ($Selection) {
            "1" { $Global:Action = "BUILD" }
            "2" { $Global:Action = "VALIDATE" }
            "3" { $Global:Action = "CLEANUP" }
            "4" {
                Write-Host ""
                Write-Host "Exiting $Global:ToolName." -ForegroundColor Yellow
                exit 0
            }
            default {
                $Global:Action = $null
                Write-Host "Invalid selection. Enter 1, 2, 3, or 4." -ForegroundColor Red
            }
        }
    } until ($Global:Action -in @("BUILD", "VALIDATE", "CLEANUP"))
}

# ============================================================
# Workspace and validation
# ============================================================

function Initialize-Workspace {
    $Paths = @(
        $Global:WorkingRoot,
        $Global:MountFolder,
        $Global:BuildFolder,
        $Global:LogFolder,
        $Global:ReportFolder,
        $Global:OutputFolder
    )

    foreach ($Path in $Paths) {
        try {
            if (-not (Test-Path $Path)) {
                New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
        }
        catch {
            throw "Unable to create or access folder: $Path. Error: $($_.Exception.Message)"
        }
    }
}

function Add-FailedCheck {
    param(
        [System.Collections.ArrayList]$FailedChecks,
        [string]$Name,
        [string]$Expected,
        [string]$Reason
    )

    $null = $FailedChecks.Add([pscustomobject]@{
        Name     = $Name
        Expected = $Expected
        Reason   = $Reason
    })
}

function New-ValidationResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Expected = "",
        [string]$Reason = ""
    )

    return [pscustomobject]@{
        Name     = $Name
        Passed   = $Passed
        Expected = $Expected
        Reason   = $Reason
    }
}

function Test-PathCheck {
    param(
        [string]$Name,
        [string]$Path
    )

    if (Test-Path $Path) {
        return New-ValidationResult -Name $Name -Passed $true -Expected $Path
    }

    $Reason = "Path not found or not reachable"
    if ([System.IO.Path]::HasExtension($Path)) {
        $Reason = "File not found"
    }
    else {
        $Reason = "Folder not found"
    }

    return New-ValidationResult -Name $Name -Passed $false -Expected $Path -Reason $Reason
}

function Write-ValidationReport {
    param(
        [array]$Results,
        [datetime]$Started,
        [datetime]$Completed
    )

    $Elapsed = New-TimeSpan -Start $Started -End $Completed
    $PassedCount = ($Results | Where-Object { $_.Passed }).Count
    $Failed = @($Results | Where-Object { -not $_.Passed })
    $FailedCount = $Failed.Count
    $TotalCount = $Results.Count

    Write-Section "Validation Report"

    foreach ($Result in $Results) {
        if ($Result.Passed) {
            Write-CheckResult -Name $Result.Name -Status "OK"
        }
        else {
            Write-CheckResult -Name $Result.Name -Status "FAIL"
        }
    }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan

    if ($FailedCount -gt 0) {
        Write-Host ("{0} " -f "Overall Result".PadRight(36, '.')) -NoNewline
        Write-Host "FAILED" -ForegroundColor Red
    }
    else {
        Write-Host ("{0} " -f "Overall Result".PadRight(36, '.')) -NoNewline
        Write-Host "PASSED" -ForegroundColor Green
    }

    if ($FailedCount -gt 0) {
        Write-Section "Failure Details"

        foreach ($Failure in $Failed) {
            Write-Host $Failure.Name -ForegroundColor Yellow
            Write-Host ("-" * $Failure.Name.Length) -ForegroundColor Yellow
            Write-Host "Expected:" -ForegroundColor Cyan
            Write-Host ("  {0}" -f $Failure.Expected)
            Write-Host ""
            Write-Host "Reason:" -ForegroundColor Cyan
            Write-Host ("  {0}" -f $Failure.Reason)
            Write-Host ""
        }
    }

    Write-Header "Validation Complete"

    if ($FailedCount -gt 0) {
        Write-Host "Status          : " -NoNewline
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host ("Build Score     : {0}%" -f $BuildHealth.Score)
    }
    else {
        Write-Host "Status          : " -NoNewline
        Write-Host "PASSED" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host ("Checks Passed   : {0}" -f $PassedCount)
    Write-Host ("Checks Failed   : {0}" -f $FailedCount)
    Write-Host ("Total Checks    : {0}" -f $TotalCount)
    Write-Host ""
    Write-Host ("Started         : {0}" -f $Started.ToString("MM/dd/yyyy hh:mm:ss tt"))
    Write-Host ("Completed       : {0}" -f $Completed.ToString("MM/dd/yyyy hh:mm:ss tt"))
    Write-Host ("Elapsed         : {0}" -f (Format-ElapsedTime -Elapsed $Elapsed))
    Write-Host ""

    if ($FailedCount -gt 0) {
        Write-Host "No changes were made." -ForegroundColor Yellow
        Write-Host "Review the Failure Details section above." -ForegroundColor Yellow
        Write-Log "Validation failed. Failed checks: $FailedCount" "Error"
        Write-Log "Summary | Status=ValidationFailed | Environment=$Global:Environment | BootImage=$($Global:EnvConfig.BootImageName) | Passed=$PassedCount | Failed=$FailedCount | Total=$TotalCount" "Error"
        Write-AuditValidationSummary -Results $Results -PassedCount $PassedCount -FailedCount $FailedCount -TotalCount $TotalCount
        $ReportPath = Write-HtmlReport -ReportType "Validation" -Status "Failed" -Started $Started -Completed $Completed -ValidationResults $Results
        if ($ReportPath) {
            Write-Host ""
            Write-Host "Report" -ForegroundColor Cyan
            Write-Host $ReportPath
        }
        Write-Footer -Result "Error"
        return $false
    }

    Write-Host "Environment is ready." -ForegroundColor Green
    Write-Log "Validation completed successfully"
    Write-Log "Summary | Status=ValidationSuccess | Environment=$Global:Environment | BootImage=$($Global:EnvConfig.BootImageName) | Passed=$PassedCount | Failed=0 | Total=$TotalCount | ChangesMade=False"
    Write-AuditValidationSummary -Results $Results -PassedCount $PassedCount -FailedCount 0 -TotalCount $TotalCount
    $ReportPath = Write-HtmlReport -ReportType "Validation" -Status "Success" -Started $Started -Completed $Completed -ValidationResults $Results
    if ($ReportPath) {
        Write-Host ""
        Write-Host "Report" -ForegroundColor Cyan
        Write-Host $ReportPath
    }
    Write-Footer -Result $(if ($BuildHealth.Health -eq "Healthy") { "Success" } else { "Warning" })
    return $true
}

function Test-EnterprisePrerequisites {
    $Started = Get-Date
    $Results = New-Object System.Collections.ArrayList

    Write-Log "Validation started for $($Global:EnvConfig.Name)"

    $null = $Results.Add((New-ValidationResult -Name "Administrator" -Passed (Test-IsAdministrator) -Expected "Elevated PowerShell session" -Reason "PowerShell is not running as Administrator"))

    $null = $Results.Add((Test-PathCheck -Name "Windows ADK" -Path (Join-Path $Global:SelectedADKRoot "Assessment and Deployment Kit")))
    $null = $Results.Add((Test-PathCheck -Name ("Build Source ({0})" -f $Global:WinPESourceMode) -Path $Global:SourceBootWim))
    $null = $Results.Add((Test-PathCheck -Name "DISM" -Path $Global:Config.General.DISMPath))

    if ($Global:EnvConfig.BranchCacheEnabled) {
        $null = $Results.Add((Test-PathCheck -Name "Windows Source" -Path $Global:Config.General.WindowsInstallWim))
        $null = $Results.Add((Test-PathCheck -Name "WinPEGen.exe" -Path $Global:Config.General.WinPEGenExe))
        $null = $Results.Add((Test-PathCheck -Name "BITSACP.exe" -Path $Global:Config.General.BITSACPSource))
        # WinPEGen.exe and BITSACP.exe are validated above. The extra files package is validated separately below.
    }
    else {
        Write-Log "BranchCache validation skipped for $Global:Environment because BranchCacheEnabled is false."
    }

    $null = $Results.Add((Test-PathCheck -Name "OSD Boot Drivers" -Path $Global:EnvConfig.BootDriverSource))
    $null = $Results.Add((Test-PathCheck -Name "OSD Boot Extra Files" -Path $Global:EnvConfig.BootExtraFilesSource))
    $null = $Results.Add((Test-PathCheck -Name "Local Output" -Path $Global:OutputFolder))

    try {
        $DriveLetter = ([System.IO.Path]::GetPathRoot($Global:WorkingRoot)).Substring(0, 1)
        $Drive = Get-PSDrive -Name $DriveLetter -ErrorAction Stop

        if ($Drive.Free -ge ($Global:Config.General.RequiredFreeSpaceGB * 1GB)) {
            $null = $Results.Add((New-ValidationResult -Name "Disk Space" -Passed $true -Expected "$DriveLetter`: drive has at least $($Global:Config.General.RequiredFreeSpaceGB) GB free"))
        }
        else {
            $null = $Results.Add((New-ValidationResult -Name "Disk Space" -Passed $false -Expected "$DriveLetter`: drive has at least $($Global:Config.General.RequiredFreeSpaceGB) GB free" -Reason "Not enough free disk space"))
        }
    }
    catch {
        $null = $Results.Add((New-ValidationResult -Name "Disk Space" -Passed $false -Expected "Readable local drive information" -Reason $_.Exception.Message))
    }

    $Completed = Get-Date

    return Write-ValidationReport -Results $Results -Started $Started -Completed $Completed
}

# ============================================================
# Cleanup
# ============================================================

function Clear-StaleMount {
    $MountedImages = Get-WindowsImage -Mounted -ErrorAction SilentlyContinue
    $MatchedMounts = @()

    foreach ($Image in $MountedImages) {
        if ($Image.Path -like "$Global:MountFolder*") {
            $MatchedMounts += $Image
        }
    }

    if ($MatchedMounts.Count -eq 0) {
        return 0
    }

    foreach ($Mount in $MatchedMounts) {
        Dismount-WindowsImage -Path $Mount.Path -Discard -ErrorAction SilentlyContinue | Out-Null
    }

    return $MatchedMounts.Count
}

function Clear-FolderContents {
    param([string]$Path)

    if (Test-Path $Path) {
        Get-ChildItem -Path $Path -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-CleanupWorkspace {
    $Started = Get-Date

    Write-Header "Cleanup Workspace"
    Write-Host ""
    Write-Host "1. Standard Cleanup (recommended)" -ForegroundColor Green
    Write-Host "   Clears stale mounts, mount contents, and temporary build files."
    Write-Host "   Keeps logs and output WIMs."
    Write-Host ""
    Write-Host "2. Complete Cleanup" -ForegroundColor Yellow
    Write-Host "   Performs standard cleanup and also deletes logs and local output."
    Write-Host ""
    Write-Host "3. Cancel" -ForegroundColor Green
    Write-Host ""

    $CleanupSelection = (Read-Host "Select cleanup option [1-3]").Trim()

    if ($CleanupSelection -eq "3") {
        Write-Host "Cleanup cancelled." -ForegroundColor Yellow
        return
    }

    if ($CleanupSelection -notin @("1", "2")) {
        Write-Host "Invalid cleanup option." -ForegroundColor Red
        return
    }

    Write-Section "Cleanup Progress"

    $MountCount = Clear-StaleMount
    if ($MountCount -gt 0) {
        Write-CheckResult -Name "Dismount abandoned images" -Status "OK"
    }
    else {
        Write-CheckResult -Name "Check mounted WIMs" -Status "OK"
    }

    Clear-FolderContents -Path $Global:MountFolder
    Write-CheckResult -Name "Delete Mount contents" -Status "OK"

    Clear-FolderContents -Path $Global:BuildFolder
    Write-CheckResult -Name "Delete Build contents" -Status "OK"

    Get-ChildItem -Path $Global:WorkingRoot -Filter "*.tmp" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-CheckResult -Name "Remove scratch files" -Status "OK"

    if ($CleanupSelection -eq "2") {
        Clear-FolderContents -Path $Global:OutputFolder
        Write-CheckResult -Name "Delete Output contents" -Status "OK"

        Clear-FolderContents -Path $Global:LogFolder
        Write-CheckResult -Name "Delete Logs" -Status "OK"
    }
    else {
        Write-CheckResult -Name "Keep Output contents" -Status "OK"
        Write-CheckResult -Name "Keep Logs" -Status "OK"
    }

    Write-CheckResult -Name "Verify workspace" -Status "OK"

    $Completed = Get-Date
    $Elapsed = New-TimeSpan -Start $Started -End $Completed

    Write-Header "Cleanup Complete"
    Write-Host "Status          : SUCCESS" -ForegroundColor Green
    Write-Host ("Started         : {0}" -f $Started.ToString("MM/dd/yyyy hh:mm:ss tt"))
    Write-Host ("Completed       : {0}" -f $Completed.ToString("MM/dd/yyyy hh:mm:ss tt"))
    Write-Host ("Elapsed         : {0}" -f (Format-ElapsedTime -Elapsed $Elapsed))
    Write-Host ""
    Write-Host "Cleanup completed successfully." -ForegroundColor Green

    Write-Log "Cleanup completed successfully"
    Write-Footer -Result "Success"
}

# ============================================================
# Build actions
# ============================================================


function Get-SharePointAccessToken {
    <#
    Placeholder for Microsoft Graph authentication.

    When app registration approval is complete, this function should return
    a bearer token with read access to the configured SharePoint site/list.
    #>

    $ManifestConfig = $Global:Config.General.SharePointDriverManifest

    if ([string]::IsNullOrWhiteSpace($ManifestConfig.TenantId) -or
        [string]::IsNullOrWhiteSpace($ManifestConfig.ClientId)) {
        throw "SharePoint driver manifest is enabled, but TenantId or ClientId is not configured."
    }

    throw "SharePoint authentication is not implemented yet. Add Graph authentication here after Sites.Selected approval."
}

function Get-SharePointBootDriverManifest {
    <#
    Placeholder for SharePoint driver manifest reads.

    Expected output objects:
        DriverName
        DriverPath
        SiteCode
        Enabled

    Required SharePoint columns:
        SiteCode
        Driver Path
        Enabled

    The script filters by BootDriverProfile:
        PHO -> PHO
        PHQ -> PHO
        PHO -> PHO
    #>

    $ManifestConfig = $Global:Config.General.SharePointDriverManifest

    if (-not $ManifestConfig.Enabled) {
        return @()
    }

    $Token = Get-SharePointAccessToken

    # Future Graph call shape:
    # GET https://graph.microsoft.com/v1.0/sites/{SiteId}/lists/{ListId}/items?expand=fields
    #
    # Filter client-side:
    #   fields[$ColumnEnabled] = true
    #   fields[$ColumnSiteCode] = $Global:BootDriverProfile
    #
    # Return:
    # [pscustomobject]@{
    #   DriverName = $fields.Title
    #   DriverPath = $fields[$ColumnDriverPath]
    #   SiteCode = $fields[$ColumnSiteCode]
    #   Enabled = $fields[$ColumnEnabled]
    # }

    throw "SharePoint manifest read is not implemented yet. Graph query logic plugs in here."
}

function Get-OSDBootDriverSources {
    $ManifestConfig = $Global:Config.General.SharePointDriverManifest

    if ($ManifestConfig.Enabled) {
        Write-Log "Reading OSD boot driver paths from SharePoint manifest for profile $Global:BootDriverProfile"
        $Rows = @(Get-SharePointBootDriverManifest)

        $DriverSources = New-Object System.Collections.ArrayList
        foreach ($Row in $Rows) {
            if ($Row.Enabled -and $Row.SiteCode -eq $Global:BootDriverProfile -and -not [string]::IsNullOrWhiteSpace($Row.DriverPath)) {
                $Name = if ($Row.DriverName) { $Row.DriverName } else { Split-Path -Path $Row.DriverPath -Leaf }
                $null = $DriverSources.Add([pscustomobject]@{
                    DriverName = $Name
                    DriverPath = $Row.DriverPath
                    SiteCode    = $Row.SiteCode
                    Source      = "SharePoint"
                })
            }
        }

        return @($DriverSources)
    }

    # Local/source-share fallback until SharePoint access is approved.
    return @(
        [pscustomobject]@{
            DriverName = Split-Path -Path $Global:EnvConfig.BootDriverSource -Leaf
            DriverPath = $Global:EnvConfig.BootDriverSource
            SiteCode    = $Global:BootDriverProfile
            Source      = "FallbackConfig"
        }
    )
}

function Get-OSDBootDriverInventory {
    param([array]$DriverSources)

    $Inventory = New-Object System.Collections.ArrayList

    foreach ($Source in $DriverSources) {
        $Path = $Source.DriverPath
        if (-not (Test-Path $Path)) {
            continue
        }

        $Items = @(Get-DriverInventory -Path $Path)

        foreach ($Item in $Items) {
            $PackageName = $Item.PackageName
            if ($Source.Source -eq "SharePoint" -and $Source.DriverName -and $Items.Count -eq 1) {
                $PackageName = $Source.DriverName
            }

            $null = $Inventory.Add([pscustomobject]@{
                PackageName = $PackageName
                Group       = $Item.Group
                InfCount    = $Item.InfCount
                Providers   = $Item.Providers
                DriverTypes = $Item.DriverTypes
                InfFiles    = $Item.InfFiles
                Path        = $Item.Path
                SiteCode    = $Source.SiteCode
                Source      = $Source.Source
            })
        }
    }

    return @($Inventory | Sort-Object PackageName)
}

function Copy-WindowsSourceLocal {
    $SourceInstallWim = $Global:Config.General.WindowsInstallWim
    $Global:LocalWindowsSourceFolder = Join-Path $Global:BuildFolder "WindowsSource"
    $Global:LocalWindowsInstallWim = Join-Path $Global:LocalWindowsSourceFolder "install.wim"

    if (-not (Test-Path $SourceInstallWim)) {
        throw "Windows source install.wim was not found: $SourceInstallWim"
    }

    if (-not (Test-Path $Global:LocalWindowsSourceFolder)) {
        New-Item -Path $Global:LocalWindowsSourceFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    if (Test-Path $Global:LocalWindowsInstallWim) {
        Remove-Item $Global:LocalWindowsInstallWim -Force -ErrorAction Stop
    }

    Copy-Item -Path $SourceInstallWim -Destination $Global:LocalWindowsInstallWim -Force -ErrorAction Stop
}

function Invoke-BranchCacheInjection {
    if (-not $Global:EnvConfig.BranchCacheEnabled) {
        Write-Log "BranchCache Components skipped for $Global:Environment"
        return
    }

    $WinPEGenExe = $Global:Config.General.WinPEGenExe

    if (-not (Test-Path $WinPEGenExe)) {
        throw "WinPEGen.exe was not found: $WinPEGenExe"
    }

    if (-not (Test-Path $Global:LocalWindowsInstallWim)) {
        throw "Local Windows install.wim was not found: $Global:LocalWindowsInstallWim"
    }

    # OneVinn WinPEGen syntax:
    # WinPEGen.exe <install.wim> <install.wim index> <winpe.wim> <winpe.wim index>
    $Arguments = @(
        "`"$Global:LocalWindowsInstallWim`"",
        "1",
        "`"$Global:BuildWim`"",
        "1"
    )

    Write-Log ("Running WinPEGen.exe {0}" -f ($Arguments -join " "))

    $Process = Start-Process -FilePath $WinPEGenExe -ArgumentList $Arguments -Wait -PassThru -NoNewWindow -ErrorAction Stop

    if ($Process.ExitCode -ne 0) {
        throw "WinPEGen.exe failed with exit code $($Process.ExitCode)"
    }
}

function Copy-OSDBootExtraFiles {
    $Source = $Global:EnvConfig.BootExtraFilesSource

    if (-not (Test-Path $Source)) {
        throw "OSD Boot Extra Files source folder was not found: $Source"
    }

    # Copy root-level content to mounted WIM root.
    # Special handling: if a child folder named Windows exists, copy its contents into mounted WIM\Windows.
    Get-ChildItem -Path $Source -Force -ErrorAction Stop | Where-Object {
        $_.Name -ne "Windows"
    } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Global:MountFolder -Recurse -Force -ErrorAction Stop
    }

    $WindowsSource = Join-Path $Source "Windows"
    if (Test-Path $WindowsSource) {
        $WindowsTarget = Join-Path $Global:MountFolder "Windows"
        Copy-Item -Path "$WindowsSource\*" -Destination $WindowsTarget -Recurse -Force -ErrorAction Stop
        Write-Log "Copied Windows-specific OSD boot files into mounted WIM Windows folder: $WindowsSource"
    }

    Write-Log "Copied OSD Boot Extra Files from $Source to mounted WIM."
}

function Copy-OSDTSBackground {
    # Kept as a no-op compatibility wrapper.
    # TSBackground is included in BootExtraFilesSource and is copied by Copy-OSDBootExtraFiles.
    Write-Log "OSD TSBackground is included in OSD Boot Extra Files. Separate TSBackground copy skipped."
}

function Update-BITSACP {
    $Source = $Global:Config.General.BITSACPSource
    $Target = Join-Path (Join-Path $Global:MountFolder "Windows\System32") "BITSACP.exe"

    if (-not (Test-Path $Source)) {
        throw "BITSACP.exe source was not found: $Source"
    }

    Copy-Item -Path $Source -Destination $Target -Force -ErrorAction Stop
}

function Prepare-BuildWim {
    if (Test-Path $Global:BuildWim) {
        Remove-Item $Global:BuildWim -Force -ErrorAction Stop
    }

    Copy-Item -Path $Global:SourceBootWim -Destination $Global:BuildWim -Force -ErrorAction Stop
}

function Mount-BootImage {
    Mount-WindowsImage -ImagePath $Global:BuildWim -Index 1 -Path $Global:MountFolder -ErrorAction Stop | Out-Null
}

function Copy-WinPEGenFiles {
    $Target = Join-Path $Global:MountFolder "WinPEGen"
    if (Test-Path $Target) {
        Remove-Item $Target -Recurse -Force -ErrorAction Stop
    }

    Copy-Item -Path $Global:EnvConfig.WinPEGenSource -Destination $Target -Recurse -Force -ErrorAction Stop
}

function Copy-ExtraFiles {
    Copy-OSDBootExtraFiles
}

function Copy-Background {
    Copy-OSDTSBackground
}

function Add-BootDrivers {
    $DriverSources = @(Get-OSDBootDriverSources)

    if (-not $DriverSources -or $DriverSources.Count -eq 0) {
        throw "No OSD boot driver sources were returned for profile $Global:BootDriverProfile"
    }

    foreach ($Source in $DriverSources) {
        if (-not (Test-Path $Source.DriverPath)) {
            throw "OSD boot driver source was not found: $($Source.DriverPath)"
        }

        Write-Log ("Injecting OSD boot drivers from {0}" -f $Source.DriverPath)
        Add-WindowsDriver -Path $Global:MountFolder -Driver $Source.DriverPath -Recurse -ForceUnsigned -ErrorAction Stop | Out-Null
    }
}

function Commit-BootImage {
    Dismount-WindowsImage -Path $Global:MountFolder -Save -CheckIntegrity -ErrorAction Stop | Out-Null
}

function Validate-BootImageSize {
    $SizeKB = [math]::Round((Get-Item $Global:BuildWim).Length / 1KB)

    if ($SizeKB -gt $Global:Config.General.MaxBootImageSizeKB) {
        throw "Boot image too large. Size: $SizeKB KB. Limit: $($Global:Config.General.MaxBootImageSizeKB) KB"
    }

    return $SizeKB
}

function Export-LocalBootImage {
    if (Test-Path $Global:FinalWim) {
        Remove-Item $Global:FinalWim -Force -ErrorAction Stop
    }

    Copy-Item -Path $Global:BuildWim -Destination $Global:FinalWim -Force -ErrorAction Stop
    return $Global:FinalWim
}

function Invoke-Rollback {
    Write-Log "Rollback started" "Warning"

    try {
        Dismount-WindowsImage -Path $Global:MountFolder -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    catch {}

    if (Test-Path $Global:BuildWim) {
        Remove-Item $Global:BuildWim -Force -ErrorAction SilentlyContinue
    }

    Write-Log "Rollback completed" "Warning"
}


function Get-BuildHealth {
    param(
        [array]$Steps = @()
    )

    $Critical = @($Steps | Where-Object { $_.Severity -eq "Critical" })
    $Required = @($Steps | Where-Object { $_.Severity -eq "Required" })
    $Optional = @($Steps | Where-Object { $_.Severity -eq "Optional" })

    $CriticalFailed = @($Critical | Where-Object { $_.Status -eq "FAIL" }).Count
    $RequiredIssues = @($Required | Where-Object { $_.Status -in @("FAIL", "WARN") }).Count
    $OptionalIssues = @($Optional | Where-Object { $_.Status -in @("FAIL", "WARN") }).Count

    if ($CriticalFailed -gt 0) {
        $Score = 0
        $Health = "Failed"
        $ManualReview = "Required"
    }
    else {
        $Score = 100
        $Score -= ($RequiredIssues * 10)
        $Score -= ($OptionalIssues * 3)
        if ($Score -lt 0) { $Score = 0 }

        if ($RequiredIssues -gt 0 -or $OptionalIssues -gt 0) {
            $Health = "Completed with Warnings"
        }
        else {
            $Health = "Healthy"
        }

        $ManualReview = if ($Score -ge 90 -and $RequiredIssues -eq 0) { "Ready for review" } else { "Review Required" }
    }

    return [pscustomobject]@{
        Score          = [int]$Score
        Health         = $Health
        ManualReview   = $ManualReview
        CriticalTotal  = $Critical.Count
        CriticalPassed = @($Critical | Where-Object { $_.Status -eq "OK" }).Count
        CriticalFailed = $CriticalFailed
        RequiredTotal  = $Required.Count
        RequiredPassed = @($Required | Where-Object { $_.Status -eq "OK" }).Count
        RequiredIssues = $RequiredIssues
        OptionalTotal  = $Optional.Count
        OptionalPassed = @($Optional | Where-Object { $_.Status -eq "OK" }).Count
        OptionalIssues = $OptionalIssues
    }
}

function Invoke-BuildStep {
    param(
        [int]$Step,
        [int]$Total,
        [string]$Name,
        [ValidateSet("Critical", "Required", "Optional")]
        [string]$Severity = "Required",
        [scriptblock]$Action
    )

    try {
        & $Action
        Write-StepResult -Step $Step -Total $Total -Name $Name -Severity $Severity -Status "OK" -Detail "Completed"
        Write-AuditLine ("BUILD PASS  {0} | Severity={1}" -f $Name, $Severity)
        return $true
    }
    catch {
        $Message = $_.Exception.Message

        if ($Severity -eq "Critical") {
            Write-StepResult -Step $Step -Total $Total -Name $Name -Severity $Severity -Status "FAIL" -Detail $Message
            Write-AuditLine ("BUILD FAIL  {0} | Severity=Critical | {1}" -f $Name, $Message) "Error"
            throw $_
        }

        Write-StepResult -Step $Step -Total $Total -Name $Name -Severity $Severity -Status "WARN" -Detail $Message
        Write-AuditLine ("BUILD WARN  {0} | Severity={1} | {2}" -f $Name, $Severity, $Message) "Warning"
        return $false
    }
}


function Clear-TemporaryBuildArtifacts {
    if (Test-Path $Global:MountFolder) {
        Clear-FolderContents -Path $Global:MountFolder
    }

    if (Test-Path $Global:BuildWim) {
        Remove-Item $Global:BuildWim -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BuildBootImage {
    $Started = Get-Date
    $Global:BuildSteps = New-Object System.Collections.ArrayList
    $FinalPath = $null
    $BootImageSizeKB = 0
    $DriverSources = @(Get-OSDBootDriverSources)
    $DriverInventory = Get-OSDBootDriverInventory -DriverSources $DriverSources
    $DriverInfCount = 0
    foreach ($Item in $DriverInventory) { $DriverInfCount += [int]$Item.InfCount }
    $ExtraFileCount = Get-FileCountSafe -Path $Global:EnvConfig.BootExtraFilesSource

    Write-DriverInjectionSummary -Inventory $DriverInventory

    Write-Section "Build Progress"
    Write-Log "Build started for $Global:Environment"
    Write-AuditLine "Build"
    Write-AuditLine ("Driver Profile....... {0}" -f $Global:BootDriverProfile)
    foreach ($Source in $DriverSources) {
        Write-AuditLine ("Driver Source........ {0}" -f $Source.DriverPath)
    }
    Write-AuditLine ("Driver INF Count..... {0}" -f $DriverInfCount)
    Write-AuditLine ("OSD Boot Extra Files. {0}" -f $ExtraFileCount)

    try {
        $StepNumber = 1
        $TotalSteps = if ($Global:EnvConfig.BranchCacheEnabled) { 10 } else { 7 }

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Preparing workspace" -Severity "Critical" -Action { $null = Clear-StaleMount }
        $StepNumber++

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Copying WinPE" -Severity "Critical" -Action { Prepare-BuildWim }
        $StepNumber++

        if ($Global:EnvConfig.BranchCacheEnabled) {
            Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Copying Windows Source" -Severity "Critical" -Action { Copy-WindowsSourceLocal }
            $StepNumber++
        }
        else {
            Write-Log "Copying Windows Source skipped for $Global:Environment because BranchCacheEnabled is false."
        }

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Mounting WIM" -Severity "Critical" -Action { Mount-BootImage }
        $StepNumber++

        if ($Global:EnvConfig.BranchCacheEnabled) {
            Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Running BranchCache Components" -Severity "Critical" -Action { Invoke-BranchCacheInjection }
            $StepNumber++
        }
        else {
            Write-Log "BranchCache Components skipped for $Global:Environment because BranchCacheEnabled is false."
        }

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Copying OSD Boot Extra Files" -Severity "Required" -Action { Copy-OSDBootExtraFiles }
        $StepNumber++

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Injecting OSD Boot Drivers" -Severity "Required" -Action { Add-BootDrivers }
        $StepNumber++

        if ($Global:EnvConfig.BranchCacheEnabled) {
            Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Updating BITSACP.exe" -Severity "Critical" -Action { Update-BITSACP }
            $StepNumber++
        }
        else {
            Write-Log "BITSACP.exe update skipped for $Global:Environment because BranchCacheEnabled is false."
        }

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Committing Image" -Severity "Critical" -Action { Commit-BootImage }
        $StepNumber++

        Invoke-BuildStep -Step $StepNumber -Total $TotalSteps -Name "Exporting Local WIM" -Severity "Critical" -Action {
            $script:StepImageSizeKB = Validate-BootImageSize
            $script:StepFinalPath = Export-LocalBootImage
        }
        $BootImageSizeKB = $script:StepImageSizeKB
        $FinalPath = $script:StepFinalPath
        Clear-TemporaryBuildArtifacts

        $Completed = Get-Date
        $Elapsed = New-TimeSpan -Start $Started -End $Completed
        $BuildHealth = Get-BuildHealth -Steps $Global:BuildSteps
        $BuildReportStatus = if ($BuildHealth.Health -eq "Healthy") { "Success" } else { "Warning" }

        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Header "Build Complete"

        Write-Host "Status          : " -NoNewline
        if ($BuildHealth.Health -eq "Healthy") {
            Write-Host "SUCCESS" -ForegroundColor Green
        }
        else {
            Write-Host "COMPLETED WITH WARNINGS" -ForegroundColor Yellow
        }
        Write-Host ("Build Score     : {0}%" -f $BuildHealth.Score)
        Write-Host ("Manual Review   : {0}" -f $BuildHealth.ManualReview)
        Write-Host ""
        Write-Host ("Environment     : {0}" -f $Global:Environment)
        Write-Host ("Boot Image      : {0}" -f $Global:EnvConfig.BootImageName)
        Write-Host ""
        Write-Host ("Started         : {0}" -f $Started.ToString("MM/dd/yyyy hh:mm:ss tt"))
        Write-Host ("Completed       : {0}" -f $Completed.ToString("MM/dd/yyyy hh:mm:ss tt"))
        Write-Host ("Elapsed         : {0}" -f (Format-ElapsedTime -Elapsed $Elapsed))
        Write-Host ""
        Write-Host "Local Output" -ForegroundColor Cyan
        Write-Host $Global:OutputFolder
        Write-Host ""
        Write-Host (Split-Path $Global:FinalWim -Leaf)
        Write-Host ""
        Write-Host "Log" -ForegroundColor Cyan
        Write-Host $Global:LogFile
        Write-Host ""
        Write-Host ("OSD Boot Drivers : {0}" -f $DriverInfCount)
        Write-Host ("OSD Boot Extra   : {0}" -f $ExtraFileCount)
        Write-Host "OSD TSBackground : Applied"
        Write-Host ("BranchCache     : {0}" -f $(if ($Global:EnvConfig.BranchCacheEnabled) { "Applied" } else { "Skipped" }))
        Write-Host ("SizeKB          : {0}" -f $BootImageSizeKB)

        $FinalItem = Get-Item -Path $FinalPath -ErrorAction SilentlyContinue
        $SizeMB = ""
        $Created = ""
        $Hash = ""
        if ($FinalItem) {
            $SizeMB = ("{0:N2} MB" -f ($FinalItem.Length / 1MB))
            $Created = $FinalItem.CreationTime.ToString("MM/dd/yyyy hh:mm:ss tt")
            try {
                $Hash = (Get-FileHash -Path $FinalPath -Algorithm SHA256 -ErrorAction Stop).Hash
            }
            catch {
                $Hash = "Unable to calculate SHA256"
            }
        }

        $BuildInfo = @{
            Status       = $BuildHealth.Health
            BuildScore   = ("{0}%" -f $BuildHealth.Score)
            ManualReview = $BuildHealth.ManualReview
            CriticalSteps = ("{0}/{1} passed" -f $BuildHealth.CriticalPassed, $BuildHealth.CriticalTotal)
            RequiredIssues = $BuildHealth.RequiredIssues
            OptionalIssues = $BuildHealth.OptionalIssues
            Environment  = $Global:Environment
            BootImage    = $Global:EnvConfig.BootImageName
            LocalImage   = $FinalPath
            SizeKB       = $BootImageSizeKB
            SizeMB       = $SizeMB
            OSDBootDrivers = $DriverInfCount
            OSDBootExtraFiles = $ExtraFileCount
            OSDTSBackground = "Applied"
            BranchCache  = $(if ($Global:EnvConfig.BranchCacheEnabled) { "Applied" } else { "Skipped" })
            OutputFolder = $Global:OutputFolder
            OutputFile   = (Split-Path $Global:FinalWim -Leaf)
            OutputPath   = $FinalPath
            SHA256       = $Hash
            Created      = $Created
        }

        Write-Log "Summary | Status=$($BuildHealth.Health) | BuildScore=$($BuildHealth.Score) | Environment=$Global:Environment | BootImage=$($Global:EnvConfig.BootImageName) | LocalImage=$FinalPath | SizeKB=$BootImageSizeKB | OSDBootDrivers=$DriverInfCount | OSDBootExtraFiles=$ExtraFileCount"
        Write-AuditLine ("Result.............. {0}" -f $BuildHealth.Health)
        Write-AuditLine ("Output.............. {0}" -f $FinalPath)
        Write-AuditLine ("SizeKB.............. {0}" -f $BootImageSizeKB)
        $ReportPath = Write-HtmlReport -ReportType "Build" -Status $BuildReportStatus -Started $Started -Completed $Completed -BuildInfo $BuildInfo -DriverInventory $DriverInventory
        if ($ReportPath) {
            Write-Host "Report" -ForegroundColor Cyan
            Write-Host $ReportPath
            Write-Host ""
        }
        Write-Footer -Result "Success"
    }
    catch {
        Write-Log $_.Exception.Message "Error"
        Invoke-Rollback

        $Completed = Get-Date
        $Elapsed = New-TimeSpan -Start $Started -End $Completed
        $BuildHealth = Get-BuildHealth -Steps $Global:BuildSteps

        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
        Write-Header "Build Complete"

        Write-Host "Status          : " -NoNewline
        Write-Host "FAILED" -ForegroundColor Red
        Write-Host ""
        Write-Host ("Environment     : {0}" -f $Global:Environment)
        Write-Host ("Boot Image      : {0}" -f $Global:EnvConfig.BootImageName)
        Write-Host ""
        Write-Host ("Started         : {0}" -f $Started.ToString("MM/dd/yyyy hh:mm:ss tt"))
        Write-Host ("Completed       : {0}" -f $Completed.ToString("MM/dd/yyyy hh:mm:ss tt"))
        Write-Host ("Elapsed         : {0}" -f (Format-ElapsedTime -Elapsed $Elapsed))
        Write-Host ""
        Write-Host "Build failed. Review the messages above and the CMTrace log." -ForegroundColor Red
        Write-Host $Global:LogFile

        $BuildInfo = @{
            Status      = "Failed"
            BuildScore  = ("{0}%" -f $BuildHealth.Score)
            CriticalSteps = ("{0}/{1} passed" -f $BuildHealth.CriticalPassed, $BuildHealth.CriticalTotal)
            RequiredIssues = $BuildHealth.RequiredIssues
            OptionalIssues = $BuildHealth.OptionalIssues
            Environment = $Global:Environment
            BootImage   = $Global:EnvConfig.BootImageName
            Error       = $_.Exception.Message
            OSDBootDrivers = $DriverInfCount
            OSDBootExtraFiles = $ExtraFileCount
        }

        Write-Log "Summary | Status=Failed | Environment=$Global:Environment | BootImage=$($Global:EnvConfig.BootImageName)" "Error"
        Write-AuditLine ("Result.............. FAILED") "Error"
        Write-AuditLine ("Error............... {0}" -f $_.Exception.Message) "Error"
        $ReportPath = Write-HtmlReport -ReportType "Build" -Status "Failed" -Started $Started -Completed $Completed -BuildInfo $BuildInfo -DriverInventory $DriverInventory
        if ($ReportPath) {
            Write-Host ""
            Write-Host "Report" -ForegroundColor Cyan
            Write-Host $ReportPath
        }
        Write-Footer -Result "Error"
    }
}

# ============================================================
# Main
# ============================================================

Select-WinPESource
Show-StartupBanner
Select-Environment
Initialize-Workspace
Show-CurrentConfiguration
Select-Action

try {
    Write-Log "Starting $Global:ToolName"
    Write-Log "Version: $Global:ToolVersion"
    Write-Log "Company: $Global:CompanyName"
    Write-Log "Selected Environment: $Global:Environment - $($Global:EnvConfig.Name)"
    Write-Log "Boot Image Name: $($Global:EnvConfig.BootImageName)"
    Write-Log "WinPE Source Mode: $Global:WinPESourceMode"
    Write-Log "Selected ADK Root: $Global:SelectedADKRoot"
    Write-Log "Source ADK WIM: $Global:SourceBootWim"
    Write-Log "Local Output: $Global:OutputFolder"
    Write-Log "Boot Driver Profile: $Global:BootDriverProfile"
    Write-Log "Action: $Global:Action"
    Write-AuditExecutionStart

    if ($Global:Action -eq "CLEANUP") {
        Invoke-CleanupWorkspace
        return
    }

    $ValidationPassed = Test-EnterprisePrerequisites

    if (-not $ValidationPassed) {
        return
    }

    if ($Global:Action -eq "VALIDATE") {
        return
    }

    Invoke-BuildBootImage
}
catch {
    Write-Log $_.Exception.Message "Error"
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Footer -Result "Error"
}
finally {
    Write-Log "Script completed"
}

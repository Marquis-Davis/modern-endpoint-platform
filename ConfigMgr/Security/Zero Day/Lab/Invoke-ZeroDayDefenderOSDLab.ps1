[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'Output'),
    [string]$AppliedCVEs = 'CVE-2026-XXXX_CVE-2026-YYYY',
    [string]$EmergencyMsu = 'windows11.0-kbXXXXXXX-x64.msu',
    [ValidateRange(0,5000)]
    [int]$DelayMs = 700
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$VersionScript = Join-Path $PSScriptRoot 'Get-LatestMicrosoftDefenderVersion.ps1'
if (-not (Test-Path $VersionScript)) {
    throw "Missing Defender version discovery script: $VersionScript"
}

if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$LogPath   = Join-Path $OutputRoot 'ZeroDayDefenderOSD.log'
$StatePath = Join-Path $OutputRoot 'status.json'
$EventPath = Join-Path $OutputRoot 'events.ndjson'

Remove-Item $LogPath,$StatePath,$EventPath -Force -ErrorAction SilentlyContinue

function Write-LabEvent {
    param(
        [Parameter(Mandatory)] [string]$Stage,
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO','SUCCESS','WARN','ERROR')] [string]$Level = 'INFO'
    )

    $now = Get-Date
    $script:State.Stage = $Stage
    $script:State.Updated = $now.ToString('o')
    $script:State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8

    $event = [ordered]@{
        timestamp = $now.ToString('o')
        level     = $Level
        stage     = $Stage
        message   = $Message
    }

    $line = '[{0}] [{1}] [{2}] {3}' -f $now.ToString('HH:mm:ss'),$Level,$Stage,$Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Add-Content -Path $EventPath -Value ($event | ConvertTo-Json -Compress) -Encoding UTF8
    Write-Host $line

    if ($DelayMs -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

# Pull the current Microsoft values at the beginning of EVERY run.
# If this fails, the simulation stops rather than displaying stale data.
try {
    $CurrentMicrosoft = & $VersionScript
}
catch {
    throw "Unable to retrieve current Microsoft Defender versions. Simulation stopped. $($_.Exception.Message)"
}

# Simulate an OSD image that is behind Microsoft's current release.
# These values are intentionally derived from the current values instead of
# hardcoding a fake 'latest' value.
function Get-PreviousVersion {
    param([Parameter(Mandatory)][string]$Version)

    $parts = $Version -split '\.'
    if ($parts.Count -lt 2) {
        return $Version
    }

    $last = [int]$parts[-1]
    $parts[-1] = [string][math]::Max(0,$last - 1)
    return ($parts -join '.')
}

$ImageState = [ordered]@{
    PlatformVersion             = Get-PreviousVersion $CurrentMicrosoft.PlatformVersion
    EngineVersion               = Get-PreviousVersion $CurrentMicrosoft.EngineVersion
    SecurityIntelligenceVersion = Get-PreviousVersion $CurrentMicrosoft.SecurityIntelligenceVersion
}

$script:State = [ordered]@{
    RunId          = [guid]::NewGuid().Guid
    Started        = (Get-Date).ToString('o')
    Updated        = (Get-Date).ToString('o')
    Status         = 'Running'
    Stage          = 'Initialize'
    MicrosoftSource = $CurrentMicrosoft.Source
    RetrievedAtUtc = $CurrentMicrosoft.RetrievedAtUtc
    CurrentMicrosoft = [ordered]@{
        PlatformVersion             = $CurrentMicrosoft.PlatformVersion
        EngineVersion               = $CurrentMicrosoft.EngineVersion
        SecurityIntelligenceVersion = $CurrentMicrosoft.SecurityIntelligenceVersion
        Released                    = $CurrentMicrosoft.Released
    }
    ImageBefore = [ordered]@{
        PlatformVersion             = $ImageState.PlatformVersion
        EngineVersion               = $ImageState.EngineVersion
        SecurityIntelligenceVersion = $ImageState.SecurityIntelligenceVersion
    }
    ImageAfter     = [ordered]@{}
    AppliedCVEs    = $AppliedCVEs
    EmergencyMsu   = $EmergencyMsu
    RebootRequired = $false
}

$script:State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8

Write-LabEvent -Stage 'Microsoft' -Message 'Querying Microsoft Security Intelligence for current Defender versions.'
Write-LabEvent -Stage 'Microsoft' -Level SUCCESS -Message ("Current Microsoft Defender: Platform {0} | Engine {1} | Intelligence {2}" -f $CurrentMicrosoft.PlatformVersion,$CurrentMicrosoft.EngineVersion,$CurrentMicrosoft.SecurityIntelligenceVersion)
Write-LabEvent -Stage 'Microsoft' -Message ("Microsoft release: {0}" -f $CurrentMicrosoft.Released)

Write-LabEvent -Stage 'Detect' -Message 'Reading Defender state from the simulated Windows 11 OSD image.'
Write-LabEvent -Stage 'Detect' -Message ("Image state: Platform {0} | Engine {1} | Intelligence {2}" -f $ImageState.PlatformVersion,$ImageState.EngineVersion,$ImageState.SecurityIntelligenceVersion)

if ($ImageState.PlatformVersion -ne $CurrentMicrosoft.PlatformVersion) {
    Write-LabEvent -Stage 'Platform' -Message 'Defender platform is behind Microsoft current. Staging the local platform update package.'
    Write-LabEvent -Stage 'Platform' -Message ("Applying platform {0}" -f $CurrentMicrosoft.PlatformVersion)
    $ImageState.PlatformVersion = $CurrentMicrosoft.PlatformVersion
    $ImageState.EngineVersion = $CurrentMicrosoft.EngineVersion
    Write-LabEvent -Stage 'Platform' -Level SUCCESS -Message 'Defender platform and engine updated successfully.'
}
else {
    Write-LabEvent -Stage 'Platform' -Level SUCCESS -Message 'Defender platform is already current.'
}

if ($ImageState.SecurityIntelligenceVersion -ne $CurrentMicrosoft.SecurityIntelligenceVersion) {
    Write-LabEvent -Stage 'Intelligence' -Message 'Security intelligence is behind Microsoft current. Copying locally staged definition content.'
    Write-LabEvent -Stage 'Intelligence' -Message 'Running the local Update-MpSignature stage used during OSD.'
    $ImageState.SecurityIntelligenceVersion = $CurrentMicrosoft.SecurityIntelligenceVersion
    Write-LabEvent -Stage 'Intelligence' -Level SUCCESS -Message ("Security intelligence updated to {0}" -f $ImageState.SecurityIntelligenceVersion)
}
else {
    Write-LabEvent -Stage 'Intelligence' -Level SUCCESS -Message 'Security intelligence is already current.'
}

Write-LabEvent -Stage 'ZeroDay' -Message ("Reading ConfigMgr TS variable APPLIED_CVEs = {0}" -f $AppliedCVEs)

if ([string]::IsNullOrWhiteSpace($AppliedCVEs)) {
    Write-LabEvent -Stage 'ZeroDay' -Level SUCCESS -Message 'APPLIED_CVEs is empty. Emergency patch step is skipped.'
}
else {
    $cves = $AppliedCVEs -split '_' | Where-Object { $_ }
    Write-LabEvent -Stage 'ZeroDay' -Message ("Emergency patch step enabled for {0} CVE value(s)." -f $cves.Count)
    Write-LabEvent -Stage 'ZeroDay' -Message ("Staging MSU: {0}" -f $EmergencyMsu)
    Write-LabEvent -Stage 'CBS' -Message 'Installing MSU and monitoring C:\Windows\Logs\CBS\CBS.log.'
    Write-LabEvent -Stage 'CBS' -Level SUCCESS -Message 'CBS servicing completed successfully in the simulation.'
    $script:State.RebootRequired = $true
}

Write-LabEvent -Stage 'Validate' -Message 'Validating Defender and emergency patch state.'

$script:State.ImageAfter = [ordered]@{
    PlatformVersion             = $ImageState.PlatformVersion
    EngineVersion               = $ImageState.EngineVersion
    SecurityIntelligenceVersion = $ImageState.SecurityIntelligenceVersion
}

$script:State.Status = 'Complete'
$script:State.Stage = 'Complete'
$script:State.Updated = (Get-Date).ToString('o')
$script:State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8

Write-LabEvent -Stage 'Complete' -Level SUCCESS -Message ("Final Defender state: Platform {0} | Engine {1} | Intelligence {2}" -f $ImageState.PlatformVersion,$ImageState.EngineVersion,$ImageState.SecurityIntelligenceVersion)
Write-LabEvent -Stage 'Complete' -Level SUCCESS -Message ("Simulation complete. Reboot required: {0}" -f $script:State.RebootRequired)

Write-Host ''
Write-Host "Log:    $LogPath"
Write-Host "Events: $EventPath"
Write-Host "State:  $StatePath"

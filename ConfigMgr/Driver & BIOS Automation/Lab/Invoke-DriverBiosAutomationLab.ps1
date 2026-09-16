[CmdletBinding()]
param(
    [ValidateSet('Simulation', 'Live')]
    [string]$Mode = 'Simulation',

    [string]$OutputRoot = (Join-Path $PSScriptRoot 'Output'),

    [ValidateRange(0, 5000)]
    [int]$DelayMs = 650
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$LogPath = Join-Path $OutputRoot 'DriverBiosAutomation.log'
$EventPath = Join-Path $OutputRoot 'events.ndjson'
$StatePath = Join-Path $OutputRoot 'status.json'

if (-not (Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

Remove-Item $LogPath, $EventPath, $StatePath -Force -ErrorAction SilentlyContinue

$script:State = [ordered]@{
    RunId       = [guid]::NewGuid().Guid
    Mode        = $Mode
    Started     = (Get-Date).ToString('o')
    Updated     = (Get-Date).ToString('o')
    Status      = 'Starting'
    Total       = 0
    Completed   = 0
    Failed      = 0
    Current     = $null
    Items       = @()
}

function Save-State {
    $script:State.Updated = (Get-Date).ToString('o')
    $script:State | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8
}

function Write-AutomationEvent {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR')] [string]$Level = 'INFO',
        [string]$Vendor = '',
        [string]$Workload = '',
        [string]$Model = '',
        [string]$Stage = ''
    )

    $now = Get-Date
    $event = [ordered]@{
        timestamp = $now.ToString('o')
        level     = $Level
        vendor    = $Vendor
        workload  = $Workload
        model     = $Model
        stage     = $Stage
        message   = $Message
    }

    $line = '[{0}] [{1}] {2}' -f $now.ToString('HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
    Add-Content -Path $EventPath -Value ($event | ConvertTo-Json -Compress) -Encoding UTF8
    Write-Host $line
}

function Set-CurrentItem {
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter(Mandatory)] [string]$Stage,
        [Parameter(Mandatory)] [string]$Status
    )

    $script:State.Current = [ordered]@{
        Vendor   = $Item.Vendor
        Workload = $Item.Workload
        Model    = $Item.Model
        Stage    = $Stage
        Status   = $Status
    }

    $existing = $script:State.Items | Where-Object {
        $_.Vendor -eq $Item.Vendor -and $_.Workload -eq $Item.Workload -and $_.Model -eq $Item.Model
    } | Select-Object -First 1

    if ($existing) {
        $existing.Stage = $Stage
        $existing.Status = $Status
    }

    Save-State
}

function Invoke-DemoStage {
    param(
        [Parameter(Mandatory)] [hashtable]$Item,
        [Parameter(Mandatory)] [string]$Stage,
        [Parameter(Mandatory)] [string]$Message,
        [int]$SleepMs = $DelayMs
    )

    Set-CurrentItem -Item $Item -Stage $Stage -Status 'Running'
    Write-AutomationEvent -Vendor $Item.Vendor -Workload $Item.Workload -Model $Item.Model -Stage $Stage -Message $Message

    if ($SleepMs -gt 0) {
        Start-Sleep -Milliseconds $SleepMs
    }
}

function Invoke-SimulatedPackageBuild {
    param(
        [Parameter(Mandatory)] [hashtable]$Item
    )

    $packageName = '{0} - {1} - {2} - {3}' -f $Item.Vendor, $Item.Model, $Item.Workload, $Item.CatalogVersion
    $packageFormat = if ($Item.Workload -eq 'Drivers') { 'WIM' } else { 'EXE' }

    Invoke-DemoStage -Item $Item -Stage 'Catalog' -Message ("Reading {0} catalog metadata for {1}" -f $Item.Vendor, $Item.Model)
    Invoke-DemoStage -Item $Item -Stage 'Compare' -Message ("Installed {0}: {1} | Catalog: {2}" -f $Item.Workload, $Item.InstalledVersion, $Item.CatalogVersion)

    if ($Item.InstalledVersion -eq $Item.CatalogVersion) {
        Set-CurrentItem -Item $Item -Stage 'Compare' -Status 'Current'
        Write-AutomationEvent -Level SUCCESS -Vendor $Item.Vendor -Workload $Item.Workload -Model $Item.Model -Stage 'Compare' -Message ("{0} is already current. No package required." -f $Item.Model)
        return
    }

    Invoke-DemoStage -Item $Item -Stage 'Download' -Message ("Downloading {0} payload with curl.exe" -f $Item.Workload)
    Invoke-DemoStage -Item $Item -Stage 'Verify' -Message 'Validating download, version metadata, and expected vendor package identity'
    Invoke-DemoStage -Item $Item -Stage 'Extract' -Message ("Extracting vendor content for {0}" -f $Item.Model)
    Invoke-DemoStage -Item $Item -Stage 'Package' -Message ("Building {0} package: {1}" -f $packageFormat, $packageName)
    Invoke-DemoStage -Item $Item -Stage 'ConfigMgr' -Message ("Creating/updating ConfigMgr package object for {0}" -f $packageName)
    Invoke-DemoStage -Item $Item -Stage 'Distribution' -Message 'Distributing content to configured distribution points'
    Invoke-DemoStage -Item $Item -Stage 'Validation' -Message 'Validating package source, content version, and distribution state'

    Set-CurrentItem -Item $Item -Stage 'Complete' -Status 'Complete'
    Write-AutomationEvent -Level SUCCESS -Vendor $Item.Vendor -Workload $Item.Workload -Model $Item.Model -Stage 'Complete' -Message ("Completed {0} automation for {1}" -f $Item.Workload, $Item.Model)
}

if ($Mode -eq 'Live') {
    throw @'
Live mode is intentionally blocked in the public lab build.

The production adapter needs environment-specific values before it can create or distribute ConfigMgr content:
- Site code and provider
- Content source paths
- Distribution point groups
- Package folder structure
- Service account / Hybrid Worker context

Run with -Mode Simulation to exercise the complete workflow safely.
'@
}

$targets = @(
    @{
        Vendor = 'HP'; Workload = 'Drivers'; Model = 'EliteBook 840 G10'
        InstalledVersion = '1.12'; CatalogVersion = '1.15'
    },
    @{
        Vendor = 'HP'; Workload = 'BIOS'; Model = 'EliteBook 840 G10'
        InstalledVersion = '01.04.03'; CatalogVersion = '01.07.00'
    },
    @{
        Vendor = 'HP'; Workload = 'Drivers'; Model = 'ProBook 440 G10'
        InstalledVersion = '1.20'; CatalogVersion = '1.20'
    },
    @{
        Vendor = 'Dell'; Workload = 'Drivers'; Model = 'Latitude 7450'
        InstalledVersion = 'A03'; CatalogVersion = 'A05'
    },
    @{
        Vendor = 'Dell'; Workload = 'BIOS'; Model = 'Latitude 7450'
        InstalledVersion = '1.8.1'; CatalogVersion = '1.11.0'
    },
    @{
        Vendor = 'Dell'; Workload = 'BIOS'; Model = 'Precision 5680'
        InstalledVersion = '1.16.0'; CatalogVersion = '1.16.0'
    }
)

$script:State.Total = $targets.Count
$script:State.Items = @($targets | ForEach-Object {
    [ordered]@{
        Vendor         = $_.Vendor
        Workload       = $_.Workload
        Model          = $_.Model
        Installed      = $_.InstalledVersion
        Catalog        = $_.CatalogVersion
        Stage          = 'Queued'
        Status         = 'Queued'
    }
})
$script:State.Status = 'Running'
Save-State

Write-AutomationEvent -Message ("Automation run {0} started in Simulation mode" -f $script:State.RunId)
Write-AutomationEvent -Message 'Refreshing HP and Dell driver/BIOS catalog state'
Start-Sleep -Milliseconds $DelayMs
Write-AutomationEvent -Level SUCCESS -Message ("Catalog discovery complete. {0} work items queued." -f $targets.Count)

foreach ($target in $targets) {
    try {
        Invoke-SimulatedPackageBuild -Item $target
        $script:State.Completed++
    }
    catch {
        $script:State.Failed++
        Set-CurrentItem -Item $target -Stage 'Failed' -Status 'Failed'
        Write-AutomationEvent -Level ERROR -Vendor $target.Vendor -Workload $target.Workload -Model $target.Model -Stage 'Failed' -Message $_.Exception.Message
    }
    finally {
        Save-State
    }
}

$script:State.Status = if ($script:State.Failed -gt 0) { 'CompletedWithErrors' } else { 'Complete' }
$script:State.Current = $null
Save-State

Write-AutomationEvent -Level SUCCESS -Message ("Run complete. Completed: {0} | Failed: {1}" -f $script:State.Completed, $script:State.Failed)
Write-Host ''
Write-Host "Log:    $LogPath"
Write-Host "Events: $EventPath"
Write-Host "State:  $StatePath"

<#
.SYNOPSIS
    Lightweight ConfigMgr OSD monitor with Azure Log Analytics telemetry.

.DESCRIPTION
    - Creates one OSDBuildId per Task Sequence run.
    - Uses the ConfigMgr Task Sequence variable as the authority during the TS.
    - Persists the same BuildId to C:\ProgramData\OSDMonitor after Apply OS.
    - Copies itself to ProgramData in Full OS.
    - Creates a temporary startup scheduled task for reboot recovery.
    - Removes the scheduled task when the TS reaches a terminal state.
    - Copies the final local log to C:\Windows\CCM\Logs when available.

.NOTES
    Expected Task Sequence variables:
      OSD_LogAnalytics_WorkspaceId
      OSD_LogAnalytics_SharedKey

    Optional Task Sequence variables:
      OSDMonitor_Mode          Normal | Diagnostics | Silent | Disabled
      OSDMonitorState          Success | Failure
      TSstartTime
      OSDComputerName
      ErrorStepName
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

#region Constants
$script:Component     = "OSDMonitor"
$script:TaskName      = "OSDMonitor-Resume"
$script:TargetRoot    = "C:\ProgramData\OSDMonitor"
$script:TargetExe     = Join-Path $script:TargetRoot "OSDMonitor.exe"
$script:BuildIdFile   = Join-Path $script:TargetRoot "BuildId.txt"
$script:SilentMode    = $false
$script:DisableAzure  = $false
#endregion

#region Task Sequence detection
$script:TsEnv = $null
$script:InTS  = $false
$script:IsResume = $args -contains "/resume"

# A startup scheduled task can fire before the ConfigMgr TS COM object is ready.
# In resume mode, wait up to 10 minutes instead of exiting immediately.
$attempts = if ($script:IsResume) { 60 } else { 1 }

for ($attempt = 1; $attempt -le $attempts; $attempt++) {
    try {
        $script:TsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
        $script:InTS  = $true
        break
    }
    catch {
        $script:InTS = $false

        if ($attempt -lt $attempts) {
            Start-Sleep -Seconds 10
        }
    }
}
#endregion

#region Phase detection
if (-not $script:InTS) {
    $script:Phase = "OutsideTS"
}
elseif ($script:TsEnv.Value("_SMSTSInWinPE") -eq "true") {
    $script:Phase = "WinPE"
}
else {
    $script:Phase = "FullOS"
}
#endregion

#region Logging initialization
if ($script:Phase -eq "WinPE") {
    $script:LogRoot = "X:\OSDMonitor"
}
else {
    $script:LogRoot = $script:TargetRoot
}

New-Item -ItemType Directory -Path $script:LogRoot -Force | Out-Null
$script:LogFile = Join-Path $script:LogRoot "OSDMonitor.log"
#endregion

function Write-OSDLog {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR")]
        [string]$Level = "INFO",

        [string]$Component = "OSDMonitor"
    )

    try {
        $timestamp = Get-Date -Format "MM-dd-yyyy HH:mm:ss.fff"
        $computer = if ($script:InTS) {
            try { $script:TsEnv.Value("OSDComputerName") } catch { $env:COMPUTERNAME }
        }
        else {
            $env:COMPUTERNAME
        }

        if ([string]::IsNullOrWhiteSpace($computer)) {
            $computer = $env:COMPUTERNAME
        }

        "$timestamp | $Level | $Component | $Message | Host=$computer" |
            Out-File -FilePath $script:LogFile -Append -Encoding utf8
    }
    catch {
        # Logging must never stop the Task Sequence.
    }
}

function Get-TSValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not $script:InTS -or $null -eq $script:TsEnv) {
        return $null
    }

    try {
        return $script:TsEnv.Value($Name)
    }
    catch {
        return $null
    }
}

function Set-TSValue {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Value
    )

    if (-not $script:InTS -or $null -eq $script:TsEnv) {
        return
    }

    try {
        $script:TsEnv.Value($Name) = $Value
    }
    catch {
        Write-OSDLog -Level WARN -Message "Unable to set TS variable [$Name]: $($_.Exception.Message)"
    }
}

function Initialize-BuildId {
    <#
        Authority order:
          1. Existing TS variable OSDBuildId
          2. Existing Full OS BuildId.txt
          3. Generate once and write back to TS variable

        In Full OS, the selected BuildId is always persisted to BuildId.txt.
    #>

    $buildId = $null

    if ($script:InTS) {
        $buildId = Get-TSValue -Name "OSDBuildId"
    }

    if (
        [string]::IsNullOrWhiteSpace($buildId) -and
        $script:Phase -ne "WinPE" -and
        (Test-Path $script:BuildIdFile)
    ) {
        try {
            $buildId = (Get-Content -Path $script:BuildIdFile -Raw).Trim()
            Write-OSDLog -Message "Recovered OSDBuildId from disk: $buildId"
        }
        catch {
            Write-OSDLog -Level WARN -Message "Unable to read BuildId file: $($_.Exception.Message)"
        }
    }

    if ([string]::IsNullOrWhiteSpace($buildId)) {
        if (-not $script:InTS) {
            throw "OSDBuildId is unavailable because the Task Sequence environment and BuildId file are both missing."
        }

        $buildId = [guid]::NewGuid().ToString()
        Write-OSDLog -Message "Generated new OSDBuildId: $buildId"
    }

    if ($script:InTS) {
        Set-TSValue -Name "OSDBuildId" -Value $buildId
    }

    if ($script:Phase -eq "FullOS") {
        New-Item -ItemType Directory -Path $script:TargetRoot -Force | Out-Null
        $buildId | Out-File -FilePath $script:BuildIdFile -Encoding ascii -Force
    }

    $script:BuildId = $buildId
}

function Install-OSDMonitorSelf {
    if ($script:Phase -ne "FullOS") {
        return
    }

    New-Item -ItemType Directory -Path $script:TargetRoot -Force | Out-Null

    try {
        $currentExe = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

        if (-not [string]::IsNullOrWhiteSpace($currentExe)) {
            $currentFull = [System.IO.Path]::GetFullPath($currentExe)
            $targetFull  = [System.IO.Path]::GetFullPath($script:TargetExe)

            if (-not $currentFull.Equals($targetFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                Copy-Item -Path $currentFull -Destination $script:TargetExe -Force
                Write-OSDLog -Message "Copied OSDMonitor to [$($script:TargetExe)]"
            }
        }
    }
    catch {
        Write-OSDLog -Level ERROR -Message "Self-copy failed: $($_.Exception.Message)"
        throw
    }
}

function Install-OSDMonitorScheduledTask {
    if ($script:Phase -ne "FullOS") {
        return
    }

    if (-not (Test-Path $script:TargetExe)) {
        Write-OSDLog -Level WARN -Message "Scheduled task not created because target EXE is missing."
        return
    }

    try {
        $existing = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue
        if ($existing) {
            return
        }

        $arguments = "/c start `"`" /min `"$($script:TargetExe)`" /resume"

        $action = New-ScheduledTaskAction `
            -Execute "cmd.exe" `
            -Argument $arguments

        $trigger = New-ScheduledTaskTrigger -AtStartup

        $principal = New-ScheduledTaskPrincipal `
            -UserId "SYSTEM" `
            -LogonType ServiceAccount `
            -RunLevel Highest

        $settings = New-ScheduledTaskSettingsSet `
            -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries `
            -StartWhenAvailable `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

        Register-ScheduledTask `
            -TaskName $script:TaskName `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force | Out-Null

        Write-OSDLog -Message "Registered startup scheduled task [$($script:TaskName)]"
    }
    catch {
        Write-OSDLog -Level WARN -Message "Scheduled task registration failed: $($_.Exception.Message)"
    }
}

function Remove-OSDMonitorScheduledTask {
    try {
        if (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
            Write-OSDLog -Message "Removed scheduled task [$($script:TaskName)]"
        }
    }
    catch {
        Write-OSDLog -Level WARN -Message "Scheduled task cleanup failed: $($_.Exception.Message)"
    }
}

function Promote-OSDMonitorLog {
    $destinationDirectory = "C:\Windows\CCM\Logs"
    $destinationLog = Join-Path $destinationDirectory "OSDMonitor.log"

    if (-not (Test-Path $script:LogFile)) {
        return
    }

    if (-not (Test-Path $destinationDirectory)) {
        return
    }

    try {
        Copy-Item -Path $script:LogFile -Destination $destinationLog -Force
        Write-OSDLog -Message "OSDMonitor log promoted to CCM Logs for audit."
    }
    catch {
        # Never block TS completion.
    }
}

function Get-ComputerIdentity {
    $make = $null
    $model = $null
    $serialNumber = $null

    try {
        $bios = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
        $make = $bios.Manufacturer
        $serialNumber = [string]$bios.SerialNumber
    }
    catch {
        try {
            $bios = Get-WmiObject -Class Win32_BIOS -ErrorAction Stop
            $make = $bios.Manufacturer
            $serialNumber = [string]$bios.SerialNumber
        }
        catch {}
    }

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $model = $computerSystem.Model
    }
    catch {
        try {
            $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
            $model = $computerSystem.Model
        }
        catch {}
    }

    [pscustomobject]@{
        Make         = $make
        Model        = $model
        SerialNumber = $serialNumber
    }
}

function Send-OSDStatus {
    param(
        [ValidateSet("Heartbeat", "StepChange", "Complete", "Error")]
        [string]$EventType = "Heartbeat",

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Status = "Info",

        [string]$StepName
    )

    if ($script:DisableAzure) {
        return
    }

    if (-not $script:InTS) {
        return
    }

    $workspaceId = Get-TSValue -Name "OSD_LogAnalytics_WorkspaceId"
    $sharedKey   = Get-TSValue -Name "OSD_LogAnalytics_SharedKey"

    if ([string]::IsNullOrWhiteSpace($workspaceId) -or [string]::IsNullOrWhiteSpace($sharedKey)) {
        Write-OSDLog -Level WARN -Message "Log Analytics credentials missing; ingestion skipped."
        return
    }

    $errorStepName = Get-TSValue -Name "ErrorStepName"
    $identity = Get-ComputerIdentity

    if ([string]::IsNullOrWhiteSpace($StepName)) {
        $StepName = Get-TSValue -Name "_SMSTSCurrentActionName"
    }

    $bodyObject = [ordered]@{
        Message         = $Message
        EventType       = $EventType
        BuildId         = $script:BuildId
        OSDStartTimer   = Get-TSValue -Name "TSstartTime"
        ComputerName    = Get-TSValue -Name "OSDComputerName"
        SiteCode        = Get-TSValue -Name "_SMSTSSiteCode"
        Make            = $identity.Make
        Model           = $identity.Model
        BIOSVersion     = Get-TSValue -Name "BIOSVersion"
        SerialNumber    = $identity.SerialNumber
        SMSTSRole       = Get-TSValue -Name "SMSTSRole"
        Status          = $Status
        StepName        = $StepName
        TaskSequence    = Get-TSValue -Name "_SMSTSPackageName"
        ErrorStepName   = $errorStepName
        Domain          = Get-TSValue -Name "Domain"
        ImagedByUser    = Get-TSValue -Name "ImagedByUser"
        DefaultGateway  = Get-TSValue -Name "DefaultGateway"
        IPAddress       = Get-TSValue -Name "IPAddress"
        isDesktop       = Get-TSValue -Name "isDesktop"
        DomainName      = Get-TSValue -Name "Domain"
        isLaptop        = Get-TSValue -Name "isLaptop"
        isVM            = Get-TSValue -Name "isVM"
        Product         = Get-TSValue -Name "Product"
        MacAddress      = Get-TSValue -Name "MacAddress"
        IsServer        = Get-TSValue -Name "IsServer"
        Phase           = $script:Phase
        TimeGenerated   = (Get-Date).ToUniversalTime().ToString("o")
    }

    $body = $bodyObject | ConvertTo-Json -Depth 5

    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $timestamp = [DateTime]::UtcNow.ToString("r")
    $contentLength = [Text.Encoding]::UTF8.GetByteCount($body)

    $stringToHash = "$method`n$contentLength`n$contentType`nx-ms-date:$timestamp`n$resource"
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)

    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    try {
        $hmac.Key = $keyBytes
        $signature = [Convert]::ToBase64String($hmac.ComputeHash($bytesToHash))
    }
    finally {
        $hmac.Dispose()
    }

    $headers = @{
        Authorization          = "SharedKey ${workspaceId}:$signature"
        "Log-Type"             = "OSDStatus"
        "x-ms-date"            = $timestamp
        "time-generated-field" = "TimeGenerated"
    }

    $uri = "https://${workspaceId}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"

    try {
        Invoke-RestMethod `
            -Method $method `
            -Uri $uri `
            -Headers $headers `
            -Body $body `
            -ContentType $contentType `
            -TimeoutSec 10 | Out-Null
    }
    catch {
        Write-OSDLog -Level WARN -Message "OSDStatus ingestion failed: $($_.Exception.Message)"
    }
}

function Get-OSDMonitorMode {
    $mode = "Normal"

    if ($script:InTS) {
        $value = Get-TSValue -Name "OSDMonitor_Mode"
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $mode = $value
        }
    }

    switch ($mode.ToLowerInvariant()) {
        "disabled" {
            Write-OSDLog -Message "OSDMonitor running in Disabled mode. Exiting."
            return "Disabled"
        }
        "diagnostics" {
            $script:DisableAzure = $true
            Write-OSDLog -Message "OSDMonitor running in Diagnostics mode."
            return "Diagnostics"
        }
        "silent" {
            $script:SilentMode = $true
            return "Silent"
        }
        default {
            return "Normal"
        }
    }
}

function Send-OSDTerminalStateSafe {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Success", "Failure")]
        [string]$State
    )

    try {
        Start-Sleep -Seconds 5

        $status = if ($State -eq "Success") { "Success" } else { "Error" }

        Send-OSDStatus `
            -EventType Complete `
            -Message "OSD completed with state [$State]" `
            -Status $status `
            -StepName "OSD TERMINAL"

        Write-OSDLog -Message "Terminal telemetry sent for state [$State]."
    }
    catch {
        Write-OSDLog -Level WARN -Message "Terminal telemetry failed: $($_.Exception.Message)"
    }
}

function Test-AndCleanupTerminalState {
    if (-not $script:InTS) {
        return $false
    }

    $state = Get-TSValue -Name "OSDMonitorState"

    if ($state -in @("Success", "Failure")) {
        Send-OSDTerminalStateSafe -State $state
        Remove-OSDMonitorScheduledTask
        Promote-OSDMonitorLog
        return $true
    }

    return $false
}

#region Initialization
Write-OSDLog -Message "Started | Phase=$($script:Phase)"

Initialize-BuildId

if ($script:Phase -eq "FullOS") {
    Install-OSDMonitorSelf
    Install-OSDMonitorScheduledTask
}

$mode = Get-OSDMonitorMode
if ($mode -eq "Disabled") {
    exit 0
}

Send-OSDStatus -EventType Heartbeat -Message "OSD Monitor started"
#endregion

#region Monitoring loop
$lastStepName  = $null
$lastExecState = $null
$lastResult    = $null

while ($true) {
    try {
        if (Test-AndCleanupTerminalState) {
            break
        }

        try {
            $script:TsEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
            $script:InTS = $true
        }
        catch {
            Write-OSDLog -Message "Task Sequence environment no longer available. Exiting monitor."
            break
        }

        $currentStep  = Get-TSValue -Name "_SMSTSCurrentActionName"
        $currentState = Get-TSValue -Name "_SMSTSExecutionState"
        $currentRes   = Get-TSValue -Name "_SMSTSLastActionSucceeded"

        if (
            $currentStep  -ne $lastStepName -or
            $currentState -ne $lastExecState -or
            $currentRes   -ne $lastResult
        ) {
            Write-OSDLog -Message "Step=$currentStep State=$currentState Result=$currentRes"

            $status = if ($currentRes -eq "false") { "Error" } else { "Info" }
            $eventType = if ($currentRes -eq "false") { "Error" } else { "StepChange" }

            Send-OSDStatus `
                -EventType $eventType `
                -Message "Step changed: $currentStep" `
                -Status $status `
                -StepName $currentStep

            $lastStepName  = $currentStep
            $lastExecState = $currentState
            $lastResult    = $currentRes
        }

        if ($currentState -eq "Complete") {
            Write-OSDLog -Message "Task Sequence completed. Exiting monitor."
            Send-OSDStatus `
                -EventType Complete `
                -Message "Task Sequence completed" `
                -Status Success `
                -StepName $currentStep
            break
        }
    }
    catch {
        Write-OSDLog -Level WARN -Message "Monitoring loop error: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 10
}
#endregion

#region Final cleanup
Remove-OSDMonitorScheduledTask
Promote-OSDMonitorLog
Start-Sleep -Seconds 5
#endregion

param(
    [Parameter(Mandatory)]
    [string]$LogFile,
        [string]$AppName
)

if (!(Test-Path $LogFile)) {
    throw "Cannot find $LogFile"
}

$OutputFolder = Join-Path (Split-Path $LogFile) "DecodedDetectionScripts"

New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

Get-Content $LogFile | ForEach-Object {

    if ($_ -notmatch 'Get policies =') {
        return
    }

    #
    # Extract ONLY the JSON
    #
    $Policy = ($_ -replace '^.*Get policies = ', '')
    $Policy = ($Policy -replace '\]\]LOG.*$', '')

    try {
        $Apps = $Policy | ConvertFrom-Json
    }
    catch {
        continue
    }
#
# Optionally allow the user to select a single application
#
#
# Ask which application to analyze
#
if ([string]::IsNullOrWhiteSpace($AppName))
{
    $AppName = Read-Host "Enter the Intune Application Name"
}

$Apps = $Apps | Where-Object {
    $_.Name -like "*$AppName*"
}

$Apps = $Apps |
    Sort-Object { [int]$_.Version } -Descending |
    Select-Object -First 1

if (!$Apps)
{
    Write-Host ""
    Write-Host "No application found matching '$AppName'." -ForegroundColor Red
    Write-Host ""

    Write-Host "Available Applications:" -ForegroundColor Yellow

    $Apps |
        Sort-Object Name |
        Select-Object -ExpandProperty Name -Unique |
        ForEach-Object { Write-Host "  $_" }

    return
}

if ($Apps.Count -gt 1)
{
    Write-Host ""
    Write-Host "Multiple applications matched '$AppName':" -ForegroundColor Yellow
    Write-Host ""

    $Apps |
        Sort-Object Name |
        Select-Object Name, Version |
        Format-Table -AutoSize

    return
}
    foreach ($App in $Apps) {
        Write-Host ""
        Write-Host "============================================================" -ForegroundColor Yellow
        Write-Host "Application"
        Write-Host "============================================================" -ForegroundColor Yellow

        Write-Host ("Name               : {0}" -f $App.Name)
        Write-Host ("ID                 : {0}" -f $App.Id)
        Write-Host ("Version            : {0}" -f $App.Version)

        switch ($App.Intent) {
            0 { $Intent = "Available" }
            1 { $Intent = "Uninstall" }
            3 { $Intent = "Required" }
            default { $Intent = $App.Intent }
        }

        switch ($App.TargetType) {
            1 { $Target = "User" }
            2 { $Target = "Device" }
            default { $Target = $App.TargetType }
        }

        switch ($App.InstallContext) {
            1 { $Context = "System" }
            2 { $Context = "User" }
            default { $Context = $App.InstallContext }
        }

        Write-Host ("Intent             : {0}" -f $Intent)
        Write-Host ("Target             : {0}" -f $Target)
        Write-Host ("Install Context    : {0}" -f $Context)

        Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Commands"
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Install"
Write-Host "-------"
Write-Host $App.InstallCommandLine

Write-Host ""
Write-Host "Uninstall"
Write-Host "---------"
Write-Host $App.UninstallCommandLine

$Requirements = $App.RequirementRules | ConvertFrom-Json

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Requirements"
Write-Host "============================================================" -ForegroundColor Cyan

$Architectures = @()

if($Requirements.RequiredOSArchitecture -band 1){$Architectures += "x86"}
if($Requirements.RequiredOSArchitecture -band 2){$Architectures += "x64"}
if($Requirements.RequiredOSArchitecture -band 4){$Architectures += "ARM"}
if($Requirements.RequiredOSArchitecture -band 8){$Architectures += "ARM64"}
if($Requirements.RequiredOSArchitecture -band 16){$Architectures += "x86 on ARM64"}
if($Requirements.RequiredOSArchitecture -band 32){$Architectures += "x64 on ARM64"}
if($Requirements.RequiredOSArchitecture -band 64){$Architectures += "Unknown64"}

Write-Host ""
Write-Host "Architecture"

$Architectures | ForEach-Object {
    Write-Host "  ✔ $_"
}

Write-Host ""

if($Requirements.MinimumWindows10BuildNumer)
{
    Write-Host ("Minimum Windows Build : {0}" -f $Requirements.MinimumWindows10BuildNumer)
}
else
{
    Write-Host "Minimum Windows Build : Not Configured"
}

Write-Host ("Minimum Memory        : {0}" -f ($Requirements.MinimumMemoryInMB ?? "Not Configured"))
Write-Host ("Minimum CPU Speed     : {0}" -f ($Requirements.MinimumCpuSpeed ?? "Not Configured"))
Write-Host ("Minimum Processors    : {0}" -f ($Requirements.MinimumNumberOfProcessors ?? "Not Configured"))
Write-Host ("Minimum Disk Space    : {0}" -f ($Requirements.MinimumFreeDiskSpaceInMB ?? "Not Configured"))

$InstallEx = $App.InstallEx | ConvertFrom-Json

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Install Experience"
Write-Host "============================================================" -ForegroundColor Cyan

switch($InstallEx.RunAs)
{
    1 {$RunAs="System"}
    2 {$RunAs="User"}
    default {$RunAs=$InstallEx.RunAs}
}

switch($InstallEx.DeviceRestartBehavior)
{
    0 {$Restart="Determine behavior based on return codes"}
    1 {$Restart="App may force restart"}
    2 {$Restart="No specific action"}
    3 {$Restart="Intune will force restart"}
    default {$Restart=$InstallEx.DeviceRestartBehavior}
}

Write-Host ("Run As               : {0}" -f $RunAs)
Write-Host ("Requires Logon       : {0}" -f $InstallEx.RequiresLogon)
Write-Host ("Maximum Runtime      : {0} Minutes" -f $InstallEx.MaxRunTimeInMinutes)
Write-Host ("Retry Count          : {0}" -f $InstallEx.MaxRetries)
Write-Host ("Retry Interval       : {0} Minutes" -f $InstallEx.RetryIntervalInMinutes)
Write-Host ("Restart Behavior     : {0}" -f $Restart)

$ReturnCodes = $App.ReturnCodes | ConvertFrom-Json

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "Return Codes"
Write-Host "============================================================" -ForegroundColor Cyan

foreach($RC in $ReturnCodes)
{
    switch($RC.Type)
    {
        0 {$Type="Failed"}
        1 {$Type="Success"}
        2 {$Type="Soft Reboot"}
        3 {$Type="Hard Reboot"}
        4 {$Type="Retry"}
        default {$Type=$RC.Type}
    }

    "{0,-8} {1}" -f $RC.ReturnCode,$Type | Write-Host
}
        $Detection = $App.DetectionRule | ConvertFrom-Json

        foreach ($Rule in $Detection) {
            if ($Rule.DetectionType -ne 3) {
                continue
            }

            $ScriptInfo = $Rule.DetectionText | ConvertFrom-Json

            $Script = [Text.Encoding]::UTF8.GetString(
                [Convert]::FromBase64String($ScriptInfo.ScriptBody)
            )

            Write-Host ""
            Write-Host $Script
            Write-Host ""

            $File = Join-Path $OutputFolder "$($App.Name)-Detection.ps1"

            $Script | Set-Content $File -Encoding UTF8

            Write-Host "Saved:"
            Write-Host $File
        }
    }
}
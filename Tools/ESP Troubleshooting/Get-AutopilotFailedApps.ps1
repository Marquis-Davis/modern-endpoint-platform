#requires -Version 5.1
#requires -RunAsAdministrator
# Read-only: Device setup / ESP-tracked Win32 apps. Run on the affected device.

if (-not [Environment]::Is64BitProcess) {
    throw 'Open 64-bit Windows PowerShell or PowerShell ISE and run this again.'
}

$Path = 'HKLM:\SOFTWARE\Microsoft\Windows\Autopilot\EnrollmentStatusTracking\Device\Setup\Apps\Tracking\Sidecar'
$LogFolder = "$env:ProgramData\Microsoft\IntuneManagementExtension\Logs"

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Warning 'No Device setup Sidecar tracking key found. A failed app cannot be identified from this registry location.'
    return
}

# The app ID is in the KEY NAME. InstallationState and ErrorHResult are values.
$Apps = @(foreach ($Key in (Get-ChildItem -LiteralPath $Path -ErrorAction Stop)) {
    if ($Key.PSChildName -notmatch '^Win32App_') { continue }

    $Values = Get-ItemProperty -LiteralPath $Key.PSPath -ErrorAction Stop
    $AppID = $Key.PSChildName -replace '^Win32App_', '' -replace '_\d+$', ''
    $State = switch ($Values.InstallationState) {
        1 { 'Not installed' }
        2 { 'In progress' }
        3 { 'Completed' }
        4 { 'Failed' }
        default { 'Unknown' }
    }

    $Code = 'Not recorded'
    if ($null -ne $Values.ErrorHResult) {
        # Handle both signed and unsigned DWORD representations.
        $Number = [long]$Values.ErrorHResult -band 4294967295L
        if ($Number -ne 0) { $Code = '0x{0:X8}' -f $Number }
    }

    [pscustomobject]@{
        AppID = $AppID
        State = $State
        Error = $Code
    }
})

if ($Apps.Count -eq 0) {
    Write-Warning 'No Win32 app tracking entries found. This does not mean every ESP app succeeded.'
    return
}

$Failed = @($Apps | Where-Object { $_.State -eq 'Failed' })
$Completed = @($Apps | Where-Object { $_.State -eq 'Completed' })
$Pending = @($Apps | Where-Object { $_.State -notin @('Failed', 'Completed') })
Write-Host "`nDevice setup: $($Failed.Count) failed, $($Completed.Count) completed, $($Pending.Count) incomplete."

$Show = $Failed
if ($Failed.Count -eq 0) {
    $Show = $Pending
    if ($Show.Count -eq 0) {
        Write-Warning 'All tracked Win32 apps report completed. This snapshot does not identify the cause of the ESP failure.'
        return
    }
    Write-Warning 'No app is marked Failed. Showing incomplete apps, not confirmed failures.'
}

# Read received app policies automatically. No Graph connection is required.
$Names = @{}
$Files = @()
if (Test-Path -LiteralPath $LogFolder) {
    $Files = @(Get-ChildItem -LiteralPath $LogFolder -File -ErrorAction Stop |
        Where-Object { $_.Name -match '^(AppWorkload|IntuneManagementExtension).*\.(log|lo_)$' } |
        Sort-Object LastWriteTime -Descending)
}

# Match the complete JSON array, including nested rules and escaped strings.
$Pattern = '(?is)Get policies\s*=\s*(?<Json>\[.*?\])\s*\]LOG\]!>'
$ParseFailures = 0
foreach ($File in $Files) {
    try {
        $Text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read $($File.Name): $($_.Exception.Message)"
        continue
    }

    $Records = [regex]::Matches([string]$Text, $Pattern)
    # Newest entry first, so old policy names do not overwrite newer names.
    for ($Index = $Records.Count - 1; $Index -ge 0; $Index--) {
        try {
            $Policies = $Records[$Index].Groups['Json'].Value | ConvertFrom-Json -ErrorAction Stop
            foreach ($Policy in $Policies) {
                if ($Policy.Id -and $Policy.Name -and -not $Names.ContainsKey([string]$Policy.Id)) {
                    $Names[[string]$Policy.Id] = [string]$Policy.Name
                }
            }
        }
        catch { $ParseFailures++ }
    }

    $Missing = @($Show | Where-Object { -not $Names.ContainsKey($_.AppID) })
    if ($Missing.Count -eq 0) { break }
}

$Report = @(foreach ($App in $Show) {
    $Name = $Names[$App.AppID]
    if (-not $Name) { $Name = 'Name unavailable in retained logs; use IntuneURL' }

    [pscustomobject]@{
        AppName = $Name
        State = $App.State
        Error = $App.Error
        AppID = $App.AppID
        IntuneURL = "https://intune.microsoft.com/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/$($App.AppID)"
    }
})

# Put entries carrying an explicit error code first, without assuming root cause.
$Report = @($Report | Sort-Object @{Expression = { $_.Error -eq 'Not recorded' }}, AppName)
$Report | Format-List

if ($ParseFailures -gt 0) {
    Write-Warning "$ParseFailures policy payload(s) could not be parsed. Some app names may be unavailable."
}

# Names come from retained local policy, not a live tenant lookup.
# Failed tracking entries can include dependency-related failures.
# This snapshot identifies affected apps, not necessarily the first/root failure.

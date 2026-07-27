# ===============================================================
# OSDMonitor Safety-Net Cleanup Script
# ===============================================================

$ErrorActionPreference = 'SilentlyContinue'

$ProcessName = 'OSDMonitor'
$TaskName    = 'OSDMonitor-SelfHeal'
$RootPath    = 'C:\ProgramData\OSDMonitor'
$ExePath     = Join-Path $RootPath 'OSDMonitor.exe'
$SourceLog   = Join-Path $RootPath 'OSDMonitor.log'
$CCMLogDir   = 'C:\Windows\CCM\Logs'
$DestLog     = Join-Path $CCMLogDir 'OSDMonitor.log'

Write-Output '[OSDMonitor-Cleanup] Starting safety-net cleanup'

# ---------------------------------------------------------------
# 0. Disable OSDMonitor self-healing
# ---------------------------------------------------------------

try {
    New-Item `
        -Path (Join-Path $RootPath 'terminal.state') `
        -ItemType File `
        -Force | Out-Null
}
catch {}

try {
    schtasks.exe /Delete /TN $TaskName /F | Out-Null
}
catch {}

try {
    auditpol.exe `
        /set `
        /subcategory:"Process Termination" `
        /success:disable | Out-Null
}
catch {}

# ---------------------------------------------------------------
# 1. Stop running OSDMonitor process
# ---------------------------------------------------------------

try {
    Get-Process `
        -Name $ProcessName `
        -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Output "[OSDMonitor-Cleanup] Stopping process PID $($_.Id)"

            Stop-Process `
                -Id $_.Id `
                -Force `
                -ErrorAction SilentlyContinue
        }
}
catch {}

# ---------------------------------------------------------------
# 2. Remove scheduled task if still present
# ---------------------------------------------------------------

try {
    $ScheduledTask = Get-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue

    if ($ScheduledTask) {
        Write-Output "[OSDMonitor-Cleanup] Removing scheduled task $TaskName"

        Unregister-ScheduledTask `
            -TaskName $TaskName `
            -Confirm:$false `
            -ErrorAction SilentlyContinue
    }
}
catch {}

# ---------------------------------------------------------------
# 3. Promote logs to CCM\Logs
# ---------------------------------------------------------------

try {
    if (Test-Path -Path $SourceLog) {

        if (-not (Test-Path -Path $CCMLogDir)) {
            New-Item `
                -ItemType Directory `
                -Path $CCMLogDir `
                -Force | Out-Null
        }

        Write-Output '[OSDMonitor-Cleanup] Moving log to CCM Logs'

        Move-Item `
            -Path $SourceLog `
            -Destination $DestLog `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
catch {}

# ---------------------------------------------------------------
# 4. Remove OSDMonitor executable
# ---------------------------------------------------------------

try {
    if (Test-Path -Path $ExePath) {
        Write-Output '[OSDMonitor-Cleanup] Deleting OSDMonitor.exe'

        Remove-Item `
            -Path $ExePath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
catch {}

# ---------------------------------------------------------------
# 5. Remove ProgramData working directory
# ---------------------------------------------------------------

try {
    if (Test-Path -Path $RootPath) {
        Write-Output '[OSDMonitor-Cleanup] Removing OSDMonitor directory'

        Remove-Item `
            -Path $RootPath `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}
catch {}

Write-Output '[OSDMonitor-Cleanup] Cleanup complete (safety-net)'

exit 0
[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $PSScriptRoot 'Output'),
    [int]$RefreshMilliseconds = 500
)

$logPath = Join-Path $OutputRoot 'DriverBiosAutomation.log'
$statusPath = Join-Path $OutputRoot 'status.json'

Write-Host 'Driver & BIOS Automation Live Watcher' -ForegroundColor Cyan
Write-Host 'Press Ctrl+C to stop.' -ForegroundColor DarkGray
Write-Host ''

$lastLogLength = 0

while ($true) {
    if (Test-Path $statusPath) {
        try {
            $state = Get-Content $statusPath -Raw | ConvertFrom-Json
            $current = if ($state.Current) {
                '{0} | {1} | {2} | {3}' -f $state.Current.Vendor, $state.Current.Model, $state.Current.Workload, $state.Current.Stage
            }
            else {
                'Idle / completed'
            }

            $statusLine = 'Run: {0} | Status: {1} | Completed: {2}/{3} | Failed: {4} | Current: {5}' -f `
                $state.RunId, $state.Status, $state.Completed, $state.Total, $state.Failed, $current

            Write-Host "`r$statusLine" -NoNewline
        }
        catch {
            # The writer may be replacing the JSON at the exact moment we read it.
        }
    }

    if (Test-Path $logPath) {
        $file = Get-Item $logPath
        if ($file.Length -gt $lastLogLength) {
            $all = Get-Content $logPath
            Clear-Host
            Write-Host 'Driver & BIOS Automation Live Watcher' -ForegroundColor Cyan
            Write-Host ('=' * 100) -ForegroundColor DarkGray
            $all | Select-Object -Last 35 | ForEach-Object { Write-Host $_ }
            Write-Host ('=' * 100) -ForegroundColor DarkGray
            $lastLogLength = $file.Length
        }
    }

    Start-Sleep -Milliseconds $RefreshMilliseconds
}

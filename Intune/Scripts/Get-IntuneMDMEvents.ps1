Get-WinEvent -LogName "Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin" -MaxEvents 100 |
Where-Object {$_.TimeCreated -gt (Get-Date).AddDays(-2)} |
Select-Object TimeCreated, Id, LevelDisplayName, Message
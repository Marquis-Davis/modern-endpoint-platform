# Deep dive specifically into MDM policy failures
Get-WinEvent -FilterHashtable @{
    LogName = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'
    Id      = 404
    StartTime = (Get-Date).AddDays(-2)
} | Select-Object TimeCreated, Id, Message | Format-List
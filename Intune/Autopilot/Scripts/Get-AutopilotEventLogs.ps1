Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
Where-Object {
    $_.LogName -match 'OOBE|CloudExperience|UserOOBE|Shell-Core|ModernDeployment'
} |
Select-Object LogName, IsEnabled, RecordCount |
Format-Table -AutoSize
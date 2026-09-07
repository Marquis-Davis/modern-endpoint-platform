# ESP Troubleshooting -- PowerShell Quick Links

A quick reference for PowerShell troubleshooting scripts that can be run
during Windows Autopilot / Enrollment Status Page (ESP) troubleshooting.

> **Usage:** Open **64-bit Windows PowerShell 5.1 as Administrator**.
> Review scripts before executing remote content.

## Get-AutopilotFailedApps

Displays failed applications detected during the Autopilot / ESP device
setup phase.

**GitHub source**

https://github.com/Marquis-Davis/modern-endpoint-platform/blob/main/Tools/ESP%20Troubleshooting/Get-AutopilotFailedApps.ps1

**Raw script**

https://raw.githubusercontent.com/Marquis-Davis/modern-endpoint-platform/main/Tools/ESP%20Troubleshooting/Get-AutopilotFailedApps.ps1

**Run from PowerShell**

``` powershell
irm 'https://raw.githubusercontent.com/Marquis-Davis/modern-endpoint-platform/main/Tools/ESP%20Troubleshooting/Get-AutopilotFailedApps.ps1' | iex
```

------------------------------------------------------------------------

## Additional Scripts

Use this template as the collection grows.

### Script-Name

**Purpose**

Brief description of what the script diagnoses or collects.

**GitHub source**

`https://github.com/...`

**Raw script**

`https://raw.githubusercontent.com/...`

**Run from PowerShell**

``` powershell
irm 'RAW-URL-HERE' | iex
```

------------------------------------------------------------------------

## Quick Copy/Paste

  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Tool                                PowerShell command
  ----------------------------------- ------------------------------------------------------------------------------------------------------------------------------------------------------
  Get-AutopilotFailedApps             `irm 'https://raw.githubusercontent.com/Marquis-Davis/modern-endpoint-platform/main/Tools/ESP%20Troubleshooting/Get-AutopilotFailedApps.ps1' \| iex`

  ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

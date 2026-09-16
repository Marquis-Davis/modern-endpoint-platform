# Driver & BIOS Automation Lab

This lab models the enterprise workflow used to discover, compare, package, publish, distribute, and validate HP and Dell driver/BIOS content for Microsoft Configuration Manager.

## What is included

- `Invoke-DriverBiosAutomationLab.ps1`
  - Simulates HP and Dell catalog discovery
  - Compares installed/package state to catalog versions
  - Simulates `curl.exe` download
  - Validates metadata
  - Simulates extraction
  - Builds Driver WIM or BIOS EXE package state
  - Simulates ConfigMgr package creation/update
  - Simulates content distribution
  - Writes live status and event files

- `Watch-DriverBiosAutomation.ps1`
  - Reads the generated status/log files continuously
  - Gives a live console view of the running workflow

## Output files

The lab writes these files under `Lab/Output`:

- `DriverBiosAutomation.log`
- `events.ndjson`
- `status.json`

This makes the run observable without requiring ConfigMgr.

## Run the simulation

```powershell
.\Invoke-DriverBiosAutomationLab.ps1
```

In another PowerShell window:

```powershell
.\Watch-DriverBiosAutomation.ps1
```

## Production design

The production version should keep the same workflow but replace the simulated stages with adapters for:

1. HP driver catalog and HP BIOS metadata
2. Dell DriverPackCatalog and CatalogPC BIOS metadata
3. Vendor payload download via `curl.exe`
4. Driver extraction and WIM creation
5. BIOS executable staging
6. ConfigMgr PowerShell module
7. Package create/update logic
8. Distribution Point / DP Group distribution
9. Content status validation
10. Structured JSON/log output for Azure Automation or dashboard consumption

## Why Live mode is blocked here

A real ConfigMgr build requires environment-specific values that should not be committed to a public repository, including:

- ConfigMgr site code/provider
- UNC content source paths
- Distribution point groups
- Package folder structure
- Service account / Hybrid Worker execution context

The public lab therefore defaults to a safe simulation while preserving the production workflow shape.

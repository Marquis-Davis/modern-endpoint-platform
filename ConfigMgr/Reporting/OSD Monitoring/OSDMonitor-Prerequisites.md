# OSDMonitor – Prerequisites and Initial Setup

## Purpose

OSDMonitor provides lightweight, real-time telemetry during a Microsoft Configuration Manager operating system deployment. It runs across WinPE and Full OS, reads Task Sequence state, and sends deployment telemetry to Azure Log Analytics.

The design is passive: OSDMonitor does not control the Task Sequence and should never be required for the Task Sequence to succeed.

---

## Required Components

Before adding OSDMonitor to a Task Sequence, confirm the following are available:

- Microsoft Configuration Manager Task Sequence
- x64 WinPE boot image
- PowerShell support in WinPE
- Network access from WinPE and Full OS to Azure Log Analytics ingestion endpoints
- Azure Log Analytics workspace
- Workspace ID and ingestion key stored as Task Sequence variables
- OSDMonitor package distributed to all required distribution points
- OSDMonitor cleanup step at the end of the Task Sequence

---

## Required Task Sequence Variables

Create and populate these variables before OSDMonitor starts:

| Variable | Purpose |
|---|---|
| `OSD_LogAnalytics_WorkspaceId` | Log Analytics workspace ID |
| `OSD_LogAnalytics_SharedKey` | Log Analytics ingestion key |
| `OSDBuildId` | Unique GUID used to correlate all telemetry for one build |
| `TSStartTime` | Task Sequence start time |
| `OSDComputerName` | Target computer name |
| `SMSTSRole` | Build role or deployment role |
| `ImagedByUser` | Engineer or technician starting the build, when available |
| `Domain` | Target domain |
| `BIOSVersion` | BIOS version, when collected |
| `DefaultGateway` | Default gateway, when collected |
| `IPAddress` | Device IP address, when collected |
| `MacAddress` | Device MAC address, when collected |
| `isDesktop` | Device type flag |
| `isLaptop` | Device type flag |
| `isVM` | Device type flag |
| `IsServer` | Device type flag |
| `Product` | Device product name or identifier |

Do not store workspace credentials directly in GitHub.

---

## Configuration Manager Package

Create a package containing:

```text
OSDMonitor.exe
Install-OSDMonitorResume.ps1
Cleanup-OSDMonitor.ps1
```

Recommended program settings:

- Run whether or not a user is logged on
- Run with administrative rights
- Allow execution from an Install Package Task Sequence step without a deployment
- Disable user interaction
- Distribute the package to every OSD distribution point

The executable must also be tested directly inside the WinPE boot image being used.

---

## Task Sequence Placement

OSDMonitor is launched three times to handle Task Sequence lifecycle boundaries.

### Phase 1 – WinPE

Place after disk partitioning and before long operating-system deployment actions.

Purpose:

- Begin WinPE telemetry
- Capture early Task Sequence activity
- Establish the build correlation ID

### Phase 2 – Setup Windows and ConfigMgr

Launch again after the ConfigMgr client setup boundary.

Purpose:

- Rehydrate monitoring after the WinPE-to-Full-OS transition
- Restore telemetry after Task Sequence execution-context changes

### Phase 3 – First Full OS Restart

Launch after the first restart into Full OS.

Purpose:

- Start the Full OS monitoring instance
- Install the temporary resume/self-healing task
- Maintain telemetry through software installation, updates, and remaining build steps

---

## Self-Healing Requirements

The Full OS phase uses Windows Process Termination auditing and a temporary scheduled task.

### Audit policy

The bootstrap script enables:

```powershell
auditpol /set /subcategory:"Process Termination" /success:enable
```

Verify with:

```powershell
auditpol /get /subcategory:"Process Termination"
```

Expected while OSDMonitor self-healing is active:

```text
Process Termination    Success
```

### Event trigger

Windows generates Security Event ID `4689` when `OSDMonitor.exe` terminates.

A scheduled task reacts to that event and runs a small gate script that:

1. Exits if OSD has reached terminal state
2. Exits if OSDMonitor is already running
3. Restarts `OSDMonitor.exe /resume` when it is not running

The scheduled task also includes an At Startup trigger for reboot recovery.

### Important behavior

- The Task Sequence does not poll for the process
- No permanent Windows service is installed
- The scheduled task is temporary
- OSDMonitor may restart with a new PID, but the build GUID must remain unchanged
- The EXE must support repeated startup without creating duplicate telemetry sessions

---

## Cleanup Requirements

The cleanup step must run near the end of the Task Sequence and should execute in this order:

1. Create the terminal marker
2. Delete the self-healing scheduled task
3. Disable Process Termination auditing
4. Stop OSDMonitor if it is still running
5. Copy OSDMonitor logs into the SMSTS log collection
6. Remove temporary OSDMonitor files

Example:

```powershell
$root = "C:\ProgramData\OSDMonitor"

New-Item -Path "$root\terminal.state" -ItemType File -Force | Out-Null

schtasks.exe /Delete /TN "OSDMonitor-SelfHeal" /F 2>$null | Out-Null

auditpol.exe /set /subcategory:"Process Termination" /success:disable | Out-Null

Get-Process -Name "OSDMonitor" -ErrorAction SilentlyContinue |
    Stop-Process -Force -ErrorAction SilentlyContinue
```

Verify audit cleanup with:

```powershell
auditpol /get /subcategory:"Process Termination"
```

Expected after cleanup:

```text
Process Termination    No Auditing
```

---

## Azure Log Analytics

OSDMonitor sends telemetry to a custom Log Analytics table.

At minimum, each record should contain:

- `BuildId`
- `ComputerName`
- `TaskSequence`
- `StepName`
- `EventType`
- `Status`
- `Message`
- `TimeGenerated`
- `SiteCode`
- `SMSTSRole`

The build GUID must be reused for every telemetry event generated during the same Task Sequence execution.

Do not use a human-readable step name as the only success signal. Step names can be renamed.

Recommended terminal fields:

```text
EventType = TSFinalState
Status = Success
```

Example KQL:

```kusto
OSDStatus_CL
| where EventType_s == "TSFinalState"
| where Status_s == "Success"
| summarize arg_max(TimeGenerated, *) by BuildId_s
```

---

## Validation Checklist

Before production rollout, validate the following in QA:

- OSDMonitor starts in WinPE
- Telemetry reaches Log Analytics from WinPE
- OSDMonitor starts after Setup Windows and ConfigMgr
- OSDMonitor starts after the first Full OS reboot
- The self-healing task is created
- Process Termination auditing is enabled
- Manually stopping OSDMonitor generates Event ID 4689
- OSDMonitor automatically restarts with a new PID
- The same build GUID is retained
- The Task Sequence continues when OSDMonitor is stopped
- Cleanup removes the scheduled task
- Cleanup disables Process Termination auditing
- Logs are copied into the final SMSTS log archive
- No OSDMonitor process remains after the build

---

## Security Notes

- Never commit the Log Analytics shared key to GitHub
- Store secrets in Task Sequence variables or an approved secret-management system
- Mark sensitive Task Sequence variables so they are not displayed in logs
- Use HTTPS only
- Limit telemetry to operational deployment data
- Review any user, IP address, serial number, or device identity fields before production use
- Restrict Log Analytics access through Azure RBAC

---

## Recommended Repository Layout

```text
OSDMonitor/
├── README.md
├── docs/
│   ├── Prerequisites.md
│   ├── TaskSequence-Integration.md
│   ├── Self-Healing.md
│   └── Log-Analytics.md
├── src/
│   └── OSDMonitor/
├── scripts/
│   ├── Install-OSDMonitorResume.ps1
│   └── Cleanup-OSDMonitor.ps1
├── kql/
│   ├── Successful-Builds.kql
│   ├── Failed-Builds.kql
│   └── Active-Builds.kql
└── examples/
    └── TaskSequence-Layout.md
```

---

## Production Recommendation

Treat OSDMonitor as an optional observability layer.

A failure to start, restart, or send telemetry must never fail the operating-system deployment. All OSDMonitor Task Sequence steps should return safely and must not block Task Sequence execution.

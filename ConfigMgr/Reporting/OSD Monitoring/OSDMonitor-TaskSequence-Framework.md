# OSDMonitor – Task Sequence Framework

## Overview

This guide outlines the recommended Framework placement of OSDMonitor inside a Microsoft Configuration Manager Operating System Deployment Task Sequence.

OSDMonitor is designed to run as a lightweight, non-blocking telemetry process during WinPE and Full OS phases. Every OSDMonitor-related Task Sequence step should have **Continue on error** enabled so monitoring can never fail the operating system deployment.

---

## 1. Initialize Variables

Create an **Initialize Variables** group near the beginning of the Task Sequence.

Inside that group, add a **Set Dynamic Variables** step and define the following variables:

| Variable | Value |
|---|---|
| `OSD_LogAnalytics_WorkspaceID` | `""` |
| `OSD_LogAnayltics_SharedKey` | `""` |

Populate these values with the correct Azure Log Analytics workspace credentials for the environment.

> Do not store production workspace credentials directly in source control.

---

## 2. OSD Monitor Phase 1

Place this step in the **Install Operating System** group immediately after the disk partitioning and formatting step.

### Step configuration

**Step type:** Run Command Line  
**Step name:** `OSD Monitor Phase 1`

**Command line:**

```cmd
cmd.exe /c start "" OSDMonitor.exe
```

**Package:**

```text
OSD - Task Sequence Monitor
```

### Purpose

Phase 1 starts OSDMonitor during WinPE so the deployment can begin reporting telemetry before the operating system is applied.

### Recommended options

- Enable **Continue on error**
- Attach the OSDMonitor package directly to the step
- Run in the normal Task Sequence execution context

---

## 3. OSD Monitor Phase 2

Place this step after the Configuration Manager client has been installed.

### Step configuration

**Step type:** Run Command Line  
**Step name:** `OSD Monitor Phase 2`

**Command line:**

```cmd
cmd.exe /c start "" OSDMonitor.exe
```

**Package:**

```text
OSD - Task Sequence Monitor
```

### Purpose

Phase 2 restarts OSDMonitor after the Configuration Manager client installation boundary.

This ensures monitoring resumes after the transition from the initial WinPE deployment phase.

### Recommended options

- Enable **Continue on error**
- Attach the OSDMonitor package directly to the step

---

## 4. OSD Monitor Phase 3

Create this step after the first restart into Full OS.

### Step configuration

**Step type:** Run Command Line  
**Step name:** `OSD Monitor Phase 3`

**Command line:**

```cmd
cmd.exe /c start "" OSDMonitor.exe
```

**Package:**

```text
OSD - Task Sequence Monitor
```

### Purpose

Phase 3 starts OSDMonitor inside the full Windows operating system so monitoring can continue through the remainder of the deployment.

### Recommended options

- Enable **Continue on error**
- Attach the OSDMonitor package directly to the step

---

## 5. OSD Monitor Self-Healing

Create this step shortly after **OSD Monitor Phase 3**.

### Step configuration

**Step type:** Run PowerShell Script  
**Step name:** `OSD Monitor Self-Healing`

Add the OSDMonitor self-healing PowerShell script to this step.

### PowerShell settings

Set the PowerShell execution policy to:

```text
Bypass
```

### Purpose

The self-healing script:

- Enables Process Termination auditing
- Creates the temporary OSDMonitor scheduled task
- Adds startup and process-termination recovery triggers
- Restarts OSDMonitor if the process terminates unexpectedly
- Prevents duplicate OSDMonitor processes
- Stops restarting OSDMonitor once the terminal state marker exists

### Recommended options

- Enable **Continue on error**
- Use the same OSDMonitor package or script package as required
- Confirm the scheduled task is created under the correct security context

---

## 6. OSD Monitor Cleanup

Place this step as the final step inside the Task Sequence **Success Group**.

### Step configuration

**Step type:** Run PowerShell Script  
**Step name:** `OSD Monitor - Cleanup`

Add the OSDMonitor cleanup PowerShell script to this step.

### PowerShell settings

Set the PowerShell execution policy to:

```text
Bypass
```

### Purpose

The cleanup script performs the final OSDMonitor shutdown and removal tasks.

It should:

- Create the terminal state marker
- Disable OSDMonitor self-healing
- Remove the OSDMonitor scheduled task
- Disable Process Termination auditing
- Stop any running `OSDMonitor.exe` process
- Promote OSDMonitor logs into the ConfigMgr client log folder
- Copy logs into:

```text
C:\Windows\CCM\Logs
```

- Remove `OSDMonitor.exe`
- Remove the OSDMonitor folder under:

```text
C:\ProgramData\OSDMonitor
```

### Recommended options

- Enable **Continue on error**
- Make this the final step in the successful deployment path
- Ensure log promotion occurs before OSDMonitor files and folders are removed

---

## Recommended Task Sequence Layout

```text
Initialize Variables
└── Set Dynamic Variables
    ├── OSD_LogAnalytics_WorkspaceID
    └── OSD_LogAnayltics_SharedKey

Install Operating System
├── Partition and Format Disk
├── OSD Monitor Phase 1
├── Apply Operating System
├── Setup Windows and ConfigMgr
└── OSD Monitor Phase 2

Restart into Full OS
├── OSD Monitor Phase 3
└── OSD Monitor Self-Healing

Remaining Build Steps
├── Applications
├── Drivers
├── Updates
├── Configuration
└── Validation

Success Group
└── OSD Monitor - Cleanup
```

---

## Important Configuration Rule

Every OSDMonitor-related Task Sequence step must have:

```text
Continue on error = Enabled
```

This includes:

- OSD Monitor Phase 1
- OSD Monitor Phase 2
- OSD Monitor Phase 3
- OSD Monitor Self-Healing
- OSD Monitor - Cleanup

OSDMonitor is an observability component and must never become a dependency for Task Sequence success.

If OSDMonitor fails to launch, restart, send telemetry, or clean itself up, the operating system deployment must continue.

---

## Final Validation

Before using the Task Sequence as a template, validate that:

- Phase 1 launches in WinPE
- Phase 2 launches after ConfigMgr client installation
- Phase 3 launches after the first Full OS restart
- Self-healing creates the scheduled task
- Stopping OSDMonitor causes it to restart
- Cleanup removes the scheduled task
- Cleanup disables auditing
- Cleanup stops OSDMonitor
- Logs are copied to `C:\Windows\CCM\Logs`
- The OSDMonitor executable is removed
- `C:\ProgramData\OSDMonitor` is removed
- The Task Sequence succeeds even if an OSDMonitor step fails

---

## Template Recommendation

Once validated, use this Task Sequence as the approved OSD build template.

Engineers creating new builds should copy the template rather than manually recreating the OSDMonitor steps. This preserves consistent placement, naming, package references, telemetry behavior, self-healing, and cleanup across all OSD deployments.

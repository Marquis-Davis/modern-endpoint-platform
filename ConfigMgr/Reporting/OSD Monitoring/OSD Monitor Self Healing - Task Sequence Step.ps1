# ===============================================================
# OSDMonitor Self-Healing Setup
# ===============================================================

$Root = "C:\ProgramData\OSDMonitor"
$Exe = "$Root\OSDMonitor.exe"
$GateCmd = "$Root\SelfHeal.cmd"
$TaskName = "OSDMonitor-SelfHeal"

# ---- Sanity check ----

if (-not (Test-Path $Exe)) {
  return
}

# ---------------------------------------------------------------
# 1. Create gate script
# ---------------------------------------------------------------

$GateContent = @"
@echo off

REM Stop permanently once OSD is complete
if exist C:\ProgramData\OSDMonitor\terminal.state exit /b 0

REM Prevent duplicate instances
tasklist /fi "imagename eq OSDMonitor.exe" | find /i "OSDMonitor.exe" >nul && exit /b 0

REM Restart monitor
start "" "C:\ProgramData\OSDMonitor\OSDMonitor.exe" /resume
"@

New-Item `
  -ItemType Directory `
  -Path $Root `
  -Force | Out-Null

Set-Content `
  -Path $GateCmd `
  -Value $GateContent `
  -Encoding ASCII `
  -Force

# ---------------------------------------------------------------
# 2. Ensure audit policy
# ---------------------------------------------------------------

$Audit = auditpol.exe `
  /get `
  /subcategory:"Process Termination" 2>$null

if ($Audit -notmatch "Success") {
  auditpol.exe `
    /set `
    /subcategory:"Process Termination" `
    /success:enable | Out-Null
}

# ---------------------------------------------------------------
# 3. Build scheduled task
# ---------------------------------------------------------------

$TaskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>
        <![CDATA[
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4689)]]
    </Select>
  </Query>
</QueryList>
        ]]>
      </Subscription>
    </EventTrigger>

    <BootTrigger />
  </Triggers>

  <Principals>
    <Principal id="System">
      <UserId>S-1-5-18</UserId>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>

  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT2M</ExecutionTimeLimit>
  </Settings>

  <Actions Context="System">
    <Exec>
      <Command>cmd.exe</Command>
      <Arguments>/c "$GateCmd"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

$XmlPath = "$Root\OSDMonitor-SelfHeal.xml"

Set-Content `
  -Path $XmlPath `
  -Value $TaskXml `
  -Encoding Unicode `
  -Force

# ---------------------------------------------------------------
# 4. Register task (idempotent)
# ---------------------------------------------------------------

schtasks.exe `
  /delete `
  /tn $TaskName `
  /f 2>$null

schtasks.exe `
  /create `
  /tn $TaskName `
  /xml $XmlPath `
  /ru SYSTEM `
  /f | Out-Null
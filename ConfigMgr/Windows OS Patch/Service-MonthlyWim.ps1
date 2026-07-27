# ============================================================
# .NET 3.5 Offline Injection for Windows WIM
# ============================================================

# --- TARGET SELECTOR ---
$Target = "Win11_24H2"
$PatchMonth = "0526"

# --- IMAGE CONFIGS ---
$ImageConfigs = @{
    Win11_25H2 = @{
        Name        = "Windows 11 25H2"
        SourceWim   = "E:\Sources\install.wim"
        SourceIndex = 3
    }

    Win11_23H2 = @{
        Name        = "Windows 11 23H2"
        SourceWim   = "E:\Sources\install.wim"
        SourceIndex = 3
    }

    Win11_24H2 = @{
        Name        = "Windows 11 24H2"
        SourceWim   = "E:\Sources\install.wim"
        SourceIndex = 3
    }

    Win10_22H2 = @{
        Name        = "Windows 10 22H2"
        SourceWim   = "E:\Sources\install.wim"
        SourceIndex = 3
    }
}

# --- PATH CONFIG ---
$WorkRoot = "C:\temp\.Net"
$MountPath = "C:\Mount"

$CabNasPath = "\\NAS\Share\NetFx3\microsoft-windows-netfx3-ondemand-package~31bf3856ad364e35~amd64~~.cab"

$CabLocalFolder = Join-Path $WorkRoot "cab"
$CabLocalPath = Join-Path $CabLocalFolder "microsoft-windows-netfx3-ondemand-package~31bf3856ad364e35~amd64~~.cab"

$OutputFolder = Join-Path $WorkRoot "Output"
$LogFolder = Join-Path $WorkRoot "Logs"

# --- SELECT TARGET CONFIG ---
if (-not $ImageConfigs.ContainsKey($Target)) {
    throw "Invalid target '$Target'. Valid options are: $($ImageConfigs.Keys -join ', ')"
}

$SelectedImage = $ImageConfigs[$Target]

$TargetImageName = $SelectedImage.Name
$SourceWim = $SelectedImage.SourceWim
$SourceIndex = $SelectedImage.SourceIndex

# --- DERIVED NAMES ---
$SafeImageName = $TargetImageName -replace '[\\/:*?"<>| ]', '_'
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

$ExportedWim = Join-Path $OutputFolder "$($SafeImageName)_PatchMonth_$PatchMonth.wim"
$LogPath = Join-Path $LogFolder "$($SafeImageName)_NetFx3_$PatchMonth_$TimeStamp.log"

# --- ENVIRONMENT PREP ---
foreach ($Path in @($WorkRoot, $MountPath, $CabLocalFolder, $OutputFolder, $LogFolder)) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

Start-Transcript -Path $LogPath -Append

Write-Output "============================================================"
Write-Output "Starting .NET 3.5 Offline Injection"
Write-Output "============================================================"
Write-Output "Timestamp : $(Get-Date)"
Write-Output "Target : $Target"
Write-Output "Image Name : $TargetImageName"
Write-Output "Patch Month : $PatchMonth"
Write-Output "Source WIM : $SourceWim"
Write-Output "Source Index : $SourceIndex"
Write-Output "Exported WIM : $ExportedWim"
Write-Output "Mount Path : $MountPath"
Write-Output "CAB NAS Path : $CabNasPath"
Write-Output "Local CAB : $CabLocalPath"
Write-Output "Log File : $LogPath"
Write-Output "============================================================"
Write-Output ""

try {
    # 1. Clean up any previous stale mounts
    Write-Output "Checking for abandoned image mounts..."

    Get-WindowsImage -Mounted |
    Where-Object { $_.MountPath -eq $MountPath } |
    ForEach-Object {
        Write-Warning "Found stale mount at $MountPath. Discarding..."
        Dismount-WindowsImage -Path $_.MountPath -Discard -ErrorAction Stop
    }

    # 2. Copy NetFx3 CAB locally
    Write-Output "Copying NetFx3 CAB locally..."
    Copy-Item -Path $CabNasPath -Destination $CabLocalPath -Force -ErrorAction Stop

    # 3. Export target index locally
    Write-Output "Exporting $TargetImageName from source WIM..."
    Write-Output "Source : $SourceWim"
    Write-Output "Index : $SourceIndex"
    Write-Output "Destination : $ExportedWim"

    if (Test-Path $ExportedWim) {
        Write-Warning "Existing exported WIM found. Removing old file..."
        Remove-Item $ExportedWim -Force
    }

    Dism /Export-Image /SourceImageFile:$SourceWim /SourceIndex:$SourceIndex /DestinationImageFile:$ExportedWim /Compress:max /CheckIntegrity

    if (-not (Test-Path $ExportedWim)) {
        throw "Export failed. Exported WIM was not created: $ExportedWim"
    }

    # 4. Mount exported WIM
    Write-Output "Mounting exported WIM..."
    Mount-WindowsImage -ImagePath $ExportedWim -Index 1 -Path $MountPath -ErrorAction Stop

    # 5. Detect mounted image info
    Write-Output "Detecting mounted Windows image info..."

    $ImageInfo = Get-WindowsImage -Mounted |
    Where-Object { $_.MountPath -eq $MountPath }

    Write-Output "Mounted Image Name : $($ImageInfo.ImageName)"
    Write-Output "Mounted Image Version : $($ImageInfo.Version)"
    Write-Output "Mounted Image Description : $($ImageInfo.ImageDescription)"
    Write-Output ""

    # 6. Add .NET 3.5 package
    Write-Output "Injecting .NET Framework 3.5 CAB..."
    Add-WindowsPackage -Path $MountPath -PackagePath $CabLocalPath -ErrorAction Stop

    # 7. Verify .NET package state using DISM
    Write-Output ""
    Write-Output "=== DISM NETFX PACKAGE CHECK ==="

    $DismCheck = dism /Get-Packages /Image:$MountPath |
    Select-String "NetFx" -Context 0, 5

    if ($DismCheck) {
        $DismCheck | ForEach-Object {
            Write-Output $_.ToString()
        }

        $PendingFound = $DismCheck | Where-Object {
            $_.ToString() -match "Install Pending"
        }

        $InstalledFound = $DismCheck | Where-Object {
            $_.ToString() -match "Installed"
        }

        if ($PendingFound -or $InstalledFound) {
            Write-Output "VALIDATION PASSED: NetFx3 package detected and servicing state recorded."
        }
        else {
            Write-Warning "VALIDATION WARNING: NetFx3 package found but no Installed or Install Pending state detected."
        }
    }
    else {
        throw "VALIDATION FAILED: NetFx3 package was not found in the mounted image."
    }

    # 8. Commit and unmount
    Write-Output ""
    Write-Output "Committing changes and unmounting WIM..."
    Dismount-WindowsImage -Path $MountPath -Save -ErrorAction Stop

    Write-Output "Successfully updated WIM with .NET 3.5."
    Write-Output "Final WIM: $ExportedWim"
}
catch {
    Write-Error "An error occurred during servicing: $_"

    if (Get-WindowsImage -Mounted | Where-Object { $_.MountPath -eq $MountPath }) {
        Write-Warning "Error caught. Attempting to discard changes and unmount to prevent file locks..."
        Dismount-WindowsImage -Path $MountPath -Discard
    }
}
finally {
    Stop-Transcript
}

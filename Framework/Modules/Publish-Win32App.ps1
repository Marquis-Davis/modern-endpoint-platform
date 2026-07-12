function Publish-Win32App {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory)]
        [string]$ApplicationFolder,

        [Parameter(Mandatory)]
        [string]$Package
    )

    #============================================================
    # Detection Rule
    #============================================================

    Write-Host ""
    Write-Host "Creating Detection Rule..." -ForegroundColor Yellow

    switch ($Manifest.Detection.Type)
    {
        "PowerShell"
        {
            $DetectionScript = Join-Path `
                $ApplicationFolder `
                $Manifest.Detection.PowerShell.Script

            if (!(Test-Path $DetectionScript))
            {
                throw "Detection script not found: $DetectionScript"
            }

            $DetectionRule = New-IntuneWin32AppDetectionRuleScript `
                -ScriptFile $DetectionScript `
                -EnforceSignatureCheck $Manifest.Detection.PowerShell.EnforceSignatureCheck `
                -RunAs32Bit $Manifest.Detection.PowerShell.RunAs32Bit
        }

        default
        {
            throw "Detection type '$($Manifest.Detection.Type)' is not supported."
        }
    }

    #============================================================
    # Requirement Rule
    #============================================================

    Write-Host "Creating Requirement Rule..." -ForegroundColor Yellow

    $RequirementParams = @{
        Architecture                   = $Manifest.Requirements.Architecture
        MinimumSupportedWindowsRelease = $Manifest.Requirements.MinimumSupportedWindowsRelease
    }

    if ($null -ne $Manifest.Requirements.MinimumDiskSpaceMB)
    {
        $RequirementParams.MinimumFreeDiskSpaceInMB =
            $Manifest.Requirements.MinimumDiskSpaceMB
    }

    if ($null -ne $Manifest.Requirements.MinimumMemoryMB)
    {
        $RequirementParams.MinimumMemoryInMB =
            $Manifest.Requirements.MinimumMemoryMB
    }

    if ($null -ne $Manifest.Requirements.MinimumCpuSpeedMHz)
    {
        $RequirementParams.MinimumCpuSpeedInMHz =
            $Manifest.Requirements.MinimumCpuSpeedMHz
    }

    if ($null -ne $Manifest.Requirements.MinimumLogicalProcessors)
    {
        $RequirementParams.MinimumLogicalProcessorCount =
            $Manifest.Requirements.MinimumLogicalProcessors
    }

    $RequirementRule = New-IntuneWin32AppRequirementRule @RequirementParams

    #============================================================
    # Install Command
    #============================================================

    $InstallCommand = $Manifest.Install.Command

    if (![string]::IsNullOrWhiteSpace($Manifest.Install.Arguments))
    {
        $InstallCommand += " $($Manifest.Install.Arguments)"
    }

    #============================================================
    # Uninstall Command
    #============================================================

    $UninstallCommand = $Manifest.Uninstall.Command

    if (![string]::IsNullOrWhiteSpace($Manifest.Uninstall.Arguments))
    {
        $UninstallCommand += " $($Manifest.Uninstall.Arguments)"
    }

    #============================================================
    # Summary
    #============================================================

    Write-Host ""
    Write-Host "Application Summary" -ForegroundColor Cyan
    Write-Host "-------------------"
    Write-Host "Name              : $($Manifest.Application.Name)"
    Write-Host "Publisher         : $($Manifest.Application.Publisher)"
    Write-Host "Version           : $($Manifest.Application.Version)"
    Write-Host "Package           : $Package"
    Write-Host "Install Command   : $InstallCommand"
    Write-Host "Uninstall Command : $UninstallCommand"
    Write-Host ""

    #============================================================
    # Create Win32 App
    #============================================================

    Write-Host "Creating Win32 Application..." -ForegroundColor Yellow

    try
    {
        $Win32App = Add-IntuneWin32App `
            -FilePath $Package `
            -DisplayName $Manifest.Application.Name `
            -Description $Manifest.Application.Description `
            -Publisher $Manifest.Application.Publisher `
            -AppVersion $Manifest.Application.Version `
            -Developer $Manifest.Application.Developer `
            -Owner $Manifest.Application.Owner `
            -InstallCommandLine $InstallCommand `
            -UninstallCommandLine $UninstallCommand `
            -InstallExperience $Manifest.Install.installExperience.runAsAccount `
            -RestartBehavior $Manifest.Install.installExperience.deviceRestartBehavior `
            -DetectionRule $DetectionRule `
            -RequirementRule $RequirementRule

        Write-Host ""
        Write-Host "Win32 Application Created Successfully." -ForegroundColor Green
        Write-Host "Application ID : $($Win32App.Id)"
        Write-Host ""

        return $Win32App
    }
    catch
    {
        Write-Host ""
        Write-Host "Failed to create Win32 Application." -ForegroundColor Red
        throw
    }
}
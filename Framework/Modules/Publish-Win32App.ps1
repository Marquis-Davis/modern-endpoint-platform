function Publish-Win32App {

    param(
        [Parameter(Mandatory)]
        $Manifest,

        [Parameter(Mandatory)]
        [string]$ApplicationFolder,

        [Parameter(Mandatory)]
        [string]$Package,

        [Parameter(Mandatory)]
        $DeploymentGroup
    )

    Write-Host ""
    Write-Host "Creating Detection Rule..." -ForegroundColor Yellow

    $DetectionRule = New-IntuneWin32AppDetectionRuleScript `
        -ScriptFile (Join-Path $ApplicationFolder $Manifest.Detection.Script) `
        -EnforceSignatureCheck $false `
        -RunAs32Bit $false

    Write-Host "Creating Requirement Rule..." -ForegroundColor Yellow

    $RequirementRule = New-IntuneWin32AppRequirementRule `
        -Architecture AllWithARM64 `
        -MinimumSupportedWindowsRelease W11_22H2

    Write-Host ""
    Write-Host "Uploading Win32 App..." -ForegroundColor Yellow

    try
    {
        $Win32App = Add-IntuneWin32App `
            -FilePath $Package `
            -DisplayName $Manifest.Application.Name `
            -Description $Manifest.Application.Description `
            -Publisher $Manifest.Application.Publisher `
            -AppVersion $Manifest.Application.Version `
            -Developer $Manifest.Application.Publisher `
            -Owner $Manifest.Application.Publisher `
            -InstallCommandLine $Manifest.Install.Command `
            -UninstallCommandLine $Manifest.Install.UninstallCommand `
            -InstallExperience System `
            -RestartBehavior Suppress `
            -DetectionRule $DetectionRule `
            -RequirementRule $RequirementRule

        Write-Host ""
        Write-Host "Assigning Application..." -ForegroundColor Yellow

        Add-IntuneWin32AppAssignmentGroup `
            -Include `
            -ID $Win32App.Id `
            -GroupID $DeploymentGroup.Id `
            -Intent Required

        Write-Host ""
        Write-Host "Application published successfully!" -ForegroundColor Green
        Write-Host "Application ID : $($Win32App.Id)"
    }
    catch
    {
        Write-Host ""
        Write-Host "Publish failed." -ForegroundColor Red
        throw
    }
}
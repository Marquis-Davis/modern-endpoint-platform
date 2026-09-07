# Centralized exporter definitions. This file sorts after the legacy modules and
# intentionally replaces their function definitions with consistent snapshot logic.

function Export-ConfigurationProfiles {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'ConfigurationProfiles' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations' `
        -FilterScript { $_.'@odata.type' -ne '#microsoft.graph.windowsUpdateForBusinessConfiguration' } `
        -RelatedCollections @('assignments') -Label 'Configuration Profiles'
}

function Export-SettingsCatalog {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'SettingsCatalog' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' `
        -FilterScript { $_.templateReference.templateFamily -eq 'none' } `
        -RelatedCollections @('settings', 'assignments') -Label 'Settings Catalog Policies'
}

function Export-AdministrativeTemplates {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $CollectionUri = 'https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations'
    $Items = [System.Collections.Generic.List[object]]::new()
    Write-Host 'Exporting Administrative Templates...' -ForegroundColor Cyan
    foreach ($Item in Get-GraphCollection -Uri $CollectionUri) {
        $ObjectUri = "$CollectionUri/$($Item.id)"
        $Object = Get-GraphObjectWithRelatedData -ObjectUri $ObjectUri -RelatedCollections @('assignments')
        $DefinitionValuesUri = "$ObjectUri/definitionValues?`$expand=definition,presentationValues"
        $DefinitionValues = @(Get-GraphCollection -Uri $DefinitionValuesUri | Sort-Object id)
        Add-SnapshotProperty -InputObject $Object -Name 'definitionValues' -Value $DefinitionValues
        $Items.Add($Object)
    }
    Export-SnapshotObjects -OutputPath (Join-Path $RepositoryRoot 'AdministrativeTemplates') `
        -InputObject $Items.ToArray() -NameScript { param($Item) $Item.displayName }
    Write-Host "Exported $($Items.Count) Administrative Template object(s)." -ForegroundColor Green
    Write-Host ''
}

function Export-EndpointSecurity {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Security' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' `
        -FilterScript { [string]$_.templateReference.templateFamily -like 'endpointSecurity*' } `
        -RelatedCollections @('settings', 'assignments') -Label 'Endpoint Security Policies'
}

function Export-CompliancePolicies {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'CompliancePolicies' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies' `
        -RelatedCollections @('assignments') -Label 'Compliance Policies'
}

function Export-UpdateRings {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'UpdateRings' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations' `
        -FilterScript { $_.'@odata.type' -eq '#microsoft.graph.windowsUpdateForBusinessConfiguration' } `
        -RelatedCollections @('assignments') -Label 'Update Rings'
}

function Export-FeatureUpdates {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'FeatureUpdates' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles' `
        -RelatedCollections @('assignments') -Label 'Feature Update Profiles'
}

function Export-DriverUpdates {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'DriverUpdates' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles' `
        -RelatedCollections @('assignments') -Label 'Driver Update Profiles'
}

function Export-QualityUpdates {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'QualityUpdates' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles' `
        -RelatedCollections @('assignments') -Label 'Quality Update Profiles'
}

function Export-PowerShellScripts {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Scripts' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts' `
        -RelatedCollections @('assignments') -Label 'PowerShell Scripts'
}

function Export-Remediations {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Remediations' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts' `
        -RelatedCollections @('assignments') -Label 'Remediations'
}

function Export-ShellScripts {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'ShellScripts' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceShellScripts' `
        -RelatedCollections @('assignments') -Label 'Shell Scripts'
}

function Export-Win32Apps {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Applications\Win32' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
        -FilterScript { $_.'@odata.type' -eq '#microsoft.graph.win32LobApp' } `
        -RelatedCollections @('assignments') -Label 'Win32 Apps'
}

function Export-MicrosoftStoreApps {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Applications\MicrosoftStore' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
        -FilterScript { $_.'@odata.type' -in @('#microsoft.graph.microsoftStoreForBusinessApp', '#microsoft.graph.winGetApp') } `
        -RelatedCollections @('assignments') -Label 'Microsoft Store Apps'
}

function Export-iOSApps {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Applications\iOS' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
        -FilterScript { $_.'@odata.type' -match '^#microsoft\.graph\.(ios|iOS)' } `
        -RelatedCollections @('assignments') -Label 'iOS Apps'
}

function Export-AndroidApps {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Applications\Android' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
        -FilterScript { $_.'@odata.type' -match '^#microsoft\.graph\.(android|managedAndroid)' } `
        -RelatedCollections @('assignments') -Label 'Android Apps'
}

function Export-macOSApps {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Applications\macOS' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps' `
        -FilterScript { $_.'@odata.type' -match '^#microsoft\.graph\.macOS' } `
        -RelatedCollections @('assignments') -Label 'macOS Apps'
}

function Export-AppProtectionPolicies {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $Uris = @(
        'https://graph.microsoft.com/beta/deviceAppManagement/androidManagedAppProtections',
        'https://graph.microsoft.com/beta/deviceAppManagement/iosManagedAppProtections',
        'https://graph.microsoft.com/beta/deviceAppManagement/windowsManagedAppProtections',
        'https://graph.microsoft.com/beta/deviceAppManagement/mdmWindowsInformationProtectionPolicies'
    )
    $Items = [System.Collections.Generic.List[object]]::new()
    foreach ($Uri in $Uris) {
        foreach ($Item in Get-GraphCollection -Uri $Uri) {
            $Items.Add((Get-GraphObjectWithRelatedData -ObjectUri "$Uri/$($Item.id)" -RelatedCollections @('assignments')))
        }
    }
    Write-Host 'Exporting App Protection Policies...' -ForegroundColor Cyan
    Export-SnapshotObjects -OutputPath (Join-Path $RepositoryRoot 'AppProtectionPolicies') -InputObject $Items.ToArray() `
        -NameScript { param($Item) $Item.displayName }
    Write-Host "Exported $($Items.Count) App Protection Policy object(s)." -ForegroundColor Green
}

function Export-AppConfigurationPolicies {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'AppConfigurationPolicies' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations' `
        -RelatedCollections @('assignments') -Label 'App Configuration Policies'
}

function Export-EnrollmentConfigurations {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'EnrollmentConfigurations' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations' `
        -FilterScript { $_.'@odata.type' -ne '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' } `
        -RelatedCollections @('assignments') -Label 'Enrollment Configurations'
}

function Export-AutopilotProfiles {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'AutopilotProfiles' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles' `
        -RelatedCollections @('assignments') -Label 'Autopilot Profiles'
}

function Export-AutopilotDevices {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'Autopilot\Devices' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities' `
        -NameScript { param($Item) $Item.serialNumber } -Label 'Autopilot Devices'
}

function Export-ESPProfiles {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'EnrollmentStatusPage' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations' `
        -FilterScript { $_.'@odata.type' -eq '#microsoft.graph.windows10EnrollmentCompletionPageConfiguration' } `
        -RelatedCollections @('assignments') -Label 'Enrollment Status Page Profiles'
}

function Export-DeviceCategories {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'DeviceCategories' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/deviceCategories' -Label 'Device Categories'
}

function Export-AssignmentFilters {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'AssignmentFilters' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' -Label 'Assignment Filters'
}

function Export-ScopeTags {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'ScopeTags' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags' -Label 'Scope Tags'
}

function Export-RoleDefinitions {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'RBAC\RoleDefinitions' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/roleDefinitions' -Label 'Role Definitions'
}

function Export-RoleAssignments {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $Items = [System.Collections.Generic.List[object]]::new()
    foreach ($Role in Get-GraphCollection -Uri 'https://graph.microsoft.com/beta/deviceManagement/roleDefinitions') {
        $Uri = "https://graph.microsoft.com/beta/deviceManagement/roleDefinitions/$($Role.id)/roleAssignments"
        foreach ($Assignment in Get-GraphCollection -Uri $Uri) {
            Add-SnapshotProperty -InputObject $Assignment -Name 'roleDefinitionId' -Value $Role.id
            $Items.Add($Assignment)
        }
    }
    Write-Host 'Exporting Role Assignments...' -ForegroundColor Cyan
    Export-SnapshotObjects -OutputPath (Join-Path $RepositoryRoot 'RoleAssignments') -InputObject $Items.ToArray() `
        -NameScript { param($Item) $Item.displayName }
    Write-Host "Exported $($Items.Count) Role Assignment object(s)." -ForegroundColor Green
}

function Export-TermsAndConditions {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    Export-GraphSnapshotCategory -RepositoryRoot $RepositoryRoot -RelativeOutputPath 'TermsAndConditions' `
        -CollectionUri 'https://graph.microsoft.com/beta/deviceManagement/termsAndConditions' `
        -RelatedCollections @('assignments') -Label 'Terms and Conditions'
}

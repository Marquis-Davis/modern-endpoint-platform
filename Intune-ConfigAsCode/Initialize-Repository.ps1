#Requires -RunAsAdministrator

$Root = $PSScriptRoot

if (-not $Root) {
    throw "This script must be saved as Initialize-Repository.ps1 before it can be run."
}

Write-Host ""
Write-Host "Repository Root: $Root" -ForegroundColor Cyan
Write-Host "Creating repository structure..." -ForegroundColor Cyan
Write-Host ""

$Folders = @(
    "Applications",
    "Assignments",
    "CompliancePolicies",
    "ConfigurationProfiles",
    "DriverUpdates",
    "Export",
    "Export\Modules",
    "FeatureUpdates",
    "Filters",
    "Import",
    "Logs",
    "Remediations",
    "Scripts",
    "Security",
    "Security\ASR",
    "Security\BitLocker",
    "Security\Defender",
    "Security\Firewall",
    "Templates"
)

foreach ($Folder in $Folders) {

    $Path = Join-Path -Path $Root -ChildPath $Folder

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Host "[+] Created $Folder" -ForegroundColor Green
    }
    else {
        Write-Host "[=] Exists  $Folder" -ForegroundColor DarkGray
    }
}

$Files = @(
    ".gitignore",
    "README.md",
    "Export\Export-Intune.ps1",
    "Import\Import-Intune.ps1"
)

foreach ($File in $Files) {

    $Path = Join-Path -Path $Root -ChildPath $File

    if (-not (Test-Path $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
        Write-Host "[+] Created $File" -ForegroundColor Yellow
    }
    else {
        Write-Host "[=] Exists  $File" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Repository initialized successfully." -ForegroundColor Green
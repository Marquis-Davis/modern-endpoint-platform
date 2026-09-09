<#
.SYNOPSIS
Installs one or more emergency zero-day Windows updates during ConfigMgr OSD.

.DESCRIPTION
This script is designed to run from the ConfigMgr task sequence package:
    OSD - Zero Day Patches

Package structure:

    ZeroDayPatch
    |
    |-- Install-ZeroDayPatch.ps1
    |
    |-- CVE-2026-81963
    |   |-- 01-KB5043080.msu
    |   `-- 02-KB5124008.msu
    |
    `-- CVE-2026-85880
        `-- 01-KBxxxxxxx.msu

The task sequence variable ZeroDayCVE determines which CVE folder(s)
are installed.

Single CVE:
    ZeroDayCVE = CVE-2026-81963

Multiple CVEs:
    ZeroDayCVE = CVE-2026-81963,CVE-2026-85880

Multiple MSU files inside a CVE folder should be prefixed with
01-, 02-, 03-, etc. to control install order.

The script reads the ZeroDayCVE task sequence variable through
Microsoft.SMS.TSEnvironment, then installs all MSU files found in
each selected CVE folder.

Expected ConfigMgr flow:

    Set Task Sequence Variable
        ZeroDayCVE = CVE-YYYY-NNNNN

    Run PowerShell Script
        Package: OSD - Zero Day Patches
        Script:  Install-ZeroDayPatch.ps1

    Restart Computer

.NOTES
After adding or changing CVE folders or MSU files, update the package
content on the Distribution Points before running OSD.
#>

$TSEnv = New-Object -ComObject Microsoft.SMS.TSEnvironment
$CVEValue = $TSEnv.Value("ZeroDayCVE")

if ([string]::IsNullOrWhiteSpace($CVEValue)) {
    Write-Error "ZeroDayCVE task sequence variable is empty."
    exit 1
}

$CVEs = $CVEValue.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }

Write-Output "ZeroDayCVE value: $CVEValue"
Write-Output "CVE count: $($CVEs.Count)"

foreach ($CVE in $CVEs) {

    $PatchFolder = Join-Path $PSScriptRoot $CVE

    Write-Output "Processing CVE: $CVE"
    Write-Output "Patch folder: $PatchFolder"

    if (-not (Test-Path $PatchFolder)) {
        Write-Error "Patch folder not found: $PatchFolder"
        exit 1
    }

    $Updates = Get-ChildItem -Path $PatchFolder -Filter *.msu |
        Sort-Object Name

    if (-not $Updates) {
        Write-Error "No MSU files found in $PatchFolder"
        exit 1
    }

    foreach ($Update in $Updates) {

        Write-Output "Installing $($Update.Name)"

        $Process = Start-Process `
            -FilePath "wusa.exe" `
            -ArgumentList "`"$($Update.FullName)`" /quiet /norestart" `
            -Wait `
            -PassThru

        Write-Output "$($Update.Name) exit code: $($Process.ExitCode)"

        if ($Process.ExitCode -notin 0, 3010, 2359302) {
            Write-Error "$($Update.Name) failed with exit code $($Process.ExitCode)"
            exit $Process.ExitCode
        }
    }
}

Write-Output "All configured zero-day updates completed successfully."
exit 0
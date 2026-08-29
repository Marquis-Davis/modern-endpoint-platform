param(
    [string]$AppName = "7-Zip -2602",
    [string]$OutputRoot = "C:\APClone"
)

# =========================
# CONFIG
# =========================

$GraphScopes = @(
    "DeviceManagementApps.ReadWrite.All"
)

$GraphBase = "https://graph.microsoft.com/beta"

$PollSeconds = 3
$PollTimeout = 60

# =========================
# FUNCTIONS
# =========================

function Connect-IntuneGraph {

    Import-Module Microsoft.Graph.Authentication

    Connect-MgGraph `
        -Scopes $GraphScopes `
        -NoWelcome
}

function Get-IntuneWin32App {

    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    Write-Host "Finding app: $DisplayName"

    $EscapedName = $DisplayName.Replace("'", "''")

    $Uri = "$GraphBase/deviceAppManagement/mobileApps?`$filter=displayName eq '$EscapedName'"

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri $Uri

    $App = $Response.value |
    Where-Object { $_.'@odata.type' -eq "#microsoft.graph.win32LobApp" } |
    Select-Object -First 1

    if (-not $App) {
        throw "Win32 app not found: $DisplayName"
    }

    Write-Host "Found App ID: $($App.id)"

    return $App
}

function New-AppOutputFolder {

    param(
        [Parameter(Mandatory)]
        [string]$DisplayName
    )

    $SafeName = $DisplayName -replace '[\\/:*?"<>|]', '_'

    $Folder = Join-Path $OutputRoot $SafeName

    New-Item `
        -Path $Folder `
        -ItemType Directory `
        -Force | Out-Null

    return $Folder
}

function Save-AppMetadata {

    param(
        [Parameter(Mandatory)]
        $App,

        [Parameter(Mandatory)]
        [string]$AppFolder
    )

    $Path = Join-Path $AppFolder "AppMetadata.json"

    $App |
    ConvertTo-Json -Depth 30 |
    Out-File `
        -FilePath $Path `
        -Encoding utf8

    Write-Host "Saved app metadata: $Path"
}

function Get-LatestContentVersion {

    param(
        [Parameter(Mandatory)]
        [string]$AppId
    )

    $Uri = "$GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions"

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri $Uri

    $LatestVersion = $Response.value |
    Sort-Object { [int]$_.id } -Descending |
    Select-Object -First 1

    if (-not $LatestVersion) {
        throw "No content version found."
    }

    Write-Host "Content Version: $($LatestVersion.id)"

    return $LatestVersion
}

function Get-MainContentFile {

    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$ContentVersionId
    )

    $Uri = "$GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions/$ContentVersionId/files"

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri $Uri

    $ContentFile = $Response.value |
    Where-Object { $_.isDependency -ne $true } |
    Select-Object -First 1

    if (-not $ContentFile) {
        throw "No main content file found."
    }

    Write-Host "Content File: $($ContentFile.name)"
    Write-Host "Encrypted Size: $($ContentFile.sizeEncrypted)"

    return $ContentFile
}

function Save-ContentFileMetadata {

    param(
        [Parameter(Mandatory)]
        $ContentFile,

        [Parameter(Mandatory)]
        [string]$AppFolder
    )

    $Path = Join-Path $AppFolder "ContentFileMetadata.json"

    $ContentFile |
    ConvertTo-Json -Depth 30 |
    Out-File `
        -FilePath $Path `
        -Encoding utf8

    Write-Host "Saved content metadata: $Path"
}

function Get-FreshContentFile {

    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$ContentVersionId,

        [Parameter(Mandatory)]
        $ContentFile
    )

    if ($ContentFile.azureStorageUri) {
        Write-Host "Azure Storage URI already available."
        return $ContentFile
    }

    Write-Host "Azure Storage URI missing."
    Write-Host "Requesting URI renewal..."

    $FileUri = "$GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions/$ContentVersionId/files/$($ContentFile.id)"
    $RenewUri = "$FileUri/renewUpload"

    Invoke-MgGraphRequest `
        -Method POST `
        -Uri $RenewUri | Out-Null

    $Elapsed = 0

    do {

        Start-Sleep -Seconds $PollSeconds
        $Elapsed += $PollSeconds

        $ContentFile = Invoke-MgGraphRequest `
            -Method GET `
            -Uri $FileUri

        Write-Host "Upload state: $($ContentFile.uploadState)"

        if ($ContentFile.azureStorageUri) {
            Write-Host "Azure Storage URI received."
            return $ContentFile
        }

    } while ($Elapsed -lt $PollTimeout)

    throw "Azure Storage URI could not be renewed within $PollTimeout seconds."
}

function Save-EncryptedContent {

    param(
        [Parameter(Mandatory)]
        $ContentFile,

        [Parameter(Mandatory)]
        [string]$AppFolder
    )

    if (-not $ContentFile.azureStorageUri) {
        throw "Azure Storage URI is missing."
    }

    $DownloadPath = Join-Path $AppFolder "EncryptedContent.bin"

    Write-Host "Downloading encrypted Intune content..."

    curl.exe `
        -L `
        --fail `
        --output $DownloadPath `
        "$($ContentFile.azureStorageUri)"

    if ($LASTEXITCODE -ne 0) {
        throw "Content download failed. curl exit code: $LASTEXITCODE"
    }

    if (-not (Test-Path $DownloadPath)) {
        throw "Download completed but file was not found."
    }

    $File = Get-Item $DownloadPath

    Write-Host "Downloaded Size: $($File.Length)"

    return $DownloadPath
}

function Export-IntuneContentManifest {

    param(
        [Parameter(Mandatory)]
        $ContentFile,

        [Parameter(Mandatory)]
        [string]$AppFolder
    )

    if (-not $ContentFile.manifest) {
        throw "Content file does not contain a manifest."
    }

    $ManifestPath = Join-Path $AppFolder "ContentManifest.xml"

    try {

        $Bytes = [Convert]::FromBase64String($ContentFile.manifest)

        [System.IO.File]::WriteAllBytes(
            $ManifestPath,
            $Bytes
        )

        Write-Host "Content manifest exported:"
        Write-Host "  $ManifestPath"
    }
    catch {
        throw "Failed to decode Intune content manifest: $($_.Exception.Message)"
    }

    return $ManifestPath
}

function Get-ContentEncryptionInfo {

    param(
        [Parameter(Mandatory)]
        [string]$AppId,

        [Parameter(Mandatory)]
        [string]$ContentVersionId,

        [Parameter(Mandatory)]
        [string]$ContentFileId,

        [Parameter(Mandatory)]
        [string]$AppFolder
    )

    Write-Host "Inspecting content file for encryption information..."

    $Uri = "$GraphBase/deviceAppManagement/mobileApps/$AppId/microsoft.graph.win32LobApp/contentVersions/$ContentVersionId/files/$ContentFileId"

    $Response = Invoke-MgGraphRequest `
        -Method GET `
        -Uri $Uri

    $OutputPath = Join-Path $AppFolder "ContentFileFull.json"

    $Response |
    ConvertTo-Json -Depth 50 |
    Out-File `
        -FilePath $OutputPath `
        -Encoding utf8

    Write-Host "Full content record exported:"
    Write-Host "  $OutputPath"

    $InterestingProperties = @(
        "fileEncryptionInfo",
        "encryptionKey",
        "initializationVector",
        "mac",
        "macKey",
        "fileDigest",
        "fileDigestAlgorithm"
    )

    Write-Host ""
    Write-Host "Encryption property check"
    Write-Host "----------------------------------------"

    foreach ($Property in $InterestingProperties) {

        if ($Response.ContainsKey($Property)) {
            Write-Host "$Property : FOUND"
        }
        else {
            Write-Host "$Property : Not returned"
        }
    }

    return $Response
}

# =========================
# MAIN
# =========================

Connect-IntuneGraph

$App = Get-IntuneWin32App `
    -DisplayName $AppName

$AppFolder = New-AppOutputFolder `
    -DisplayName $AppName

Save-AppMetadata `
    -App $App `
    -AppFolder $AppFolder

$ContentVersion = Get-LatestContentVersion `
    -AppId $App.id

$ContentFile = Get-MainContentFile `
    -AppId $App.id `
    -ContentVersionId $ContentVersion.id

Save-ContentFileMetadata `
    -ContentFile $ContentFile `
    -AppFolder $AppFolder

$ManifestPath = Export-IntuneContentManifest `
    -ContentFile $ContentFile `
    -AppFolder $AppFolder
    
$FullContentRecord = Get-ContentEncryptionInfo `
    -AppId $App.id `
    -ContentVersionId $ContentVersion.id `
    -ContentFileId $ContentFile.id `
    -AppFolder $AppFolder

Write-Host ""
Write-Host "PHASE 1 COMPLETE"
Write-Host "----------------------------------------"
Write-Host "App:      $AppName"
Write-Host "App ID:   $($App.id)"
Write-Host "Manifest: $ManifestPath"

return
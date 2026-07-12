function Update-Win32App {

    [CmdletBinding()]
    param(

        [Parameter(Mandatory)]
        [pscustomobject]$Manifest,

        [Parameter(Mandatory)]
        [string]$ApplicationId
    )

    Write-Host ""
    Write-Host "Updating Win32 Application..." -ForegroundColor Yellow

    #============================================================
    # Build Graph Body
    #============================================================

    $Body = @{

        displayName     = $Manifest.Application.Name
        description     = $Manifest.Application.Description
        publisher       = $Manifest.Application.Publisher
        developer       = $Manifest.Application.Developer
        owner           = $Manifest.Application.Owner

        notes                   = $Manifest.Application.Notes
        informationUrl          = $Manifest.Application.InformationUrl
        privacyInformationUrl   = $Manifest.Application.PrivacyInformationUrl

        displayVersion = $Manifest.Application.Version

        installCommandLine   = $Manifest.Install.Command
        uninstallCommandLine = $Manifest.Uninstall.Command

        allowAvailableUninstall = $Manifest.Deployment.AllowAvailableUninstall
        isFeatured              = $Manifest.Deployment.Featured

        roleScopeTagIds = $Manifest.ScopeTags

    }

    #
    # Remove null / empty values
    #

    $Keys = @($Body.Keys)

    foreach ($Key in $Keys)
    {
        if ($null -eq $Body[$Key])
        {
            $Body.Remove($Key)
            continue
        }

        if ($Body[$Key] -is [string])
        {
            if ([string]::IsNullOrWhiteSpace($Body[$Key]))
            {
                $Body.Remove($Key)
            }
        }
    }

    #
    # Convert to JSON
    #

    $Json = $Body | ConvertTo-Json -Depth 20

    Write-Host ""
    Write-Host "Updating Graph properties..." -ForegroundColor Yellow

    Invoke-MgGraphRequest `
        -Method PATCH `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$ApplicationId" `
        -Body $Json `
        -ContentType "application/json"

    Write-Host ""
    Write-Host "Win32 App updated successfully." -ForegroundColor Green
}
# Connect to Microsoft Graph
Connect-MgGraph `
    -Scopes "User.ReadWrite.All","Directory.ReadWrite.All" `
    -UseDeviceAuthentication

# Stop if authentication failed
$Context = Get-MgContext
if (-not $Context) {
    throw "Failed to authenticate to Microsoft Graph."
}

Write-Host "Connected as $($Context.Account)" -ForegroundColor Green

$Groups = @(
    "SG-HR-Users",
    "SG-Finance-Users",
    "SG-IT-Users",
    "SG-Engineering-Users",
    "SG-Sales-Users",
    "SG-Testing-Users",
    "SG-HelpDesk-Users",
    "SG-Intune-Lab-Users",
    "SG-Intune-Lab-Devices",
    "APP-7Zip-Required",
    "APP-Chrome-Required",
    "APP-VSCode-Required",
    "POL-BitLocker",
    "POL-Defender",
    "POL-WindowsUpdateRing"
)

foreach ($Group in $Groups) {
    New-MgGroup `
        -DisplayName $Group `
        -MailEnabled:$false `
        -MailNickname ($Group -replace '[^a-zA-Z0-9]', '') `
        -SecurityEnabled:$true

    Write-Host "Created $Group"
}

#Verify
# Get-MgGroup -All | Select DisplayName
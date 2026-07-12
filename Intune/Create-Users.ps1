# Install (only needed once)
Install-Module Microsoft.Graph -Scope CurrentUser -Force

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

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

$Domain = ""
$TempPassword = ''

$Users = @(
    @{DisplayName="Alice Smith";   UserName="alice";    Department="HR"}
    @{DisplayName="Bob Johnson";   UserName="bob";      Department="Finance"}
    @{DisplayName="Charlie Brown"; UserName="charlie";  Department="IT"}
    @{DisplayName="David Wilson";  UserName="david";    Department="Engineering"}
    @{DisplayName="Emily Davis";   UserName="emily";    Department="Sales"}
    @{DisplayName="Help Desk";     UserName="helpdesk"; Department="IT"}
    @{DisplayName="Test User";     UserName="testuser"; Department="Testing"}
)

foreach ($User in $Users) {

    $UPN = "$($User.UserName)@$Domain"

    # Skip existing users
    if (Get-MgUser -Filter "userPrincipalName eq '$UPN'" -ErrorAction SilentlyContinue) {
        Write-Host "$UPN already exists." -ForegroundColor Yellow
        continue
    }

    try {

        New-MgUser `
            -DisplayName $User.DisplayName `
            -UserPrincipalName $UPN `
            -MailNickname $User.UserName `
            -AccountEnabled:$true `
            -Department $User.Department `
            -PasswordProfile @{
                Password = $TempPassword
                ForceChangePasswordNextSignIn = $true
            } `
            -ErrorAction Stop

        Write-Host "Created $UPN" -ForegroundColor Green

    }
    catch {
        Write-Host "Failed to create $UPN" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
    }
}

Get-MgUser |
    Where-Object UserPrincipalName -like "*@$Domain" |
    Select-Object DisplayName, UserPrincipalName, Department |
    Format-Table -AutoSize
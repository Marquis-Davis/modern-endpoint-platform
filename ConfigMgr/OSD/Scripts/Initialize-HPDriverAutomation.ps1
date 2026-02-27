# ============================================
# HP DAT / HPCMSL Environment Preparation
# PowerShell 5.1 Compatible
# Run as Administrator
# ============================================

Write-Host "=== Setting TLS 1.2 ==="
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Paths to check
$paths = @(
"C:\Program Files\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1",
"C:\Program Files (x86)\WindowsPowerShell\Modules\PowerShellGet\1.0.0.1"
)

foreach ($path in $paths) {
if (Test-Path $path) {
Write-Host "Removing legacy PowerShellGet from $path"
Remove-Item $path -Recurse -Force
}
}

# Reload PowerShellGet 2.2.5
Import-Module PowerShellGet -MinimumVersion 2.2.5 -Force

# Ensure NuGet provider
if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
Install-PackageProvider -Name NuGet -Force -Scope AllUsers
}

# Trust PSGallery
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Remove old HPCMSL versions if present
if (Get-Module -ListAvailable HPCMSL) {
Uninstall-Module HPCMSL -AllVersions -Force -ErrorAction SilentlyContinue
}

# Install clean
Install-Module HPCMSL -Scope AllUsers -Force -AcceptLicense

Import-Module HPCMSL -Force

if (Get-Command New-HPDriverPack -ErrorAction SilentlyContinue) {
Write-Host "SUCCESS: HP Softpaq ready." -ForegroundColor Green
} else {
Write-Host "ERROR: HP Softpaq not available." -ForegroundColor Red
}

Write-Host "=== Setup Complete ==="
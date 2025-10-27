#Requires -RunAsAdministrator
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check if module is already installed
$installed = Get-PSResource -Name PSWindowsUpdate -ErrorAction SilentlyContinue
if ($null -eq $installed) {
    Write-Host "Installing PSWindowsUpdate..."
    Install-PSResource PSWindowsUpdate -AcceptLicense -Scope AllUsers -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
} else {
    Write-Host "Updating PSWindowsUpdate..."
    Update-PSResource PSWindowsUpdate -Scope AllUsers -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
}
Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
# Install all available updates silently
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction Stop

# Reboot automatically if required
if (Get-WURebootStatus -Silent) {
    Write-Host "**REboot-Required**"
    Sleep 30
    Write-Host "REbooting...."
    Sleep 3
    Restart-Computer -Force
} else {
    Write-Host "This machine is FULLY updated"
}

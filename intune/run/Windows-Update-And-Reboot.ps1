[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check if module is already installed
$installed = Get-PSResource -Name PSWindowsUpdate -ErrorAction SilentlyContinue
if ($null -eq $installed) {
    Write-Host "Module '$ModuleName' not found. Installing..." -ForegroundColor Green
    Install-PSResource PSWindowsUpdate
} else {
    Write-Host "Module '$ModuleName' found. Updating..." -ForegroundColor Cyan
    Update-PSResource PSWindowsUpdate
}
Import-Module PSWindowsUpdate -Force
# Install all available updates silently
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot

# Reboot automatically if required
if (Get-WURebootStatus) {
    Write-Host "**REboot-Required**"
    Sleep 30
    Restart-Computer -Force
}

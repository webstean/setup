[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Check if module is already installed
$installed = Get-PSResource -Name PSWindowsUpdate -ErrorAction SilentlyContinue
if ($null -eq $installed) {
    Write-Host "Installing PSWindowsUpdate..."
    Install-PSResource PSWindowsUpdate -ErrorAction SilentlyContinue
} else {
    Write-Host "Updating PSWindowsUpdate..."
    Update-PSResource PSWindowsUpdate -ErrorAction SilentlyContinue
}
Import-Module PSWindowsUpdate -Force -ErrorAction SilentlyContinue
# Install all available updates silently
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction Stop

# Reboot automatically if required
if (Get-WURebootStatus) {
    Write-Host "**REboot-Required**"
    Sleep 30
    Restart-Computer -Force
}

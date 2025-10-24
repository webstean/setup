[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers
}
Import-Module PSWindowsUpdate

# Install all available updates silently
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot

# Reboot automatically if required
if (Get-WURebootStatus) {
    Restart-Computer -Force
}

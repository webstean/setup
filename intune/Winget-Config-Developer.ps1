#Requires -RunAsAdministrator

if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser
}

winget configure developer.winget.yml --accept-configuration-agreements

exit 0

if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
    Import-Module Microsoft.WinGet.Client
}
if (-not (Get-Module -Name Microsoft.WinGet.Configuration)) {
    Import-Module Microsoft.WinGet.Configuration
}

$configSet = Get-WinGetConfiguration -File developer.winget.yml
Invoke-WinGetConfiguration -Set $configSet -AcceptConfigurationAgreements



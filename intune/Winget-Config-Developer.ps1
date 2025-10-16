#Requires -RunAsAdministrator

winget configure validate --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
#winget configure show     --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
winget configure          --file developer.winget --accept-configuration-agreements --suppress-initial-details --ignore-warnings --disable-interactivity --verbose-logs

exit 0

if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser
}
if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
    Import-Module Microsoft.WinGet.Client
}
if (-not (Get-Module -Name Microsoft.WinGet.Configuration)) {
    Import-Module Microsoft.WinGet.Configuration
}

$configSet = Get-WinGetConfiguration -File developer.winget
Invoke-WinGetConfiguration -Set $configSet -AcceptConfigurationAgreements



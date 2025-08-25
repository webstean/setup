#Requires -RunAsAdministrator

if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser
}
if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
    Import-Module Microsoft.WinGet.Client
}

winget configure developer.winget --accept-configuration-agreements --verbose-logs


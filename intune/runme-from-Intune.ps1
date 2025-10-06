#Requires -RunAsAdministrator

## Base URL for raw GitHub content (public`)
$baseUrl = "https://raw.githubusercontent.com/webstean/setup//main/intune"

## List of script files to download and run
$scripts = @(
    "Install-Global-Secure-Access-Client.ps1",
    "Install-Windows-Admin-Centre.ps1",
    "Install-Developer-System.ps1",
    "Install-Developer-PowerShellModules.ps1",
    "Install-Developer-User.ps1",
    "Install-Developer-Fonts.ps1",
    "Config-Normal-Machine.ps1",
    "Winget-Config-Developer.ps1"
)

## List of files to download but NOT execute
$filesToDownloadOnly = @(
    # Example files:
    "developer.winget",
    "wallpaper.jpg",
    "wallpaper.mp4"
    # Add more filenames as needed
)

# Local folder to save downloaded scripts
$scriptFolder = $TranscriptDir

# Download files that should NOT be executed
foreach ($file in $scripts) {
    $url = "$baseUrl/$file"
    $destination = Join-Path -Path $scriptFolder -ChildPath $file
    Write-Host "Downloading (no execute): $file from $url ..."
    Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
}
# Download files that need to be executed
foreach ($file in $filesToDownloadOnly) {
    $url = "$baseUrl/$file"
    $destination = Join-Path -Path $scriptFolder -ChildPath $file
    Write-Host "Downloading (no execute): $file from $url ..."
    Invoke-WebRequest -Uri $url -OutFile $destination -UseBasicParsing
}


Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Output "PowerShell is NOT running in FullLanguage mode. Current mode: $($ExecutionContext.SessionState.LanguageMode)"  
}
Write-Output "Current Powershell Language mode is $($ExecutionContext.SessionState.LanguageMode)"  
Get-ExecutionPolicy -List | Format-Table -AutoSize

# Be aware, if running via Intune, then logs will be created in: "$($env:ProgramData)\Microsoft\IntuneManagementExtension\Logs"

# Local folder to save downloaded scripts
$TranscriptDir  = "$($env:ProgramData)\$($env:USERDOMAIN)\Transcripts"
$TranscriptFile = "$($env:ProgramData)\$($env:USERDOMAIN)\Transcripts\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))"
if (-not (Test-Path "$TranscriptDir")) {
    New-Item -Path "$TranscriptDir" -ItemType Directory | Out-Null
}
## Start again with Transcript File if it over 4MB in size
if (Test-Path "$TranscriptFile") {
    Get-ChildItem -File $TranscriptFile | Where-Object Length -gt 4MB | Clear-Content -Force
}
Start-Transcript -Path $TranscriptFile -Append -Force -IncludeInvocationHeader -ErrorAction SilentlyContinue
## For the transcript: Running in Azure Automation
if ($env:AUTOMATION_ASSET_ACCOUNTID) {
    Write-Output "Running in Azure Automation: $env:AUTOMATION_ASSET_ACCOUNTID"
}
### For the transcript: Get the IP Address(es)
$env:HostIP = (
    Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4DefaultGateway -ne $null -and
        $_.NetAdapter.Status -ne "Disconnected"
    }
).IPv4Address.IPAddress
Write-Output $env:HostIP
## For the transcript: Existing Powerhell versions
$PSVersionTable

$info = Get-ComputerInfo
$info.CSDNSHostName
$info.OsName
$info.OsProductType
$info.OsArchitecture
$info.OsVersion
$info.OsHardwareAbstractionLayer
$info.OsUptime.Hours
$info.OsOrganization
$info.CsManufacturer
$info.CsSystemFamily
$info.Timezone
$info.LogonServer

Write-Output "Retrieving current user information..." 
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Output "Current User is: $currentUser" 
$systemcontext = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
Write-Output "System Context : $systemcontext" 
Write-Output "Env: User Profile: $env:USERPROFILE" 

Write-Host ("Setting PowerShell to UTF-8 output encoding...")
[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# Check if winget is installed
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host "✅ Winget is already installed. Version:" 
    winget --version
} else {
    Write-Host "⚠️ Winget is not installed. Installing..."

    # Winget comes with the "App Installer" package from Microsoft Store
    # Try to install App Installer using winget’s official MSIX package
    $url = "https://aka.ms/getwinget"
    $installerPath = "$env:TEMP\AppInstaller.msixbundle"

    Write-Host "Downloading Winget installer..."
    Invoke-WebRequest -Uri $url -OutFile $installerPath

    Write-Host "Installing Winget..."
    Add-AppxPackage -Path $installerPath

    # Verify installation
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "✅ Winget installed successfully. Version:" 
        winget --version
    } else {
        Write-Host "❌ Winget installation failed. You may need to update Windows or install manually from Microsoft Store."
        exit 1
    }
}
try {
    & "Config-Normal-Machine.ps1",
    & "Install-Global-Secure-Access-Client.ps1",
    & "Install-Windows-Admin-Centre.ps1",
    & "Install-Developer-Fonts.ps1",
    & "Install-Developer-System.ps1", ## installs dotnet, that we need later

    & "Install-Developer-PowerShellModules.ps1",
    & "Install-Developer-User.ps1",
    & "Winget-Config-Developer.ps1"

catch {
    Write-Error "Error executing ${script}: $_"
}
finally {
    # Stop transcript no matter what
    Stop-Transcript
    Write-Host "Transcript stopped."
}
Write-Host "All scripts executed."

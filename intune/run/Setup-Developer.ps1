#Requires -RunAsAdministrator

$elapsed = [System.Diagnostics.Stopwatch]::StartNew()

## Base URL for raw GitHub content (public`)
$baseUrl = "https://raw.githubusercontent.com/webstean/setup//main/intune/"

## List of script files to download and run
$filesToDownload = @(
    "Config-Normal-Machine.ps1",
    "developer.winget",
    "Install-Developer-Fonts.ps1",
    "Install-Developer-PowershellModules.ps1", --file 
    "Install-Developer-System.ps1",
    "Install-Developer-User.ps1",
    "Install-Global-Secure-Access-Client.ps1",
    "Install-Windows-Admin-Centre.ps1",
    "logo.png",
    "wallpaper.jpg"
    # Add more filenames as needed
)

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
## For the transcript: Powershell versions
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
        winget source export
        
    } else {
        Write-Host "❌ Winget installation failed. You may need to update Windows or install manually from Microsoft Store."
        exit 1
    }
}

# Local folder to save downloaded scripts

function New-EmptyTempDirectory {
    [CmdletBinding()]
    param()

    # $env:TEMP gives us the temp folder path
    $basePath = $env:TEMP

    # Use New-Guid (PowerShell 5+) to generate a unique name
    $uniqueName = (New-Guid).Guid
    $fullPath = Join-Path -Path $basePath -ChildPath $uniqueName

    # Ensure it's empty: remove if somehow it already exists
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create the empty directory
    $null = New-Item -ItemType Directory -Path $fullPath -Force

    # Return the path as string
    return $fullPath
}
$destination = New-EmptyTempDirectory

# Download files that should NOT be executed
function Invoke-Download {
    foreach ($file in $filesToDownload) {
        $url = "$baseUrl/$file"
        $filedestination = Join-Path -Path $destination -ChildPath $file
        Write-Output "Downloading (no execute): $url... to $filedestination"
        Invoke-WebRequest -Uri $url -OutFile $filedestination -UseBasicParsing
    }
}

function Invoke-IfFileExists {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Host "EXECUTING: Stated $Path.."
        & $Path
        Write-Host "EXECUTING: Finished $Path.."
    }
    else {
        Write-Host "Failed to execute as script was not found: $Path"
    }
}

function Invoke-WingetConfiguration-Developer {
    #winget configure validate --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
    #winget configure show     --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
    if ( Test-Path "${destination}\developer.winget" ) {
        winget configure --file ${destination}\developer.winget --accept-configuration-agreements --suppress-initial-details --disable-interactivity --verbose-logs
    } else {
        Write-Host "${destination}\developer.winget not found!!"
        Read-Host "Press Enter to continue..."
    }
    return ;
    ## get-childitem     $env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir\
    #if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    #Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser
    #}
    #if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
    #Import-Module Microsoft.WinGet.Client
    #}
    #if (-not (Get-Module -Name Microsoft.WinGet.Configuration)) {
    #Import-Module Microsoft.WinGet.Configuration
    #}
    #$configSet = Get-WinGetConfiguration -File developer.winget
    #Invoke-WinGetConfiguration -Set $configSet -AcceptConfigurationAgreements
}

## Execute downloaded scripts
try {
    Write-Host "******************= Scripts to EXECUTE =******************************"
    Invoke-Download
    If ( Test-Path "$destination\wallpaper.jpg" ) {
        Copy-Item "$destination\wallpaper.jpg" "$env:ALLUSERSPROFILE\default-wallpaper.jpg" -Force -ErrorAction SilentlyContinue
    }
    If ( Test-Path "$destination\logo.png" ) {
        Copy-Item "$destination\logo.png" "$env:ALLUSERSPROFILE\logo.png" -Force -ErrorAction SilentlyContinue
    }
   
    ### Normal Machine ###
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Config-Normal-Machine.ps1"
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."

    if ($env:IsDevBox -eq "True") {
        Write-Host "*** This is a DevBox ***"
    }

    ### DEVELOPER Machine ###
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WingetConfiguration-Developer
    $csw.Stop()
    Write-Host "⏳ winget configuration completed in $($csw.Elapsed.Minutes) minutes."

    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Developer-PowerShellModules.ps1"
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Global-Secure-Access-Client.ps1"
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Windows-Admin-Centre.ps1"
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Developer-Fonts.ps1" ## need ZIP from PowerShell modules
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Developer-System.ps1" ## installs dotnet, that we need later
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Install-Developer-User.ps1"
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."

    Write-Host "******************= All scripts executed =******************************"
    $elapsed.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
}
catch {
    Write-Error "Error executing: $_"
}
finally {
    # Stop transcript no matter what
    Stop-Transcript
    Write-Host "Transcript stopped."
    Write-Host "COMPLETED."
}
return $true


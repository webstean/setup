#Requires -RunAsAdministrator

## Current Statue: Global Secure Access Client (windows)
## ==> IPv4 is preferred and it suggested you disabled IPv6 is you have issues: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#ipv4-preferred
## ==> DNS over HTTP not supported: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#dns-over-https-not-supported
## ==> QUIC is not supported for Internet Access, but is supproted for Private Access and Microsoft 365 workloads.
## These change won't be fully effective until after reboot.
function CreateIfNotExists {
	param($Path)
	if (-NOT (Test-Path $Path)) {
		New-Item -Path $Path -Force | Out-Null
	}
}

function Ensure-RegistryValue {
    param(
        [Parameter(Mandatory)] [ValidateSet('HKLM','HKCU')] [string] $Hive,
        [Parameter(Mandatory)] [string] $SubKey,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [object] $Value,
        [ValidateSet('STRING','DWORD','QWORD','BINARY','MULTISTRING','EXPANDSTRING')]
        [string] $Type = 'String'
    )
    $path = "$Hive`:\$SubKey"
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        return [pscustomobject]@{ Path=$path; Name=$Name; Value=$Value; Type=$Type; Status='OK' }
    } catch {
        return [pscustomobject]@{ Path=$path; Name=$Name; Error=$_.Exception.Message; Status='FAILED' }
    }
}
## Example:
#Ensure-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso\MyApp' -Name 'ServerUrl' -Value 'https://example.local' -Type 'String'

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

Write-Output ("Configuring...")
function PreferIPv4 {
	## Prefer IPv4 over IPv6 with 0x20, disable  IPv6 with 0xff, revert to default with 0x00.
	$setting = 0x20
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value $setting
}
function UnbindIPv6 {
	# More radical - typically not neccessary
	Get-NetAdapterBinding | Where-Object ComponentID -eq 'ms_tcpip6' | ForEach-Object {
		Disable-NetAdapterBinding -Name $_.Name -ComponentID 'ms_tcpip6'
	}
}
function DisableInbuiltDNS {
	$disableBuiltInDNS = 0x00
	## Disabled Inbuilt DNS for the Microsoft Edge
	CreateIfNotExists "HKLM:\SOFTWARE\Policies\Microsoft"
	CreateIfNotExists "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DnsOverHttpsMode" -Value "off"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BuiltInDnsClientEnabled" -Type DWord -Value $disableBuiltInDNS
	## Disabled Inbuilt DNS for the Google Chrome
	CreateIfNotExists "HKLM:\SOFTWARE\Policies\Google"
	CreateIfNotExists "HKLM:\SOFTWARE\Policies\Google\Chrome"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "DnsOverHttpsMode" -Value "off"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "BuiltInDnsClientEnabled" -Type DWord -Value $disableBuiltInDNS
}
function DisableQUIC {
	## QUIC is currently supported WITH Private Access and Microsoft 365 workloads but NOT in Internet Access
	$disableQUIC = 0x00
	##$enableQUIC = 0x01
	## Disable QUIC protocol in Microsoft Edge
	Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Edge" -Name "QuicAllowed" -Value $disableQUIC -Type DWord -Force
	## Disable QUIC protocol in Google Chrome
	Set-ItemProperty -Path "HKLM:\Software\Policies\Google\Chrome"  -Name "QuicAllowed" -Value $disableQUIC -Type DWord -Force
}
## Configure for MAXIMUM compatibility with Microsoft Global Secure Access and other similar (Cisco Umbrella etc..)
PreferIPv4
# UnbindIPv6
DisableInbuiltDNS
DisableQUIC

# WANT MORE OPTIONS, see: https://github.com/petrak-dan/Win11-Initial-Setup-Script/blob/main/Win10.psm1
# Disable News and Interests feed in Taskbar
Function DisableNewsAndInterests {
	If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 0
}
DisableNewsAndInterests

function Disable-MsnFeedsAndWidgets {
	Write-Host "`n🔧 Disabling MSN Feeds, Widgets, and Search Highlights..."

	# 1. Disable Widgets in Taskbar via system policy
	try {
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
		New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -PropertyType DWord -Value 0 -Force | Out-Null
		Write-Host "✅ Widgets disabled via policy (HKLM)."
	}
 	catch {
		Write-Warning "❌ Failed to set system-wide widget policy: $_"
	}

	# 2. Disable Widgets for current user
	try {
		## Need extra permissions
		Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
		Write-Host "✅ Taskbar widgets disabled for current user."
	}
 	catch {
		Write-Warning "❌ Failed to disable taskbar widgets: $_"
	}

	# 3. Disable Search Highlights
	try {
		$searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
		New-Item -Path $searchKey -Force | Out-Null
		New-ItemProperty -Path $searchKey -Name "IsDynamicSearchBoxEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
		New-ItemProperty -Path $searchKey -Name "IsDynamicSearchBoxEnabledOnTablet" -Value 0 -PropertyType DWord -Force | Out-Null
		Write-Host "✅ Search highlights disabled."
	}
 	catch {
		Write-Warning "❌ Failed to configure search highlights: $_"
	}

	# 4. Disable personalized feeds content (need more permissions)
	try {
		$feedsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
		New-Item -Path $feedsKey -Force -ErrorAction SilentlyContinue | Out-Null
		## Need permissions
		New-ItemProperty -Path $feedsKey -Name "ShellFeedsTaskbarViewMode" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
		Write-Host "✅ Personalized content in feeds disabled."
	}
 	catch {
		Write-Warning "❌ Failed to disable feeds view: $_"
	}
}
Disable-MsnFeedsAndWidgets


# Enable location feature and scripting for the location feature (This does NOT work on Windows 11)
Function EnableLocation {
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -ErrorAction SilentlyContinue
}
EnableLocation

# Disable Feedback
Function DisableFeedback {
	If (!(Test-Path "HKCU:\Software\Microsoft\Siuf\Rules")) {
		New-Item -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1
	Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClient" -ErrorAction SilentlyContinue | Out-Null
	Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" -ErrorAction SilentlyContinue | Out-Null
}
DisableFeedback

# Disable Error reporting
Function DisableErrorReporting {
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1
	Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" | Out-Null
}
DisableErrorReporting

# Disable System Recovery and Factory reset
# Warning: This tweak completely removes the option to enter the system recovery during boot and the possibility to perform a factory reset
Function DisableRecoveryAndReset {
	reagentc /disable 2>&1 | Out-Null
}
DisableRecoveryAndReset ## this does NOT work with Intune enrolled Autopilot devices anyway

# Disable Autoplay
Function DisableAutoplay {
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Type DWord -Value 1
	Ensure-RegistryValue -Hive HKCU -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value '1' -Type 'DWORD'
}
DisableAutoplay

# Disable Autorun for all drives
Function DisableAutorun {
	If (!(Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
		New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Type DWord -Value 255
}
DisableAutorun

# Enable NTFS paths with length over 260 characters
Function EnableNTFSLongPaths {
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWord -Value 1
}
EnableNTFSLongPaths

# Disable updating of NTFS last access timestamps
Function DisableNTFSLastAccess {
	# User Managed, Last Access Updates Disabled
	fsutil behavior set DisableLastAccess 1 | Out-Null
}
DisableNTFSLastAccess

# Enable automatic reboot on crash (BSOD)
Function EnableAutoRebootOnCrash {
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "AutoReboot" -Type DWord -Value 1
}
EnableAutoRebootOnCrash

# Show network options on lock screen
Function ShowNetworkOnLockScreen {
	Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DontDisplayNetworkSelectionUI" -ErrorAction SilentlyContinue
}
ShowNetworkOnLockScreen

# Disable accessibility keys prompts (Sticky keys, Toggle keys, Filter keys)
Function DisableAccessibilityKeys {
	Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Type String -Value "506"
	Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Type String -Value "58"
	Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Type String -Value "122"
}

Write-Output ("Configuring Sounds...")
# Set sound scheme to No Sounds
Function SetSoundSchemeNone {
	$SoundScheme = ".None"
	Get-ChildItem -Path "HKCU:\AppEvents\Schemes\Apps\*\*" | ForEach-Object {
		# If scheme keys do not exist in an event, create empty ones (similar behavior to Sound control panel).
		If (!(Test-Path "$($_.PsPath)\$($SoundScheme)")) {
			New-Item -Path "$($_.PsPath)\$($SoundScheme)" | Out-Null
		}
		If (!(Test-Path "$($_.PsPath)\.Current")) {
			New-Item -Path "$($_.PsPath)\.Current" | Out-Null
		}
		# Get a regular string from any possible kind of value, i.e. resolve REG_EXPAND_SZ, copy REG_SZ or empty from non-existing.
		$Data = (Get-ItemProperty -Path "$($_.PsPath)\$($SoundScheme)" -Name "(Default)" -ErrorAction SilentlyContinue)."(Default)"
		# Replace any kind of value with a regular string (similar behavior to Sound control panel).
		Set-ItemProperty -Path "$($_.PsPath)\$($SoundScheme)" -Name "(Default)" -Type String -Value $Data
		# Copy data from source scheme to current.
		Set-ItemProperty -Path "$($_.PsPath)\.Current" -Name "(Default)" -Type String -Value $Data
	}
	Set-ItemProperty -Path "HKCU:\AppEvents\Schemes" -Name "(Default)" -Type String -Value $SoundScheme
}
SetSoundSchemeNone

# Disable playing Windows Startup sound
Function DisableStartupSound {
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Type DWord -Value 1
}
DisableStartupSound

# Disable verbose startup/shutdown status messages
Function DisableVerboseStatus {
	If ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
		Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -ErrorAction SilentlyContinue
	}
 Else {
		Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Type DWord -Value 0
	}
}
DisableVerboseStatus

# Disable Sharing Wizard
Function DisableSharingWizard {
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn" -Type DWord -Value 0
}
DisableSharingWizard

# Show This PC shortcut on desktop
Function ShowThisPCOnDesktop {
	If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu")) {
		New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0
	If (!(Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel")) {
		New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0
}
ShowThisPCOnDesktop

# Hide Music icon from Explorer namespace - Hides the icon also from personal folders and open/save dialogs
Function HideMusicFromExplorer {
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{a0c69a99-21c8-4671-8703-7934162fcf1d}\PropertyBag" -Name "ThisPCPolicy" -Type String -Value "Hide"
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\{a0c69a99-21c8-4671-8703-7934162fcf1d}\PropertyBag" -Name "ThisPCPolicy" -Type String -Value "Hide"
}
HideMusicFromExplorer

# Disable Internet Explorer warning when closing multiple tabs.
Function DisableIEandEdgeWarnings {
	If (!(Test-Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing")) {
		New-Item -Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing" -Name "WarnOnClose" -Type DWord -Value 0
	if (!(Test-Path "HKCU:\Software\Policies\Microsoft\Edge")) {
		New-Item -Path "HKCU:\Software\Policies\Microsoft\Edge" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "RestoreOnStartup" -Type DWord -Value 1
}
DisableIEandEdgeWarnings

# Disable Windows Media Player's media sharing feature
Function DisableMediaSharing {
	If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer")) {
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Name "PreventLibrarySharing" -Type DWord -Value 1
}
DisableMediaSharing

# Uninstall Windows Media Player (use VLC instead)
Write-Output ("Installing DotNet 2, 3 and 3.5 for compatability...")
# Install .NET Framework 2.0, 3.0 and 3.5 runtimes - Requires internet connection
Function InstallNET23 {
	If ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
		Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "NetFx3" } | Enable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	}
 Else {
		Install-WindowsFeature -Name "NET-Framework-Core" -WarningAction SilentlyContinue | Out-Null
	}
}
InstallNET23

# Uninstall Internet Explorer (not applicable on later Windows 10/11 builds)
Function UninstallInternetExplorer {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -like "Internet-Explorer-Optional*" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Browser.InternetExplorer*" } | Remove-WindowsCapability -Online | Out-Null
}
UninstallInternetExplorer

Write-Output ("Uninstalling Windows System bloat...")
# Uninstall Work Folders Client - never used 
Function UninstallWorkFolders {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "WorkFolders-Client" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
}
UninstallWorkFolders

# Uninstall PowerShell Integrated Scripting Environment - Applicable since 2004
# Note: Also removes built-in graphical methods like Out-GridView
Function UninstallPowerShellISE {
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Microsoft.Windows.PowerShell.ISE*" } | Remove-WindowsCapability -Online | Out-Null
}
##UninstallPowerShellISE

# Uninstall Microsoft XPS Document Writer
Function UninstallXPSPrinter {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "Printing-XPSServices-Features" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
}
UninstallXPSPrinter

# Remove Default Fax Printer
Function RemoveFaxPrinter {
	Remove-Printer -Name "Fax" -ErrorAction SilentlyContinue
}
RemoveFaxPrinter

# Uninstall Windows Fax and Scan Services
Function UninstallFaxAndScan {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "FaxServicesClientPackage" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Print.Fax.Scan*" } | Remove-WindowsCapability -Online | Out-Null
}
UninstallFaxAndScan

# Hide Server Manager after login (applicable to Servers only)
Function HideServerManagerOnLogin {
	If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager")) {
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager" -Name "DoNotOpenAtLogon" -Type DWord -Value 1
}
HideServerManagerOnLogin

# Disable Shutdown Event Tracker (applicable to Servers only)
Function DisableShutdownTracker {
	If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability")) {
		New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" -Force | Out-Null
	}
	Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability" -Name "ShutdownReasonOn" -Type DWord -Value 0
}
DisableShutdownTracker

# Disable Internet Explorer Enhanced Security Configuration (IE ESC) (applicable to Servers only)
Function DisableIEEnhancedSecurity {
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}") {
		Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Type DWord -Value 0
	}
	if (Test-Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}") {
		Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Type DWord -Value 0
	}
}
DisableIEEnhancedSecurity

Write-Output ("Uninstalling Microsoft Software Bloat...")

function Uninstall-AppxPackageAndWait {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName
    )

    # Get the package for all users
    $package = Get-AppxPackage $PackageName -AllUsers

    if (-not $package) {
        Write-Host "Package '$PackageName' is not installed."
        return
    }

    Write-Host "Uninstalling '$PackageName' for all users..."
    Remove-AppxPackage -Package $package.PackageFullName -AllUsers

    # Wait for the package to be fully uninstalled
    do {
        Start-Sleep -Seconds 2
        $stillInstalled = Get-AppxPackage $PackageName -AllUsers
    } while ($stillInstalled)

    Write-Host "Package '$PackageName' has been successfully uninstalled."
}

# Uninstall default Microsoft applications
Function UninstallMsftBloat {
	## Import-Module Appx
	Uninstall-AppxPackageAndWait "Microsoft.GamingApp"
	Uninstall-AppxPackageAndWait "Microsoft.XboxIdentityProvider"
	Uninstall-AppxPackageAndWait "Microsoft.Xbox.TCUI"
	Uninstall-AppxPackageAndWait "Microsoft.Windows.DevHome"  
	Uninstall-AppxPackageAndWait "Clipchamp.Clipchamp"
	Uninstall-AppxPackageAndWait "Microsoft.3DBuilder"
	Uninstall-AppxPackageAndWait "Microsoft.AppConnector"
	Uninstall-AppxPackageAndWait "Microsoft.BingFinance"
	Uninstall-AppxPackageAndWait "Microsoft.BingFoodAndDrink"
	Uninstall-AppxPackageAndWait "Microsoft.BingHealthAndFitness"
	Uninstall-AppxPackageAndWait "Microsoft.BingMaps"
	Uninstall-AppxPackageAndWait "Microsoft.BingNews"
	Uninstall-AppxPackageAndWait "Microsoft.BingSports"
	Uninstall-AppxPackageAndWait "Microsoft.BingTranslator"
	Uninstall-AppxPackageAndWait "Microsoft.BingTravel"
	Uninstall-AppxPackageAndWait "Microsoft.BingWeather"
	Uninstall-AppxPackageAndWait "Microsoft.CommsPhone"
	Uninstall-AppxPackageAndWait "Microsoft.ConnectivityStore"
	Uninstall-AppxPackageAndWait "Microsoft.FreshPaint"
	Uninstall-AppxPackageAndWait "Microsoft.GetHelp"
	Uninstall-AppxPackageAndWait "Microsoft.Getstarted"
	Uninstall-AppxPackageAndWait "Microsoft.HelpAndTips"
	Uninstall-AppxPackageAndWait "Microsoft.Media.PlayReadyClient.2"
	Uninstall-AppxPackageAndWait "Microsoft.Messaging"
	Uninstall-AppxPackageAndWait "Microsoft.Microsoft3DViewer"
	Uninstall-AppxPackageAndWait "Microsoft.MicrosoftOfficeHub"
	Uninstall-AppxPackageAndWait "Microsoft.MicrosoftPowerBIForWindows"
	Uninstall-AppxPackageAndWait "Microsoft.MicrosoftSolitaireCollection"
	Uninstall-AppxPackageAndWait "Microsoft.MicrosoftStickyNotes"
	Uninstall-AppxPackageAndWait "Microsoft.MinecraftUWP"
	Uninstall-AppxPackageAndWait "Microsoft.MixedReality.Portal"
	Uninstall-AppxPackageAndWait "Microsoft.MoCamera"
	Uninstall-AppxPackageAndWait "Microsoft.MSPaint"
	Uninstall-AppxPackageAndWait "Microsoft.NetworkSpeedTest"
	Uninstall-AppxPackageAndWait "Microsoft.OfficeLens"
	Uninstall-AppxPackageAndWait "Microsoft.Office.OneNote"
	Uninstall-AppxPackageAndWait "Microsoft.Office.Sway"
	Uninstall-AppxPackageAndWait "Microsoft.OneConnect"
	Uninstall-AppxPackageAndWait "Microsoft.People"
	Uninstall-AppxPackageAndWait "Microsoft.Print3D"
	Uninstall-AppxPackageAndWait "Microsoft.Reader"
	Uninstall-AppxPackageAndWait "Microsoft.RemoteDesktop"
	Uninstall-AppxPackageAndWait "Microsoft.SkypeApp"
	Uninstall-AppxPackageAndWait "Microsoft.Todos"
	Uninstall-AppxPackageAndWait "Microsoft.Wallet"
	Uninstall-AppxPackageAndWait "Microsoft.WebMediaExtensions"
	Uninstall-AppxPackageAndWait "Microsoft.Whiteboard"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsAlarms"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsCamera"
	Uninstall-AppxPackageAndWait "microsoft.windowscommunicationsapps"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsFeedbackHub"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsMaps"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsPhone"
	Uninstall-AppxPackageAndWait "Microsoft.Windows.Photos"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsReadingList"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsScan"
	Uninstall-AppxPackageAndWait "Microsoft.WindowsSoundRecorder"
	Uninstall-AppxPackageAndWait "Microsoft.WinJS.1.0"
	Uninstall-AppxPackageAndWait "Microsoft.WinJS.2.0"
	Uninstall-AppxPackageAndWait "Microsoft.YourPhone"
	Uninstall-AppxPackageAndWait "Microsoft.ZuneMusic"
	Uninstall-AppxPackageAndWait "Microsoft.ZuneVideo"
	Uninstall-AppxPackageAndWait "Microsoft.Advertising.Xaml" # Dependency for microsoft.windowscommunicationsapps, Microsoft.BingWeather
}
UninstallMsftBloat

# Uninstall default third party applications
function UninstallThirdPartyBloat {
	Write-Output ("Uninstalling 3rd Party Software Bloat...")
	## Import-Module Appx
	Uninstall-AppxPackageAndWait "2414FC7A.Viber"
	Uninstall-AppxPackageAndWait "41038Axilesoft.ACGMediaPlayer"
	Uninstall-AppxPackageAndWait "46928bounde.EclipseManager"
	Uninstall-AppxPackageAndWait "4DF9E0F8.Netflix"
	Uninstall-AppxPackageAndWait "64885BlueEdge.OneCalendar"
	Uninstall-AppxPackageAndWait "7EE7776C.LinkedInforWindows"
	Uninstall-AppxPackageAndWait "828B5831.HiddenCityMysteryofShadows"
	Uninstall-AppxPackageAndWait "89006A2E.AutodeskSketchBook"
	Uninstall-AppxPackageAndWait "9E2F88E3.Twitter"
	Uninstall-AppxPackageAndWait "A278AB0D.DisneyMagicKingdoms"
	Uninstall-AppxPackageAndWait "A278AB0D.DragonManiaLegends"
	Uninstall-AppxPackageAndWait "A278AB0D.MarchofEmpires"
	Uninstall-AppxPackageAndWait "ActiproSoftwareLLC.562882FEEB491"
	Uninstall-AppxPackageAndWait "AD2F1837.GettingStartedwithWindows8"
	Uninstall-AppxPackageAndWait "AD2F1837.HPJumpStart"
	Uninstall-AppxPackageAndWait "AD2F1837.HPRegistration"
	Uninstall-AppxPackageAndWait "AdobeSystemsIncorporated.AdobePhotoshopExpress"
	Uninstall-AppxPackageAndWait "Amazon.com.Amazon"
	Uninstall-AppxPackageAndWait "C27EB4BA.DropboxOEM"
	Uninstall-AppxPackageAndWait "CAF9E577.Plex"
	Uninstall-AppxPackageAndWait "CyberLinkCorp.hs.PowerMediaPlayer14forHPConsumerPC"
	Uninstall-AppxPackageAndWait "D52A8D61.FarmVille2CountryEscape"
	Uninstall-AppxPackageAndWait "D5EA27B7.Duolingo-LearnLanguagesforFree"
	Uninstall-AppxPackageAndWait "DB6EA5DB.CyberLinkMediaSuiteEssentials"
	Uninstall-AppxPackageAndWait "DolbyLaboratories.DolbyAccess"
	Uninstall-AppxPackageAndWait "Drawboard.DrawboardPDF"
	Uninstall-AppxPackageAndWait "Facebook.Facebook"
	Uninstall-AppxPackageAndWait "Fitbit.FitbitCoach"
	Uninstall-AppxPackageAndWait "flaregamesGmbH.RoyalRevolt2"
	Uninstall-AppxPackageAndWait "GAMELOFTSA.Asphalt8Airborne"
	Uninstall-AppxPackageAndWait "KeeperSecurityInc.Keeper"
	Uninstall-AppxPackageAndWait "king.com.BubbleWitch3Saga"
	Uninstall-AppxPackageAndWait "king.com.CandyCrushFriends"
	Uninstall-AppxPackageAndWait "king.com.CandyCrushSaga"
	Uninstall-AppxPackageAndWait "king.com.CandyCrushSodaSaga"
	Uninstall-AppxPackageAndWait "king.com.FarmHeroesSaga"
	Uninstall-AppxPackageAndWait "Nordcurrent.CookingFever"
	Uninstall-AppxPackageAndWait "PandoraMediaInc.29680B314EFC2"
	Uninstall-AppxPackageAndWait "PricelinePartnerNetwork.Booking.comBigsavingsonhot"
	Uninstall-AppxPackageAndWait "SpotifyAB.SpotifyMusic"
	Uninstall-AppxPackageAndWait "ThumbmunkeysLtd.PhototasticCollage"
	Uninstall-AppxPackageAndWait "WinZipComputing.WinZipUniversal"
	Uninstall-AppxPackageAndWait "XINGAG.XING"
}
UninstallThirdPartyBloat

function Disable-WindowsGaming {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    # ----- Helpers ------------------------------------------------------------
    function Ensure-Key {
        param([Parameter(Mandatory)][string]$Path)
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    }

    function Set-Dword {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][int]$Value
        )
        Ensure-Key -Path $Path
        New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    }

    $summary = [ordered]@{
        GameBarProcessesStopped = $false
        GameDVREnforcedPolicy   = $false
        GameDVREnabledHKCU      = $false
        GameConfigDvrDisabled   = $false
        GameBarUiDisabled       = $false
        GameModeAutoDisabled    = $false
        RunEntriesRemoved       = @()
        ServicesDisabled        = @()
        TasksDisabled           = @()
        Notes                   = @()
    }

    Write-Verbose "Stopping Game Bar processes if running..."
    try {
        Get-Process -Name XboxGameBar, GameBar, GameBarFT -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $summary.GameBarProcessesStopped = $true
    } catch { $summary.Notes += "Could not stop Game Bar processes: $($_.Exception.Message)" }

    # ---- Disable Game DVR/Captures (policy + per-user)
    if ($PSCmdlet.ShouldProcess("Policy HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR","Disable Game DVR")) {
        try {
            Set-Dword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
            $summary.GameDVREnforcedPolicy = $true
        } catch { $summary.Notes += "Policy write failed: $($_.Exception.Message)" }
    }

    if ($PSCmdlet.ShouldProcess("HKCU GameDVR","Disable AppCaptureEnabled")) {
        try {
            Set-Dword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
            $summary.GameDVREnabledHKCU = $true
        } catch { $summary.Notes += "HKCU GameDVR write failed: $($_.Exception.Message)" }
    }

    if ($PSCmdlet.ShouldProcess("HKCU GameConfigStore","Disable GameDVR_Enabled")) {
        try {
            Set-Dword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
            $summary.GameConfigDvrDisabled = $true
        } catch { $summary.Notes += "HKCU GameConfigStore write failed: $($_.Exception.Message)" }
    }

    # ---- Disable Game Bar UI, tips, hotkey; Disable Game Mode auto
    if ($PSCmdlet.ShouldProcess("HKCU GameBar","Disable Game Bar UI and Game Mode auto")) {
        try {
            $hkcuBar = 'HKCU:\Software\Microsoft\GameBar'
            Set-Dword -Path $hkcuBar -Name 'ShowStartupPanel' -Value 0
            Set-Dword -Path $hkcuBar -Name 'UseNexusForGameBarEnabled' -Value 0
            Set-Dword -Path $hkcuBar -Name 'OpenGameBar' -Value 0
            Set-Dword -Path $hkcuBar -Name 'AutoGameModeEnabled' -Value 0
            $summary.GameBarUiDisabled = $true
            $summary.GameModeAutoDisabled = $true
        } catch { $summary.Notes += "GameBar settings write failed: $($_.Exception.Message)" }
    }

    # ---- Remove common auto-start entries (per-user)
    if ($PSCmdlet.ShouldProcess("HKCU Run entries","Remove Xbox/GameBar autostart")) {
        $runCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        foreach ($name in 'XboxGameBar','GameBar') {
            try {
                if (Get-ItemProperty -Path $runCU -Name $name -ErrorAction SilentlyContinue) {
                    Remove-ItemProperty -Path $runCU -Name $name -Force -ErrorAction SilentlyContinue
                    $summary.RunEntriesRemoved += $name
                }
            } catch { $summary.Notes += "Failed removing Run entry ${name}: $($_.Exception.Message)" }
        }
    }

    # ---- Disable Xbox-related services
    if ($PSCmdlet.ShouldProcess("Xbox services","Stop and disable")) {
        $svcNames = 'XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc'
        foreach ($svc in $svcNames) {
            $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
            if ($s) {
                try {
                    if ($s.Status -ne 'Stopped') { Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue }
                    Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                    $summary.ServicesDisabled += $svc
                } catch { $summary.Notes += "Service $svc change failed: $($_.Exception.Message)" }
            }
        }
    }

    # ---- Disable scheduled tasks
    if ($PSCmdlet.ShouldProcess("Scheduled tasks","Disable Xbox Game Save tasks")) {
        $taskItems = @(
            @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTask' },
            @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTaskLogon' }
        )
        foreach ($t in $taskItems) {
            try {
                $st = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
                if ($st) {
                    Disable-ScheduledTask -TaskPath $t.Path -TaskName $t.Name | Out-Null
                    $summary.TasksDisabled += ($t.Path + $t.Name)
                }
            } catch { $summary.Notes += "Task disable failed for $($t.Path)$($t.Name): $($_.Exception.Message)" }
        }
    }

    # ---- Optional light-touch on package (do not remove system app)
    # Attempt to keep overlay from re-registering background tasks; harmless if unsupported.
    if ($PSCmdlet.ShouldProcess("XboxGamingOverlay package","Re-register manifest to block background tasks (best-effort)")) {
        try {
            Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay' -AllUsers -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue | Out-Null
                    } catch {}
                }
        } catch { $summary.Notes += "Overlay package handling skipped: $($_.Exception.Message)" }
    }

    Write-Verbose "Done. Some changes apply after sign-out or Explorer restart."
    [pscustomobject]$summary
}
Disable-WindowsGaming

function Set-SettingsPageVisibility {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Hide','ShowOnly')]
        [string]$Mode,

        [string[]]$Pages,

        [switch]$Add,
        [switch]$Remove,
        [switch]$Clear,
        [switch]$Get
    )

    # Registry target
    $KeyPath   = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $ValueName = 'SettingsPageVisibility'

    # --- Admin check for HKLM writes
    $needsWrite = -not $Get
    if ($needsWrite -and -not $Clear -and -not $Remove -and -not $Add -and -not $Mode) {
        throw "No action specified. Use -Hide/-ShowOnly via -Mode with -Pages, or -Add/-Remove/-Clear/-Get."
    }
    if ($needsWrite -and (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        throw "Run elevated (Administrator) to modify HKLM."
    }

    # Helpers
    function Parse-Value([string]$v){
        if ([string]::IsNullOrWhiteSpace($v)) { return @{ Mode=$null; Pages=@() } }
        $parts = $v.Split(':',2)
        $mode  = $parts[0].Trim().ToLower()
        $pages = @()
        if ($parts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $pages = $parts[1].Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }
        return @{
            Mode  = if ($mode -eq 'hide') {'Hide'} elseif ($mode -eq 'showonly') {'ShowOnly'} else {$null}
            Pages = $pages
        }
    }
    function Build-Value([string]$m,[string[]]$p){
        $p2 = ($p | Where-Object { $_ } | Select-Object -Unique)
        switch ($m) {
            'Hide'     { return ("hide:"     + ($p2 -join ';')) }
            'ShowOnly' { return ("showonly:" + ($p2 -join ';')) }
            default    { throw "Invalid mode '$m' when building value." }
        }
    }

    # Ensure key exists (for writes)
    if (-not (Test-Path $KeyPath)) {
        if ($Get) {
            return [pscustomobject]@{ Mode=$null; Pages=@(); Raw=$null; Path="$KeyPath\$ValueName" }
        }
        New-Item -Path $KeyPath -Force | Out-Null
    }

    # Read current
    $currentRaw = (Get-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    $parsed     = Parse-Value $currentRaw
    $curMode    = $parsed.Mode
    $curPages   = [System.Collections.Generic.List[string]]::new()
    $parsed.Pages | ForEach-Object { [void]$curPages.Add($_) }

    if ($Get) {
        return [pscustomobject]@{
            Mode = $curMode
            Pages = $parsed.Pages
            Raw = $currentRaw
            Path = "$KeyPath\$ValueName"
        }
    }

    # --- Clear
    if ($Clear) {
        if ($PSCmdlet.ShouldProcess("$KeyPath\$ValueName","Remove")) {
            Remove-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
        }
        Write-Verbose "Policy cleared."
        return
    }

    # Normalize supplied pages
    if (($Mode -or $Add -or $Remove) -and $Pages) {
        $Pages = $Pages | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    # --- Overwrite with explicit mode (Hide/ShowOnly)
    if ($Mode -and -not $Add -and -not $Remove) {
        if (-not $Pages -or $Pages.Count -eq 0) { throw "You must supply -Pages when using -Mode (Hide/ShowOnly) to overwrite." }
        $newRaw = Build-Value -m $Mode -p $Pages
        if ($PSCmdlet.ShouldProcess("$KeyPath\$ValueName","Set to '$newRaw'")) {
            New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        }
        return
    }

    # --- Add to existing value (or start a new one with provided Mode)
    if ($Add) {
        if (-not $Pages) { throw "Use -Add with one or more -Pages." }
        $targetMode = $curMode
        if (-not $targetMode) {
            if (-not $Mode) { throw "No existing value. Use -Add together with -Mode Hide/ShowOnly to establish the mode." }
            $targetMode = $Mode
        }
        foreach ($p in $Pages) {
            if (-not ($curPages.Contains($p))) { [void]$curPages.Add($p) }
        }
        $newRaw = Build-Value -m $targetMode -p $curPages
        if ($PSCmdlet.ShouldProcess("$KeyPath\$ValueName","Add -> '$newRaw'")) {
            New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        }
        return
    }

    # --- Remove from existing value
    if ($Remove) {
        if (-not $Pages) { throw "Use -Remove with one or more -Pages." }
        if (-not $curMode) { Write-Verbose "Nothing to remove; value not set."; return }
        $remaining = $curPages | Where-Object { $Pages -notcontains $_ }
        $newRaw = Build-Value -m $curMode -p $remaining
        if ($PSCmdlet.ShouldProcess("$KeyPath\$ValueName","Remove -> '$newRaw'")) {
            New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        }
        return
    }

    throw "No valid action specified. Use one of: -Mode Hide/ShowOnly (with -Pages), -Add, -Remove, -Clear, or -Get."
}
Set-SettingsPageVisibility -Get | Format-List
Set-SettingsPageVisibility -Mode Hide -Pages 'family-group','gaming','windowsinsider-optin','map','maps-downloadmaps','autoplay','network-dialup','network-proxy','delivery-optimization' ## 'gaming-gamebar','gaming-captures','gaming-gamemode','gaming-xboxnetworking'
Set-SettingsPageVisibility -Get | Format-List

# Enable Clipboard History & Sync
function EnableClipboardHistorySync {

	$regPath = "Software\Microsoft\Clipboard"

	# Enable Cloud History
	$propertyName = "EnableClipboardHistory"
	$propertyValue = 1 ## 1 = enabled, 0 = disabled
	Ensure-RegistryValue -Hive HKCU -SubKey $regPath -Name $propertyName -Value $propertyValue -Type 'DWORD'

	# Enable Cloud Clipboard Sync (Automatic) - must use a Microsoft Account to sync accross devices.
	$propertyName = "CloudClipboardAutomaticUpload"
	$propertyValue = 1 ## 1 = enabled, 0 = disabled
	Ensure-RegistryValue -Hive HKCU -SubKey $regPath -Name $propertyName -Value $propertyValue -Type 'DWORD'

	# $propertyName = "CloudClipboardAutomaticUpload"
	# $propertyValue = 1 ## 1 = enabled, 0 = disabled
	# Ensure-RegistryValue -Hive HKCU -SubKey $regPath -Name $propertyName -Value $propertyValue -Type 'DWORD'

	# Ensure the registry key exists
#	if (-not (Test-Path $regPath)) {
#		New-Item -Path $regPath -Force | Out-Null
#	}

	# Set the value
#	Set-ItemProperty -Path $regPath -Name $propertyName -Value $propertyValue -Type DWord

	## Display Any Policy - if it exists
	Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name AllowClipboardHistory -ErrorAction SilentlyContinue

	Write-Output "Clipboard history has been enabled."
}
EnableClipboardHistorySync

function Set-DefaultTerminalToWindowsTerminal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [switch]$AllUsers # also set HKLM keys (requires admin)
    )

    $terminalMoniker = 'Windows.Terminal'
    $hkcu = 'HKCU:\Console'
    $hklm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Console'
    $targets = @(
        '%%Startup',
        '%SystemRoot%_system32_cmd.exe',
        '%SystemRoot%_System32_WindowsPowerShell_v1.0_powershell.exe',
        '%ProgramFiles%_PowerShell_7_pwsh.exe',
        '%ProgramFiles(x86)%_PowerShell_7_pwsh.exe',
        '%SystemRoot%_system32_wsl.exe'
    )

    # 0) Sanity: is Windows Terminal present?
    $wtInstalled = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -AllUsers -ErrorAction SilentlyContinue
    if (-not $wtInstalled) {
        Write-Warning "Windows Terminal not found. Install from Microsoft Store or winget, then re-run."
        return $false
    }

    # helper to ensure a key + two values
    function Set-Delegation([string]$root, [string]$subKey){
        $path = Join-Path $root $subKey
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name DelegationConsole  -Value $terminalMoniker -Type String
        Set-ItemProperty -Path $path -Name DelegationTerminal -Value $terminalMoniker -Type String
    }

    try {
        foreach ($t in $targets) { Set-Delegation -root $hkcu -subKey $t }

        # Also ensure "legacy console" not forced (ForceV2 must be 1 or absent)
        $forceV2Path = Join-Path $hkcu '%%Startup'
        if (-not (Test-Path $forceV2Path)) { New-Item -Path $forceV2Path -Force | Out-Null }
        New-ItemProperty -Path $forceV2Path -Name ForceV2 -PropertyType DWord -Value 1 -Force | Out-Null

        if ($AllUsers) {
            if (-not ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
                Write-Warning "AllUsers requested but session not elevated. Skipping HKLM."
            } else {
                # Mirror to HKLM so new users inherit sane defaults
                Set-Delegation -root $hklm -subKey '%%Startup'
                foreach ($t in $targets[1..($targets.Count-1)]) { Set-Delegation -root $hklm -subKey $t }
                New-ItemProperty -Path (Join-Path $hklm '%%Startup') -Name ForceV2 -PropertyType DWord -Value 1 -Force | Out-Null
            }
        }

        Write-Host "✅ Windows Terminal set as the default terminal for common hosts."
        Write-Host "Tip: Close all consoles (conhost.exe) and relaunch, or sign out/in."
        return $true
    }
    catch {
        Write-Warning "❌ Failed: $($_.Exception.Message)"
        return $false
    }
}
Set-DefaultTerminalToWindowsTerminal -AllUsers

function DisableSearchonStartMenu {
	# Disable Bing web search in Start Menu
	$Path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
	if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
	New-ItemProperty -Path $Path -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWord -Force | Out-Null
}
DisableSearchonStartMenu

function HideVideoPicturesFileExplorer {

	# Hide Videos and Pictures folders from File Explorer (This PC / navigation pane)
	# Windows 10/11

	# Pictures Known Folder GUID
	$picturesGUID = "{0ddd015d-b06c-45d5-8c4c-f59713854639}"

	# Videos Known Folder GUID
	$videosGUID = "{35286a68-3c57-41a1-bbb1-0eae73d76c95}"

	# Registry paths
	$regPaths = @(
		"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace",
		"HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace"
	)

	foreach ($guid in @($picturesGUID, $videosGUID)) {
		foreach ($path in $regPaths) {
			$fullPath = Join-Path $path $guid
			if (Test-Path $fullPath) {
				Remove-Item $fullPath -Recurse -Force
				Write-Host "Removed $guid from $path"
			}
		}
	}
	# Optional: Restart Explorer automatically
	Stop-Process -Name explorer -Force
}
HideVideoPicturesFileExplorer

Write-Output ("Configuring Media...")
Function UninstallMediaPlayer {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "WindowsMediaPlayer" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Media.WindowsMediaPlayer*" } | Remove-WindowsCapability -Online | Out-Null
}
UninstallMediaPlayer

function Install-VLC {
	<#
    .SYNOPSIS
        Installs VLC (if missing) and sets it as the default app
        for common media file types (current user only).

    .NOTES
        Works best on Windows 10/11 with winget installed.
        May require logoff/logon for associations to fully apply.
    #>

	# 1. Install VLC if not already installed
	if (-not (Get-Command "vlc.exe" -ErrorAction SilentlyContinue)) {
		Write-Host "Installing VLC via winget..."
		winget install --id VideoLAN.VLC -e --accept-source-agreements --accept-package-agreements
	}
 else {
		Write-Host "VLC is already installed."
	}

	# 2. VLC ProgIDs (more precise per extension than just VLC.mp4)
	$vlcProgIDs = @{
		".mp4"  = "VLC.mp4"
		".mkv"  = "VLC.mkv"
		".avi"  = "VLC.avi"
		".mov"  = "VLC.mov"
		".flv"  = "VLC.flv"
		".wmv"  = "VLC.wmv"
		".mp3"  = "VLC.mp3"
		".wav"  = "VLC.wav"
		".flac" = "VLC.flac"
		".aac"  = "VLC.aac"
		".ogg"  = "VLC.ogg"
		".m4a"  = "VLC.m4a"
	}

	$regBase = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"

	foreach ($ext in $vlcProgIDs.Keys) {
		$progId = $vlcProgIDs[$ext]
		$userChoicePath = Join-Path (Join-Path $regBase $ext) "UserChoice"

		# Ensure key exists
		if (-not (Test-Path $userChoicePath)) {
			New-Item -Path $userChoicePath -Force -ErrorAction SilentlyContinue | Out-Null
		}

		# Set VLC as default handler
		Set-ItemProperty -Path $userChoicePath -Name "ProgId" -Value $progId -Force -ErrorAction SilentlyContinue | Out-Null
		Write-Host "Associated $ext with VLC ($progId)"
	}

	Write-Host "✅ VLC set as default media player for current user. Logoff/logon may be required."
}
Install-VLC

function Wait-WindowsUptime {

    $Minutes = 10
	$targetSeconds = $Minutes * 60
	$CheckInterval = 1
    Write-Host "[INFO] Waiting for system uptime to reach $Minutes minute(s)..."

    while ($true) {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $seconds = [int]$uptime.TotalSeconds

        if ($seconds -ge $targetSeconds) {
            #Write-Host "[INFO] Uptime reached $([math]::Round($seconds/60,1)) minute(s)."
            break
        }

        $remaining = $targetSeconds - $seconds
        Write-Host "[INFO] Current uptime: $([math]::Round($seconds/60,1)) min — waiting $remaining s more..."
        Start-Sleep -Seconds ([Math]::Min($CheckInterval, $remaining))
    }
	return $true
}

function SetAustraliaLocation {

	$ShortLanguage = "AU" ## Language pack for Australian English

	Wait-WindowsUptime
	## Set the Home Location
	$geoId = (New-Object System.Globalization.RegionInfo $ShortLanguage).GeoId
    Write-Host "Setting Windows location to be $ShortLanguage"
	Set-WinHomeLocation -GeoId $geoId
}

function EnableAustralianLanguagePack {

	Wait-WindowsUptime
	$ShortLanguage = "AU" ## Language pack for Australian English
	$lcid = ([System.Globalization.CultureInfo]::GetCultureInfo("en-$ShortLanguage")).LCID
	$DisplayName = ([System.Globalization.CultureInfo]::GetCultureInfo("en-$ShortLanguage")).DisplayName
	$Language = ([System.Globalization.CultureInfo]::GetCultureInfo("en-$ShortLanguage")).Name
	Write-Host 		"lcid        = $lcid"            ## 3081
	Write-Host  	"DisplayName = $DisplayName"     ## English (Australia)
	Write-Host      "Language    = $Language"        ## en-AU
	
	Write-Output "Installing language pack: $DisplayName"

	try {
		## Set-Culture -CultureInfo de-DE
		Set-Culture -CultureInfo $Language 

		## Install the language pack with UI, system, and input preferences
		$job = Install-Language -Language $Language -CopyToSettings
		# Wait until the installation completes
		$job | Wait-Job
		Receive-Job $job
		Write-Host "✅ Language installation completed."
		
		## Get-WindowsCapability -Online | Where-Object Name -like '*en-AU*'
		$capabilities = @(
			"Language.Basic~~~$Language~0.0.1.0",
			"Language.Speech~~~$Language~0.0.1.0",
			"Language.TextToSpeech~~~$Language~0.0.1.0",
			"Language.OCR~~~$Language~0.0.1.0"
		)
		foreach ($capability in $capabilities) {
			Write-Output "Installing feature: $capability"
			if ((Get-WindowsCapability -Online -Name $capability).State -ne 'Installed') {
				Add-WindowsCapability -Online -Name $capability
			} else {
				Write-Host "$capability already INSTALLED"
			}
		}
	
	    # sets a user-preferred display language to be used for the Windows user interface (UI).
		# Log off and loging back on is required for changes to take place.
		Set-WinUILanguageOverride -Language $Language
		Set-Culture -CultureInfo $Language

		## Set user language list
		$LangList = New-WinUserLanguageList -Language $Language
		Set-WinUserLanguageList -LanguageList $LangList -Force
		Set-WinSystemLocale -SystemLocale $Language

		## Copy internationl settings to system - Log off and loging back on is required for changes to take place.
		## Windows 11 only
		Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

		## Set speech language to Australian as well
		$speechKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings'
        if (-not (Test-Path $speechKey)) { New-Item -Path $speechKey -Force | Out-Null }
        New-ItemProperty -Path $speechKey -Name 'SpeechLanguage' -Value $Language -PropertyType String -Force | Out-Null

		## $voice = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enAU_JamesM"
		$voice = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enAU_CatherineM"
		if (Test-Path $voice) {
			CreateIfNotExists "HKCU:\Software\Microsoft\Speech\Voices"
			Set-ItemProperty -Path "HKCU:\Software\Microsoft\Speech\Voices" -Name "DefaultTokenId" -Value $voice -Type String
			Get-Item -Path "HKCU:\Software\Microsoft\Speech\Voices"
		}

		Write-Output "$Language pack (and features) has been installed and enabled!"
		Get-Language
		Write-Output "You may need to sign out and sign back in for the change to take effect."
	}
 	catch {
		Write-Error "Failed to install language pack: $_"
	}
	return
}
SetAustraliaLocation
EnableAustralianLanguagePack

function SortOutTimeManagement {
	$vmic = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\VMICTimeProvider"

	if ($vmic.Enabled -eq 1) {
		Write-Host "✅ VMICTimeProvider is enabled -  leaving it alone."
	} else {
		Stop-Service -Name W32Time
		Write-Host "❌ VMICTimeProvider is not enabled -- configuring NTP settings..."
		$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
		$regProperties = @{
			Name         = "Type"
			Value        = "NTP"
			PropertyType = "String"
			ErrorAction  = "Stop"
		}

		Try {
			$Null = New-ItemProperty -Path $registryPath @regProperties -Force
			Write-Log -Message "Updated Set W32Time Parameter Type to NTP in registry"
		}
		Catch [System.Management.Automation.ItemNotFoundException] {
			Write-Log -Message "Error: $registryPath path not found, attempting to create..."
			$Null = New-Item -Path $registryPath -Force
			$Null = New-ItemProperty -Path $registryPath @regProperties -Force
		}
		Catch {
			Write-Log -Message "Error changing registry: $($_.Exception.message)"
			Write-Warning "Error: $($_.Exception.message)"        
			Exit
		}
		Finally {
			Write-Log -Message "Finished Set W32Time Parameter Type to NTP"
		}
		$ntpServer = "time.windows.com,0x1"
		Set-ItemProperty -Path $registryPath -Name "NtpServer" -Value $ntpServer -Type String
		Set-Service -Name W32Time -StartupType Automatic
		Start-Service -Name W32Time
	}
}
SortOutTimeManagement

Write-Host "Restarting Windows Explorer..."
Stop-Process -Name explorer -Force
Start-Process explorer.exe

Write-Host "`n🛑 Changes applied. Please sign out or restart the computer to fully apply settings."

## Cleanup
## winget remove Splashtop.SplashtopStreamer
## winrm HTTPS requires a local computer Server Authentication certificate with a CN matching the hostname to be installed. The certificate mustn't be expired, revoked, or self-signed.
## Test-NetConnection -Port 443 -ComputerName localhost -InformationLevel Detailed
Return $true

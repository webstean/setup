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
Write-Output ("Configuring...")
function DisableIPv6 {
	$setIpv6Value = 0x20
	## Prefer IPv4 over IPv6 with 0x20, disable  IPv6 with 0xff, revert to default with 0x00.
	Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value $setIpv6Value
	## Go further, by disabling IPv6 by removing binding
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
DisableIPv6
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
	<#
    .SYNOPSIS
        Disables MSN news feeds, widgets, and search highlights on Windows 11.

    .DESCRIPTION
        - Disables the Widgets feature (news, weather, stocks).
        - Disables MSN content in search and feeds.
        - Applies settings for current user and system.
        - Requires restart or sign-out to fully apply.

    .EXAMPLE
        Disable-MsnFeedsAndWidgets
    #>

	[CmdletBinding()]
	param()

	if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
		).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
		Write-Warning "⚠️  Please run this script as Administrator."
		return
	}

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
		Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Force
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

	# 4. Disable personalized feeds content
	try {
		$feedsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
		New-Item -Path $feedsKey -Force | Out-Null
		New-ItemProperty -Path $feedsKey -Name "ShellFeedsTaskbarViewMode" -Value 2 -PropertyType DWord -Force | Out-Null
		Write-Host "✅ Personalized content in feeds disabled."
	}
 catch {
		Write-Warning "❌ Failed to disable feeds view: $_"
	}

	Write-Host "`n🛑 Changes applied. Please sign out or restart the computer to fully apply settings."
}
Disable-MsnFeedsAndWidgets


# Enable location feature and scripting for the location feature
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
DisableRecoveryAndReset ## these dont work with Intune enrolled Autopilot devices anyway

# Disable Autoplay
Function DisableAutoplay {
	Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Type DWord -Value 1
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
Write-Output ("Configuring Media...")
Function UninstallMediaPlayer {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "WindowsMediaPlayer" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Media.WindowsMediaPlayer*" } | Remove-WindowsCapability -Online | Out-Null
}
UninstallMediaPlayer

# Uninstall Internet Explorer
Function UninstallInternetExplorer {
	Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -like "Internet-Explorer-Optional*" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
	Get-WindowsCapability -Online | Where-Object { $_.Name -like "Browser.InternetExplorer*" } | Remove-WindowsCapability -Online | Out-Null
}
UninstallInternetExplorer

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

Write-Output ("Uninstalling Bloat...")
# Uninstall default Microsoft applications
Function UninstallMsftBloat {
	## Import-Module Appx
	Get-AppxPackage "Microsoft.3DBuilder" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.AppConnector" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingFinance" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingFoodAndDrink" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingHealthAndFitness" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingMaps" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingNews" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingSports" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingTranslator" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingTravel" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.BingWeather" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.CommsPhone" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.ConnectivityStore" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.FreshPaint" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.GetHelp" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Getstarted" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.HelpAndTips" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Media.PlayReadyClient.2" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Messaging" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Microsoft3DViewer" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MicrosoftOfficeHub" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MicrosoftPowerBIForWindows" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MicrosoftSolitaireCollection" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MicrosoftStickyNotes" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MinecraftUWP" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MixedReality.Portal" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MoCamera" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.MSPaint" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.NetworkSpeedTest" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.OfficeLens" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Office.OneNote" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Office.Sway" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.OneConnect" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.People" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Print3D" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Reader" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.RemoteDesktop" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.SkypeApp" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Todos" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Wallet" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WebMediaExtensions" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Whiteboard" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsAlarms" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsCamera" | Remove-AppxPackage
	Get-AppxPackage "microsoft.windowscommunicationsapps" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsFeedbackHub" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsMaps" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsPhone" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Windows.Photos" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsReadingList" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsScan" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WindowsSoundRecorder" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WinJS.1.0" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.WinJS.2.0" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.YourPhone" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.ZuneMusic" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.ZuneVideo" | Remove-AppxPackage
	Get-AppxPackage "Microsoft.Advertising.Xaml" | Remove-AppxPackage # Dependency for microsoft.windowscommunicationsapps, Microsoft.BingWeather
}
UninstallMsftBloat

# Uninstall default third party applications
function UninstallThirdPartyBloat {
	## Import-Module Appx
	Get-AppxPackage "2414FC7A.Viber" | Remove-AppxPackage
	Get-AppxPackage "41038Axilesoft.ACGMediaPlayer" | Remove-AppxPackage
	Get-AppxPackage "46928bounde.EclipseManager" | Remove-AppxPackage
	Get-AppxPackage "4DF9E0F8.Netflix" | Remove-AppxPackage
	Get-AppxPackage "64885BlueEdge.OneCalendar" | Remove-AppxPackage
	Get-AppxPackage "7EE7776C.LinkedInforWindows" | Remove-AppxPackage
	Get-AppxPackage "828B5831.HiddenCityMysteryofShadows" | Remove-AppxPackage
	Get-AppxPackage "89006A2E.AutodeskSketchBook" | Remove-AppxPackage
	Get-AppxPackage "9E2F88E3.Twitter" | Remove-AppxPackage
	Get-AppxPackage "A278AB0D.DisneyMagicKingdoms" | Remove-AppxPackage
	Get-AppxPackage "A278AB0D.DragonManiaLegends" | Remove-AppxPackage
	Get-AppxPackage "A278AB0D.MarchofEmpires" | Remove-AppxPackage
	Get-AppxPackage "ActiproSoftwareLLC.562882FEEB491" | Remove-AppxPackage
	Get-AppxPackage "AD2F1837.GettingStartedwithWindows8" | Remove-AppxPackage
	Get-AppxPackage "AD2F1837.HPJumpStart" | Remove-AppxPackage
	Get-AppxPackage "AD2F1837.HPRegistration" | Remove-AppxPackage
	Get-AppxPackage "AdobeSystemsIncorporated.AdobePhotoshopExpress" | Remove-AppxPackage
	Get-AppxPackage "Amazon.com.Amazon" | Remove-AppxPackage
	Get-AppxPackage "C27EB4BA.DropboxOEM" | Remove-AppxPackage
	Get-AppxPackage "CAF9E577.Plex" | Remove-AppxPackage
	Get-AppxPackage "CyberLinkCorp.hs.PowerMediaPlayer14forHPConsumerPC" | Remove-AppxPackage
	Get-AppxPackage "D52A8D61.FarmVille2CountryEscape" | Remove-AppxPackage
	Get-AppxPackage "D5EA27B7.Duolingo-LearnLanguagesforFree" | Remove-AppxPackage
	Get-AppxPackage "DB6EA5DB.CyberLinkMediaSuiteEssentials" | Remove-AppxPackage
	Get-AppxPackage "DolbyLaboratories.DolbyAccess" | Remove-AppxPackage
	Get-AppxPackage "Drawboard.DrawboardPDF" | Remove-AppxPackage
	Get-AppxPackage "Facebook.Facebook" | Remove-AppxPackage
	Get-AppxPackage "Fitbit.FitbitCoach" | Remove-AppxPackage
	Get-AppxPackage "flaregamesGmbH.RoyalRevolt2" | Remove-AppxPackage
	Get-AppxPackage "GAMELOFTSA.Asphalt8Airborne" | Remove-AppxPackage
	Get-AppxPackage "KeeperSecurityInc.Keeper" | Remove-AppxPackage
	Get-AppxPackage "king.com.BubbleWitch3Saga" | Remove-AppxPackage
	Get-AppxPackage "king.com.CandyCrushFriends" | Remove-AppxPackage
	Get-AppxPackage "king.com.CandyCrushSaga" | Remove-AppxPackage
	Get-AppxPackage "king.com.CandyCrushSodaSaga" | Remove-AppxPackage
	Get-AppxPackage "king.com.FarmHeroesSaga" | Remove-AppxPackage
	Get-AppxPackage "Nordcurrent.CookingFever" | Remove-AppxPackage
	Get-AppxPackage "PandoraMediaInc.29680B314EFC2" | Remove-AppxPackage
	Get-AppxPackage "PricelinePartnerNetwork.Booking.comBigsavingsonhot" | Remove-AppxPackage
	Get-AppxPackage "SpotifyAB.SpotifyMusic" | Remove-AppxPackage
	Get-AppxPackage "ThumbmunkeysLtd.PhototasticCollage" | Remove-AppxPackage
	Get-AppxPackage "WinZipComputing.WinZipUniversal" | Remove-AppxPackage
	Get-AppxPackage "XINGAG.XING" | Remove-AppxPackage
}
UninstallThirdPartyBloat

# Enable Clipboard History
function EnableClipboardHistory {
	$regPath = "HKCU:\Software\Microsoft\Clipboard"
	$propertyName = "EnableClipboardHistory"
	$propertyValue = 1

	# Ensure the registry key exists
	if (-not (Test-Path $regPath)) {
		New-Item -Path $regPath -Force | Out-Null
	}

	# Set the value
	Set-ItemProperty -Path $regPath -Name $propertyName -Value $propertyValue -Type DWord

	Write-Output "Clipboard history has been enabled."
}
EnableClipboardHistory

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
			New-Item -Path $userChoicePath -Force | Out-Null
		}

		# Set VLC as default handler
		Set-ItemProperty -Path $userChoicePath -Name "ProgId" -Value $progId -Force
		Write-Host "Associated $ext with VLC ($progId)"
	}

	Write-Host "✅ VLC set as default media player for current user. Logoff/logon may be required."
}
Install-VLC

function EnableAustralianLanguagePack {

	$DisplayName = "English (Australia)"
	$Language = "en-AU" ## Language pack for Australian English
	$ShortLanguage = "AU" ## Language pack for Australian English
	$CodeLanguage = 12

	## Set the Home Location
	$geoId = (New-Object System.Globalization.RegionInfo $ShortLanguage).GeoId
	Set-WinHomeLocation -GeoId $geoId
	
	if ( (Get-WinSystemLocale).Name -eq $Language ) {
		return
	}
	
	Get-InstalledLanguage
	Get-WinSystemLocale
	Write-Output "Installing language pack: $DisplayName"

	## Install-Module -Name Install-Language

	try {
		## Install the language pack with UI, system, and input preferences
		powershell.exe -Command "Install-Language -Language $Language -CopyToSettings"

		## Set system locale
		powershell.exe -Command "Set-WinSystemLocale -SystemLocale $Language"
		powershell.exe -Command "Set-WinUILanguageOverride -Language $Language"
		powershell.exe -Command "Set-Culture -CultureInfo $Language"

		## Set user language list
		$LangList = New-WinUserLanguageList -Language $Language
		Set-WinUserLanguageList -LanguageList $LangList -Force
		Set-WinSystemLocale -SystemLocale $Language

		## Copy to system
		Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true

		## Get-WindowsCapability -Online | Where-Object { $_.Name -like "*Speech*" }
		$features = @(
			"Language.Handwriting~~~$Language~0.0.1.0",
			"Language.Speech~~~$Language~0.0.1.0",
			"Language.TextToSpeech~~~$Language~0.0.1.0"
		)
		foreach ($feature in $features) {
			Write-Output "Installing feature: $feature"
			#powershell.exe -Command "Add-WindowsCapability -Online -Name $feature"
			Add-WindowsCapability -Online -Name $feature
		}
	
		## $voice = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enAU_JamesM"
		$voice = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\MSTTS_V110_enAU_CatherineM"
		Set-ItemProperty -Path "HKCU:\Software\Microsoft\Speech\Voices" -Name "DefaultTokenId" -Value $voice -Type String
		Get-Item -Path "HKCU:\Software\Microsoft\Speech\Voices"

		Write-Output "$Language pack has been enabled!"
		Set-ItemProperty -Path "HKCU:\Control Panel\International\Geo" -Name "Name" -Value $ShortLanguage
		Set-ItemProperty -Path "HKCU:\Control Panel\International\Geo" -Name "Nation" -Value $CodeLanguage
		Set-ItemProperty -Path "HKCU:\Control Panel\International\Geo" -Name "AutoGeo" -Value 1
		Write-Output "You may need to sign out and sign back in for the change to take effect."
	}
 	catch {
		Write-Error "Failed to install language pack: $_"
	}
	return
}
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
#SortOutTimeManagement

## Cleanup
## winget remove Splashtop.SplashtopStreamer
## winrm HTTPS requires a local computer Server Authentication certificate with a CN matching the hostname to be installed. The certificate mustn't be expired, revoked, or self-signed.
## Test-NetConnection -Port 443 -ComputerName localhost -InformationLevel Detailed
Exit 0

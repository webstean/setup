#Requires -RunAsAdministrator

## Current Statue: Global Secure Access Client (windows)
## ==> IPv4 is preferred and it suggested you disabled IPv6 is you have issues: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health[...]
## ==> DNS over HTTP not supported: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#dns-over-https-not-supported
## ==> QUIC is not supported for Internet Access, but is supported for Private Access and Microsoft 365 workloads.
## These changes won't be fully effective until after reboot.
function CreateIfNotExists {
    param($Path)
    if (-NOT (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Ensure-RegistryValue {
    param(
        [Parameter(Mandatory)] [ValidateSet('HKLM', 'HKCU')] [string] $Hive,
        [Parameter(Mandatory)] [string] $SubKey,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [object] $Value,
        [ValidateSet('STRING', 'DWORD', 'QWORD', 'BINARY', 'MULTISTRING', 'EXPANDSTRING')]
        [string] $Type = 'String'
    )
    $path = "$Hive`:\$SubKey"
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        return [pscustomobject]@{ Path = $path; Name = $Name; Value = $Value; Type = $Type; Status = 'OK' }
    }
    catch {
        return [pscustomobject]@{ Path = $path; Name = $Name; Error = $_.Exception.Message; Status = 'FAILED' }
    }
}
## Example:
#Ensure-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso\MyApp' -Name 'ServerUrl' -Value 'https://example.local' -Type 'String'

# Check if winget is installed
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host "✅ Winget is already installed. Version:" 
    winget --version
}
else {
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
    }
    else {
        Write-Host "❌ Winget installation failed. You may need to update Windows or install manually from Microsoft Store."
        exit 1
    }
}

Write-Output "Configuring..."

function PreferIPv4 {
    ## Prefer IPv4 over IPv6 with 0x20, disable  IPv6 with 0xff, revert to default with 0x00.
    $setting = 0x20
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value $setting
}
function UnbindIPv6 {
    # More radical - typically not necessary
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
    Set-ItemProperty -Path "HKLM:\Software\Policies\Google\Chrome" -Name "QuicAllowed" -Value $disableQUIC -Type DWord -Force
}

## Configure for MAXIMUM compatibility with Microsoft Global Secure Access and other similar (Cisco Umbrella etc..)
PreferIPv4
# UnbindIPv6
DisableInbuiltDNS
DisableQUIC

function Set-NetworkProfilesToPrivate {
    [CmdletBinding()]
    param ()

    $networks = Get-NetConnectionProfile

    foreach ($net in $networks) {
        if ($net.NetworkCategory -ne 'Private') {
            Write-Host "Changing '$($net.Name)' from $($net.NetworkCategory) to Private..."
            Set-NetConnectionProfile -InterfaceIndex $net.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
        }
        else {
            Write-Host "'$($net.Name)' is already Private. Skipping."
        }
    }

    # Verify
    Get-NetConnectionProfile
}

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
        New-Item -Path $searchKey -Force | Out-Null ## Get weird error message: Attempted to perform an unauthorized operation.
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

# Enable location on Windows 10/11
Function EnableLocation {
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -ErrorAction SilentlyContinue

    ## Enable location services system-wide
    $cfgKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    if (-not (Test-Path $cfgKey)) {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service' -Name 'Configuration' -Force | Out-Null
    }
    New-ItemProperty -Path $cfgKey -Name 'Status' -PropertyType DWord -Value 1 -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Value 1

    ## Allow apps to access location
    $capCU = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    if (-not (Test-Path $capCU)) {
        New-Item -Path $capCU -Force | Out-Null 
    }
    New-ItemProperty -Path $capCU -Name 'Value' -PropertyType String -Value 'Allow' -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Allow"

    Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value"
    ## this will be set to DENY if there is a Group Policy, MDM controlling this
    ## Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value"

    ## Setup location service to Automation and Restart
    Set-Service -Name lfsvc -StartupType Automatic -ErrorAction SilentlyContinue
    Restart-Service lfsvc
}
# EnableLocation

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

Write-Output "Configuring Sounds..."

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
    # Require admin rights
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Run this function from an elevated PowerShell session (Run as Administrator)."
        return
    }

    $musicGuid = "{a0c69a99-21c8-4671-8703-7934162fcf1d}"

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag" -Name "ThisPCPolicy" -Type String -Value "Hide"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag" -Name "ThisPCPolicy" -Type String -Value "Hide"
    $propertyBagKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag"
    $valueName = "ThisPCPolicy"

    # Ensure the PropertyBag key exists
    if (-not (Test-Path $propertyBagKey)) {
        New-Item -Path $propertyBagKey -Force | Out-Null
    }

    # Set ThisPCPolicy=Hide
    New-ItemProperty -Path $propertyBagKey `
        -Name $valueName `
        -Value "Hide" `
        -PropertyType String `
        -Force | Out-Null

    Write-Host "🎵 Music folder will be hidden from 'This PC' permanently." -ForegroundColor Green
}
HideMusicFromExplorer ## does not work

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

function Set-EdgeNoFirstRun {
    <#
    .SYNOPSIS
        Configures Microsoft Edge to skip first run, suppress import prompts,
        and auto sign-in + sync without user prompts (where supported).

    .DESCRIPTION
        Sets Microsoft Edge enterprise policy registry keys so:
          - First run experience is hidden
          - Import / add-profile / default-browser prompts are suppressed
          - Browser sign-in is forced
          - Automatic sign-in with the current account is enabled
          - Sync is forced on and cannot be disabled by the user

        Notes:
        - Auto sign-in + sync assumes the device/account setup supports it
          (e.g. Entra ID or AD with Seamless SSO / hybrid join).
        - Policies are applied via HKLM, so they affect all users on the device.
    #>

    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    # Create policy path if not exists
    if (-not (Test-Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    # Core "no first run" + profile/import prompts + auto sign-in + forced sync
    $policies = @{
        # Your original "no first run / no import" bits
        "HideFirstRunExperience"               = 1  # Hide first-run UI
        "ImportFavorites"                      = 0  # Don't import favorites
        "AutoImportAtFirstRun"                 = 0  # No auto-import wizard
        "BrowserAddProfileEnabled"             = 0  # Prevent add-profile prompts
        "DefaultBrowserSettingEnabled"         = 0  # Don't prompt to be default

        # 🔐 Identity / sign-in / sync
        # Allow/force browser sign-in so a profile is always signed in
        # 0 = Disabled, 1 = Enabled, 2 = Force sign-in
        "BrowserSignin"                        = 2

        # Enable automatic sign-in from web/OS to browser
        # These two must match and be 1 to enable auto sign-in
        "WebToBrowserSignInEnabled"            = 1
        "SeamlessWebToBrowserSignInEnabled"    = 1

        # Auto sign in with on-prem AD account when no Entra account
        # (only applies in domain-joined scenarios)
        "ConfigureOnPremisesAccountAutoSignIn" = 1

        # Force sync on and prevent turning it off
        "ForceSync"                            = 1
    }

    foreach ($policy in $policies.GetEnumerator()) {
        New-ItemProperty -Path $edgePolicyPath `
            -Name $policy.Key `
            -Value $policy.Value `
            -PropertyType DWord `
            -Force | Out-Null
    }

    # Optional: user hive tweak to reduce sign-in CTA noise
    $userCtaPath = "HKCU:\Software\Microsoft\Edge\SignIn"
    if (-not (Test-Path $userCtaPath)) {
        New-Item -Path $userCtaPath -Force | Out-Null
    }
    New-ItemProperty -Path $userCtaPath `
        -Name "SignInCtaShownCount" `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Host "✅ Microsoft Edge configured to skip first run, auto sign-in, and force sync (subject to device/account setup)."
}
Set-EdgeNoFirstRun

function Hide-WindowsSecurityFamilyOptions {
    <#
    .SYNOPSIS
        Hides the "Family options" section in the Windows Security app.

    .DESCRIPTION
        Sets a registry value under
        HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Family options
        to disable the "Family options" UI section.
    #>

    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Family options"
    $valueName = "UILockdown"

    # Ensure running elevated
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Run this function as Administrator to modify HKLM."
        return
    }

    if (-not (Test-Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    New-ItemProperty -Path $keyPath `
        -Name $valueName `
        -Value 1 `
        -PropertyType DWord `
        -Force | Out-Null

    Write-Host "✅ 'Family options' hidden in Windows Security app." -ForegroundColor Green
}
Hide-WindowsSecurityFamilyOptions

# Disable Windows Media Player's media sharing feature
Function DisableMediaSharing {
    If (!(Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Force | Out-Null
    }
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Name "PreventLibrarySharing" -Type DWord -Value 1
    Write-Host "✅ 'Disabled Media Sharing" -ForegroundColor Green
}
DisableMediaSharing

# Install .NET Framework 2.0, 3.0 and 3.5 runtimes - Requires internet connection
# Take ages to install!!
Function InstallNET23 {
    Write-Output "Installing DotNet 2, 3 and 3.5 for compatibility..."
    If ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
        Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "NetFx3" } | Enable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
    }
    Else {
        Install-WindowsFeature -Name "NET-Framework-Core" -WarningAction SilentlyContinue | Out-Null
    }
}
# InstallNET23

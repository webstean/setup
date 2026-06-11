#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

## Current Statue: Global Secure Access Client (windows)
## ==> IPv4 is preferred and it suggested you disabled IPv6 is you have issues: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health[...]
## ==> DNS over HTTP not supported: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#dns-over-https-not-supported
## ==> QUIC is not supported for Internet Access, but is supported for Private Access and Microsoft 365 workloads.
## These changes won't be fully effective until after reboot.
function CreateIfNotExists {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Ensure-RegistryValue {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('HKLM', 'HKCU')]
        [string]$Hive,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SubKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('STRING', 'DWORD', 'QWORD', 'BINARY', 'MULTISTRING', 'EXPANDSTRING')]
        [string]$Type = 'String'
    )

    $path = "$Hive`:\$SubKey"
    try {
        if (-not (Test-Path -Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        New-ItemProperty -Path $path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        return [pscustomobject]@{
            Path   = $path
            Name   = $Name
            Value  = $Value
            Type   = $Type
            Status = 'OK'
        }
    }
    catch {
        return [pscustomobject]@{
            Path   = $path
            Name   = $Name
            Error  = $_.Exception.Message
            Status = 'FAILED'
        }
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
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    ## Prefer IPv4 over IPv6 with 0x20, disable IPv6 with 0xff, revert to default with 0x00.
    $setting = 0x20
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Type DWord -Value $setting
}

function UnbindIPv6 {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # More radical - typically not necessary
    Get-NetAdapterBinding | Where-Object { $_.ComponentID -eq 'ms_tcpip6' } | ForEach-Object {
        Disable-NetAdapterBinding -Name $_.Name -ComponentID 'ms_tcpip6'
    }
}

function DisableInbuiltDNS {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $disableBuiltInDNS = 0x00

    ## Disabled Inbuilt DNS for Microsoft Edge
    CreateIfNotExists -Path "HKLM:\SOFTWARE\Policies\Microsoft"
    CreateIfNotExists -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "DnsOverHttpsMode" -Value "off"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "BuiltInDnsClientEnabled" -Type DWord -Value $disableBuiltInDNS

    ## Disabled Inbuilt DNS for Google Chrome
    CreateIfNotExists -Path "HKLM:\SOFTWARE\Policies\Google"
    CreateIfNotExists -Path "HKLM:\SOFTWARE\Policies\Google\Chrome"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "DnsOverHttpsMode" -Value "off"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "BuiltInDnsClientEnabled" -Type DWord -Value $disableBuiltInDNS
}

function DisableQUIC {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    ## QUIC is currently supported WITH Private Access and Microsoft 365 workloads but NOT in Internet Access
    $disableQUIC = 0x00
    Set-ItemProperty -Path "HKLM:\Software\Policies\Microsoft\Edge" -Name "QuicAllowed" -Value $disableQUIC -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\Software\Policies\Google\Chrome" -Name "QuicAllowed" -Value $disableQUIC -Type DWord -Force
}

## Configure for MAXIMUM compatibility with Microsoft Global Secure Access and other similar (Cisco Umbrella etc..)
PreferIPv4
# UnbindIPv6
DisableInbuiltDNS
DisableQUIC

function Set-NetworkProfilesToPrivate {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param()

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

    Get-NetConnectionProfile
}

# WANT MORE OPTIONS, see: https://github.com/petrak-dan/Win11-Initial-Setup-Script/blob/main/Win10.psm1
# Disable News and Interests feed in Taskbar
function DisableNewsAndInterests {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" | Out-Null
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds" -Name "EnableFeeds" -Type DWord -Value 0
}
DisableNewsAndInterests

function Disable-MsnFeedsAndWidgets {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Host "`n🔧 Disabling MSN Feeds, Widgets, and Search Highlights..."

    try {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -PropertyType DWord -Value 0 -Force | Out-Null
        Write-Host "�� Widgets disabled via policy (HKLM)."
    }
    catch {
        Write-Warning "❌ Failed to set system-wide widget policy: $($_.Exception.Message)"
    }

    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "✅ Taskbar widgets disabled for current user."
    }
    catch {
        Write-Warning "❌ Failed to disable taskbar widgets: $($_.Exception.Message)"
    }

    try {
        $searchKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        New-Item -Path $searchKey -Force | Out-Null
        New-ItemProperty -Path $searchKey -Name "IsDynamicSearchBoxEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $searchKey -Name "IsDynamicSearchBoxEnabledOnTablet" -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Host "✅ Search highlights disabled."
    }
    catch {
        Write-Warning "❌ Failed to configure search highlights: $($_.Exception.Message)"
    }

    try {
        $feedsKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
        New-Item -Path $feedsKey -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $feedsKey -Name "ShellFeedsTaskbarViewMode" -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "✅ Personalized content in feeds disabled."
    }
    catch {
        Write-Warning "❌ Failed to disable feeds view: $($_.Exception.Message)"
    }
}
Disable-MsnFeedsAndWidgets

function EnableLocation {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocationScripting" -ErrorAction SilentlyContinue

    $cfgKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    if (-not (Test-Path -Path $cfgKey)) {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service' -Name 'Configuration' -Force | Out-Null
    }

    New-ItemProperty -Path $cfgKey -Name 'Status' -PropertyType DWord -Value 1 -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration" -Name "Status" -Value 1

    $capCU = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    if (-not (Test-Path -Path $capCU)) {
        New-Item -Path $capCU -Force | Out-Null
    }

    New-ItemProperty -Path $capCU -Name 'Value' -PropertyType String -Value 'Allow' -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Allow"

    Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value"

    Set-Service -Name lfsvc -StartupType Automatic -ErrorAction SilentlyContinue
    Restart-Service -Name lfsvc
}
# EnableLocation

function DisableFeedback {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Siuf\Rules")) {
        New-Item -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name "NumberOfSIUFInPeriod" -Type DWord -Value 0
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "DoNotShowFeedbackNotifications" -Type DWord -Value 1
    Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClient" -ErrorAction SilentlyContinue | Out-Null
    Disable-ScheduledTask -TaskName "Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload" -ErrorAction SilentlyContinue | Out-Null
}
DisableFeedback

function DisableErrorReporting {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting" -Name "Disabled" -Type DWord -Value 1
    Disable-ScheduledTask -TaskName "Microsoft\Windows\Windows Error Reporting\QueueReporting" | Out-Null
}
DisableErrorReporting

function DisableRecoveryAndReset {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    reagentc /disable 2>&1 | Out-Null
}
DisableRecoveryAndReset

function DisableAutoplay {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Type DWord -Value 1
    Ensure-RegistryValue -Hive HKCU -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1 -Type 'DWORD'
}
DisableAutoplay

function DisableAutorun {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer")) {
        New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" | Out-Null
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Type DWord -Value 255
}
DisableAutorun

function EnableNTFSLongPaths {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWord -Value 1
}
EnableNTFSLongPaths

function DisableNTFSLastAccess {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    fsutil behavior set DisableLastAccess 1 | Out-Null
}
DisableNTFSLastAccess

function EnableAutoRebootOnCrash {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -Name "AutoReboot" -Type DWord -Value 1
}
EnableAutoRebootOnCrash

function ShowNetworkOnLockScreen {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DontDisplayNetworkSelectionUI" -ErrorAction SilentlyContinue
}
ShowNetworkOnLockScreen

function DisableAccessibilityKeys {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\StickyKeys" -Name "Flags" -Type String -Value "506"
    Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\ToggleKeys" -Name "Flags" -Type String -Value "58"
    Set-ItemProperty -Path "HKCU:\Control Panel\Accessibility\Keyboard Response" -Name "Flags" -Type String -Value "122"
}

Write-Output "Configuring Sounds..."

function SetSoundSchemeNone {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $SoundScheme = ".None"
    Get-ChildItem -Path "HKCU:\AppEvents\Schemes\Apps\*\*" | ForEach-Object {
        if (-not (Test-Path -Path "$($_.PsPath)\$($SoundScheme)")) {
            New-Item -Path "$($_.PsPath)\$($SoundScheme)" | Out-Null
        }

        if (-not (Test-Path -Path "$($_.PsPath)\.Current")) {
            New-Item -Path "$($_.PsPath)\.Current" | Out-Null
        }

        $data = (Get-ItemProperty -Path "$($_.PsPath)\$($SoundScheme)" -Name "(Default)" -ErrorAction SilentlyContinue)."(Default)"
        Set-ItemProperty -Path "$($_.PsPath)\$($SoundScheme)" -Name "(Default)" -Type String -Value $data
        Set-ItemProperty -Path "$($_.PsPath)\.Current" -Name "(Default)" -Type String -Value $data
    }

    Set-ItemProperty -Path "HKCU:\AppEvents\Schemes" -Name "(Default)" -Type String -Value $SoundScheme
}
SetSoundSchemeNone

function DisableStartupSound {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation" -Name "DisableStartupSound" -Type DWord -Value 1
}
DisableStartupSound

function DisableVerboseStatus {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ((Get-CimInstance -Class "Win32_OperatingSystem").ProductType -eq 1) {
        Remove-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -ErrorAction SilentlyContinue
    }
    else {
        Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System" -Name "VerboseStatus" -Type DWord -Value 0
    }
}
DisableVerboseStatus

function DisableSharingWizard {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SharingWizardOn" -Type DWord -Value 0
}
DisableSharingWizard

function ShowThisPCOnDesktop {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu")) {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0

    if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel")) {
        New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel" -Name "{20D04FE0-3AEA-1069-A2D8-08002B30309D}" -Type DWord -Value 0
}
ShowThisPCOnDesktop

function HideMusicFromExplorer {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Run this function from an elevated PowerShell session (Run as Administrator)."
        return
    }

    $musicGuid = "{a0c69a99-21c8-4671-8703-7934162fcf1d}"
    $propertyBagKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag"
    $wowPropertyBagKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag"
    $valueName = "ThisPCPolicy"

    if (-not (Test-Path -Path $propertyBagKey)) {
        New-Item -Path $propertyBagKey -Force | Out-Null
    }

    if (-not (Test-Path -Path $wowPropertyBagKey)) {
        New-Item -Path $wowPropertyBagKey -Force | Out-Null
    }

    Set-ItemProperty -Path $propertyBagKey -Name $valueName -Type String -Value "Hide"
    Set-ItemProperty -Path $wowPropertyBagKey -Name $valueName -Type String -Value "Hide"

    Write-Host "🎵 Music folder will be hidden from 'This PC' permanently." -ForegroundColor Green
}
HideMusicFromExplorer

function DisableIEandEdgeWarnings {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing")) {
        New-Item -Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing" -Name "WarnOnClose" -Type DWord -Value 0

    if (-not (Test-Path -Path "HKCU:\Software\Policies\Microsoft\Edge")) {
        New-Item -Path "HKCU:\Software\Policies\Microsoft\Edge" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Edge" -Name "RestoreOnStartup" -Type DWord -Value 1
}
DisableIEandEdgeWarnings

function Set-EdgeNoFirstRun {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $edgePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

    if (-not (Test-Path -Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    $policies = @{
        "HideFirstRunExperience"               = 1
        "ImportFavorites"                      = 0
        "AutoImportAtFirstRun"                 = 0
        "BrowserAddProfileEnabled"             = 0
        "DefaultBrowserSettingEnabled"         = 0
        "BrowserSignin"                        = 2
        "WebToBrowserSignInEnabled"            = 1
        "SeamlessWebToBrowserSignInEnabled"    = 1
        "ConfigureOnPremisesAccountAutoSignIn" = 1
        "ForceSync"                            = 1
    }

    foreach ($policy in $policies.GetEnumerator()) {
        New-ItemProperty -Path $edgePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
    }

    $userCtaPath = "HKCU:\Software\Microsoft\Edge\SignIn"
    if (-not (Test-Path -Path $userCtaPath)) {
        New-Item -Path $userCtaPath -Force | Out-Null
    }

    New-ItemProperty -Path $userCtaPath -Name "SignInCtaShownCount" -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "✅ Microsoft Edge configured to skip first run, auto sign-in, and force sync (subject to device/account setup)."
}
Set-EdgeNoFirstRun

function Hide-WindowsSecurityFamilyOptions {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $keyPath = "HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Family options"
    $valueName = "UILockdown"

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning "Run this function as Administrator to modify HKLM."
        return
    }

    if (-not (Test-Path -Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    New-ItemProperty -Path $keyPath -Name $valueName -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "✅ 'Family options' hidden in Windows Security app." -ForegroundColor Green
}
Hide-WindowsSecurityFamilyOptions

function DisableMediaSharing {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer")) {
        New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Force | Out-Null
    }

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer" -Name "PreventLibrarySharing" -Type DWord -Value 1
    Write-Host "✅ Disabled Media Sharing" -ForegroundColor Green
}
DisableMediaSharing

function Disable-WindowsGaming {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Ensure-Key {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
    }

    function Set-Dword {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,

            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            [int]$Value
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
    }
    catch {
        $summary.Notes += "Could not stop Game Bar processes: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
        $summary.GameDVREnforcedPolicy = $true
    }
    catch {
        $summary.Notes += "Policy write failed: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
        $summary.GameDVREnabledHKCU = $true
    }
    catch {
        $summary.Notes += "HKCU GameDVR write failed: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
        $summary.GameConfigDvrDisabled = $true
    }
    catch {
        $summary.Notes += "HKCU GameConfigStore write failed: $($_.Exception.Message)"
    }

    try {
        $hkcuBar = 'HKCU:\Software\Microsoft\GameBar'
        Set-Dword -Path $hkcuBar -Name 'ShowStartupPanel' -Value 0
        Set-Dword -Path $hkcuBar -Name 'UseNexusForGameBarEnabled' -Value 0
        Set-Dword -Path $hkcuBar -Name 'OpenGameBar' -Value 0
        Set-Dword -Path $hkcuBar -Name 'AutoGameModeEnabled' -Value 0
        $summary.GameBarUiDisabled = $true
        $summary.GameModeAutoDisabled = $true
    }
    catch {
        $summary.Notes += "GameBar settings write failed: $($_.Exception.Message)"
    }

    $runCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($name in 'XboxGameBar', 'GameBar') {
        try {
            if (Get-ItemProperty -Path $runCU -Name $name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $runCU -Name $name -Force -ErrorAction SilentlyContinue
                $summary.RunEntriesRemoved += $name
            }
        }
        catch {
            $summary.Notes += "Failed removing Run entry ${name}: $($_.Exception.Message)"
        }
    }

    $svcNames = 'XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc'
    foreach ($svc in $svcNames) {
        $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($service) {
            try {
                if ($service.Status -ne 'Stopped') {
                    Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
                }

                Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
                $summary.ServicesDisabled += $svc
            }
            catch {
                $summary.Notes += "Service $svc change failed: $($_.Exception.Message)"
            }
        }
    }

    $taskItems = @(
        @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTask' },
        @{ Path = '\Microsoft\XblGameSave\'; Name = 'XblGameSaveTaskLogon' }
    )
    foreach ($task in $taskItems) {
        try {
            $scheduledTask = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue
            if ($scheduledTask) {
                Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name | Out-Null
                $summary.TasksDisabled += ($task.Path + $task.Name)
            }
        }
        catch {
            $summary.Notes += "Task disable failed for $($task.Path)$($task.Name): $($_.Exception.Message)"
        }
    }

    try {
        Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay' -AllUsers -ErrorAction SilentlyContinue |
            ForEach-Object {
                try {
                    Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" -ErrorAction SilentlyContinue | Out-Null
                }
                catch {
                }
            }
    }
    catch {
        $summary.Notes += "Overlay package handling skipped: $($_.Exception.Message)"
    }

    Write-Verbose "Done. Some changes apply after sign-out or Explorer restart."
    return [pscustomobject]$summary
}

function Set-SettingsPageVisibility {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Hide', 'ShowOnly')]
        [string]$Mode = 'Hide',

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string[]]$Pages = @(),

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Add = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Remove = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Clear = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Get = $false
    )

    $KeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $ValueName = 'SettingsPageVisibility'

    $needsWrite = -not $Get
    if ($needsWrite -and -not $Clear -and -not $Remove -and -not $Add -and [string]::IsNullOrWhiteSpace($Mode)) {
        throw "No action specified. Use -Mode with -Pages, or -Add, -Remove, -Clear, or -Get."
    }

    if ($needsWrite -and (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) {
        throw "Run elevated (Administrator) to modify HKLM."
    }

    function Parse-Value {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        param(
            [Parameter(Mandatory = $false)]
            [AllowNull()]
            [string]$ValueText = $null
        )

        if ([string]::IsNullOrWhiteSpace($ValueText)) {
            return @{ Mode = $null; Pages = @() }
        }

        $parts = $ValueText.Split(':', 2)
        $parsedMode = $parts[0].Trim().ToLowerInvariant()
        $parsedPages = @()

        if ($parts.Count -gt 1 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $parsedPages = $parts[1].Split(';') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }

        return @{
            Mode  = if ($parsedMode -eq 'hide') { 'Hide' } elseif ($parsedMode -eq 'showonly') { 'ShowOnly' } else { $null }
            Pages = $parsedPages
        }
    }

    function Build-Value {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$InputMode,

            [Parameter(Mandatory = $true)]
            [ValidateNotNull()]
            [string[]]$InputPages
        )

        $uniquePages = $InputPages | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
        switch ($InputMode) {
            'Hide' { return ('hide:' + ($uniquePages -join ';')) }
            'ShowOnly' { return ('showonly:' + ($uniquePages -join ';')) }
            default { throw "Invalid mode '$InputMode' when building value." }
        }
    }

    if (-not (Test-Path -Path $KeyPath)) {
        if ($Get) {
            return [pscustomobject]@{
                Mode  = $null
                Pages = @()
                Raw   = $null
                Path  = "$KeyPath\$ValueName"
            }
        }

        New-Item -Path $KeyPath -Force | Out-Null
    }

    $currentRaw = (Get-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    $parsed = Parse-Value -ValueText $currentRaw
    $curMode = $parsed.Mode
    $curPages = [System.Collections.Generic.List[string]]::new()
    foreach ($page in $parsed.Pages) {
        [void]$curPages.Add($page)
    }

    if ($Get) {
        return [pscustomobject]@{
            Mode  = $curMode
            Pages = $parsed.Pages
            Raw   = $currentRaw
            Path  = "$KeyPath\$ValueName"
        }
    }

    if ($Clear) {
        Remove-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
        Write-Verbose "Policy cleared."
        return
    }

    if (($Mode -or $Add -or $Remove) -and $Pages.Count -gt 0) {
        $Pages = $Pages | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    if (($Mode) -and (-not $Add) -and (-not $Remove)) {
        if ($Pages.Count -eq 0) {
            throw "You must supply -Pages when using -Mode to overwrite."
        }

        $newRaw = Build-Value -InputMode $Mode -InputPages $Pages
        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }

    if ($Add) {
        if ($Pages.Count -eq 0) {
            throw "Use -Add with one or more -Pages."
        }

        $targetMode = $curMode
        if ([string]::IsNullOrWhiteSpace($targetMode)) {
            if ([string]::IsNullOrWhiteSpace($Mode)) {
                throw "No existing value. Use -Add together with -Mode Hide or ShowOnly to establish the mode."
            }

            $targetMode = $Mode
        }

        foreach ($page in $Pages) {
            if (-not $curPages.Contains($page)) {
                [void]$curPages.Add($page)
            }
        }

        $newRaw = Build-Value -InputMode $targetMode -InputPages $curPages.ToArray()
        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }

    if ($Remove) {
        if ($Pages.Count -eq 0) {
            throw "Use -Remove with one or more -Pages."
        }

        if ([string]::IsNullOrWhiteSpace($curMode)) {
            Write-Verbose "Nothing to remove; value not set."
            return
        }

        $remaining = $curPages | Where-Object { $Pages -notcontains $_ }
        $newRaw = Build-Value -InputMode $curMode -InputPages $remaining
        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }

    throw "No valid action specified. Use one of: -Mode Hide/ShowOnly (with -Pages), -Add, -Remove, -Clear, or -Get."
}

Disable-WindowsGaming
Set-SettingsPageVisibility -Get $true | Format-List

Set-SettingsPageVisibility -Mode Hide -Pages @(
    'family-group',
    'otherusers',
    'gaming',
    'lockscreen',
    'windowsinsider',
    'windowsinsider-optin',
    'troubleshoot',
    'map',
    'maps-downloadmaps',
    'autoplay'
)

Set-SettingsPageVisibility -Get $true | Format-List

function EnableClipboardHistorySync {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $regPath = "Software\Microsoft\Clipboard"

    Ensure-RegistryValue -Hive HKCU -SubKey $regPath -Name "EnableClipboardHistory" -Value 1 -Type 'DWORD'
    Ensure-RegistryValue -Hive HKCU -SubKey $regPath -Name "CloudClipboardAutomaticUpload" -Value 0 -Type 'DWORD'

    Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name AllowClipboardHistory -ErrorAction SilentlyContinue
    Write-Output "Clipboard history has been enabled."
}
EnableClipboardHistorySync

function Set-DefaultTerminalToWindowsTerminal {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$AllUsers = $false
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

    $wtInstalled = Get-AppxPackage -Name 'Microsoft.WindowsTerminal' -AllUsers -ErrorAction SilentlyContinue
    if (-not $wtInstalled) {
        Write-Warning "Windows Terminal not found. Install from Microsoft Store or winget, then re-run."
        return $false
    }

    function Set-Delegation {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Root,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubKey
        )

        $path = Join-Path -Path $Root -ChildPath $SubKey
        if (-not (Test-Path -Path $path)) {
            New-Item -Path $path -Force | Out-Null
        }

        Set-ItemProperty -Path $path -Name DelegationConsole -Value $terminalMoniker -Type String
        Set-ItemProperty -Path $path -Name DelegationTerminal -Value $terminalMoniker -Type String
    }

    try {
        foreach ($target in $targets) {
            Set-Delegation -Root $hkcu -SubKey $target
        }

        $forceV2Path = Join-Path -Path $hkcu -ChildPath '%%Startup'
        if (-not (Test-Path -Path $forceV2Path)) {
            New-Item -Path $forceV2Path -Force | Out-Null
        }

        New-ItemProperty -Path $forceV2Path -Name ForceV2 -PropertyType DWord -Value 1 -Force | Out-Null

        if ($AllUsers) {
            if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                Write-Warning "AllUsers requested but session not elevated. Skipping HKLM."
            }
            else {
                Set-Delegation -Root $hklm -SubKey '%%Startup'
                foreach ($target in $targets[1..($targets.Count - 1)]) {
                    Set-Delegation -Root $hklm -SubKey $target
                }

                New-ItemProperty -Path (Join-Path -Path $hklm -ChildPath '%%Startup') -Name ForceV2 -PropertyType DWord -Value 1 -Force | Out-Null
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
Set-DefaultTerminalToWindowsTerminal -AllUsers $true

function DisableSearchonStartMenu {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $path = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
    if (-not (Test-Path -Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    New-ItemProperty -Path $path -Name "DisableSearchBoxSuggestions" -Value 1 -PropertyType DWord -Force | Out-Null
}
DisableSearchonStartMenu

Write-Output "Configuring Media..."

function UninstallMediaPlayer {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    try {
        Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -eq "WindowsMediaPlayer" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
        Get-WindowsCapability -Online | Where-Object { $_.Name -like "Media.WindowsMediaPlayer*" } | Remove-WindowsCapability -Online | Out-Null
    }
    catch {
        Write-Warning "❌ Failed to uninstall Windows Media Player (yuk!): $($_.Exception.Message)"
    }
}
UninstallMediaPlayer

#Requires -RunAsAdministrator
#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$LogPath = (Join-Path $env:ProgramData 'Config-Normal-Machine.log'),

    [Parameter()]
    [switch]$NoTranscript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Faster web downloads (PS 5.1 progress UI is extremely slow) and force TLS 1.2.
$ProgressPreference = 'SilentlyContinue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Verbose "Could not set TLS 1.2: $($_.Exception.Message)"
}

if (-not $NoTranscript) {
    try {
        $logDir = Split-Path -Path $LogPath -Parent
        if ($logDir -and -not (Test-Path -Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Start-Transcript -Path $LogPath -Append -ErrorAction Stop | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        Write-Warning "Could not start transcript at '$LogPath': $($_.Exception.Message)"
        $script:TranscriptStarted = $false
    }
}

## Current Status: Global Secure Access Client (windows)
## ==> IPv4 is preferred and it suggested you disabled IPv6 is you have issues: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health
## ==> DNS over HTTP not supported: https://learn.microsoft.com/en-us/entra/global-secure-access/troubleshoot-global-secure-access-client-diagnostics-health-check#dns-over-https-not-supported
## ==> QUIC is not supported for Internet Access, but is supported for Private Access and Microsoft 365 workloads.
## These changes won't be fully effective until after reboot.
function CreateIfNotExists {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
}

function Set-RegistryValue {
    <#
        .SYNOPSIS
            Idempotently create or update a registry value.

        .DESCRIPTION
            Robust replacement for the original Set-RegistryValue.
            - Accepts hive aliases (HKLM, HKCU, HKCR, HKU, HKCC, plus the long
              HKEY_* names and trailing ':' forms).
            - Accepts type aliases in any case (String, DWORD, REG_SZ, ...).
            - Coerces $Value to the requested registry type.
            - Creates parent keys as needed, including deep paths.
            - Detects existing values: returns 'Unchanged' when value+type
              already match, 'Updated' when overwriting, 'Created' for new
              values, 'Failed' on error.
            - Re-creates the value when the existing kind doesn't match the
              requested kind (PowerShell can't change kind in place).
            - Honours -WhatIf / -Confirm.
            - Never throws (returns a status object); callers can opt into
              throwing via -ErrorAction Stop on Write-Error if needed.

        .EXAMPLE
            Set-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso' -Name 'Url' -Value 'https://x' -Type String

        .EXAMPLE
            Set-RegistryValue -Hive HKCU -SubKey 'Software\Foo' -Name 'Bar' -Value 1 -Type DWORD -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hive,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Key')]
        [string]$SubKey,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PropertyName')]
        [string]$Name,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [object]$Value,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PropertyType', 'Kind')]
        [string]$Type = 'String'
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $hiveMap = @{
            'HKLM' = 'HKLM'; 'HKEY_LOCAL_MACHINE' = 'HKLM'
            'HKCU' = 'HKCU'; 'HKEY_CURRENT_USER' = 'HKCU'
            'HKCR' = 'HKCR'; 'HKEY_CLASSES_ROOT' = 'HKCR'
            'HKU' = 'HKU'; 'HKEY_USERS' = 'HKU'
            'HKCC' = 'HKCC'; 'HKEY_CURRENT_CONFIG' = 'HKCC'
        }

        $typeMap = @{
            'STRING' = 'String'; 'REG_SZ' = 'String'
            'DWORD' = 'DWord'; 'REG_DWORD' = 'DWord'
            'QWORD' = 'QWord'; 'REG_QWORD' = 'QWord'
            'BINARY' = 'Binary'; 'REG_BINARY' = 'Binary'
            'MULTISTRING' = 'MultiString'; 'REG_MULTI_SZ' = 'MultiString'
            'EXPANDSTRING' = 'ExpandString'; 'REG_EXPAND_SZ' = 'ExpandString'
        }
    }

    process {
        # ---- Normalize hive ----
        $hiveKey = $Hive.Trim().TrimEnd(':').ToUpperInvariant()
        if (-not $hiveMap.ContainsKey($hiveKey)) {
            return [pscustomobject]@{
                Path   = "$Hive\$SubKey"
                Name   = $Name
                Type   = $Type
                Status = 'Failed'
                Error  = "Unsupported hive '$Hive'. Use HKLM, HKCU, HKCR, HKU or HKCC."
            }
        }
        $resolvedHive = $hiveMap[$hiveKey]

        # ---- Normalize subkey (strip drive prefixes, leading slashes, swap /) ----
        $cleanSub = $SubKey.Trim().Replace('/', '\')
        $cleanSub = $cleanSub -replace '^(HKLM|HKCU|HKCR|HKU|HKCC):\\?', ''
        $cleanSub = $cleanSub -replace '^(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG)\\', ''
        $cleanSub = $cleanSub.TrimStart('\')

        # ---- Normalize type ----
        $typeKey = $Type.Trim().ToUpperInvariant()
        if ($typeMap.ContainsKey($typeKey)) {
            $resolvedType = $typeMap[$typeKey]
        } else {
            return [pscustomobject]@{
                Path   = "${resolvedHive}:\$cleanSub"
                Name   = $Name
                Type   = $Type
                Status = 'Failed'
                Error  = "Unsupported registry type '$Type'."
            }
        }

        $path = "${resolvedHive}:\$cleanSub"

        # ---- Coerce $Value into the requested registry kind ----
        try {
            $coerced =
            switch ($resolvedType) {
                'DWord' { [int]$Value }
                'QWord' { [long]$Value }
                'Binary' {
                    if ($null -eq $Value) { [byte[]]@() }
                    elseif ($Value -is [byte[]]) { , $Value }
                    elseif ($Value -is [string]) { [System.Text.Encoding]::UTF8.GetBytes([string]$Value) }
                    elseif ($Value -is [System.Collections.IEnumerable]) {
                        , ([byte[]]@($Value | ForEach-Object { [byte]$_ }))
                    } else {
                        throw 'Binary values must be a byte[] (or convertible).'
                    }
                }
                'MultiString' {
                    if ($null -eq $Value) { , [string[]]@() }
                    elseif ($Value -is [string[]]) { , $Value }
                    elseif ($Value -is [string]) { , @([string]$Value) }
                    elseif ($Value -is [System.Collections.IEnumerable]) {
                        , ([string[]]@($Value | ForEach-Object { [string]$_ }))
                    } else {
                        , @([string]$Value)
                    }
                }
                default { [string]$Value }   # String / ExpandString
            }
        } catch {
            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Type   = $resolvedType
                Status = 'Failed'
                Error  = "Value coercion failed: $($_.Exception.Message)"
            }
        }

        try {
            # ---- Ensure parent key exists ----
            if (-not (Test-Path -LiteralPath $path)) {
                if ($PSCmdlet.ShouldProcess($path, 'Create registry key')) {
                    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
                }
            }

            # ---- Discover existing value (if any) ----
            $existing = $null
            $existingKind = $null
            try {
                $regKey = Get-Item -LiteralPath $path -ErrorAction Stop
                $existingKind = $regKey.GetValueKind($Name)        # throws if missing
                $existing = $regKey.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            } catch {
                $existingKind = $null
                $existing = $null
            }

            $status = 'Created'

            if ($null -ne $existingKind) {
                $status = 'Updated'
                $existingKindString = [string]$existingKind

                if ($existingKindString -ne $resolvedType) {
                    # Different kind — must remove and recreate
                    Write-Verbose "Replacing $existingKindString value '$Name' at '$path' with $resolvedType."
                    if ($PSCmdlet.ShouldProcess("$path!$Name", "Remove existing $existingKindString value")) {
                        Remove-ItemProperty -LiteralPath $path -Name $Name -Force -ErrorAction Stop
                    }
                } else {
                    # Same kind — short-circuit if equal (idempotency)
                    $isEqual = $false
                    try {
                        $isEqual =
                        switch ($resolvedType) {
                            'Binary' { -not (Compare-Object $existing $coerced -SyncWindow 0) }
                            'MultiString' { -not (Compare-Object $existing $coerced -SyncWindow 0) }
                            default { $existing -eq $coerced }
                        }
                    } catch {
                        $isEqual = $false
                    }

                    if ($isEqual) {
                        return [pscustomobject]@{
                            Path   = $path
                            Name   = $Name
                            Value  = $coerced
                            Type   = $resolvedType
                            Status = 'Unchanged'
                        }
                    }
                }
            }

            if ($PSCmdlet.ShouldProcess("$path!$Name", "Set $resolvedType value")) {
                New-ItemProperty -LiteralPath $path -Name $Name -Value $coerced -PropertyType $resolvedType -Force -ErrorAction Stop | Out-Null
            }

            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Value  = $coerced
                Type   = $resolvedType
                Status = $status
            }
        } catch {
            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Type   = $resolvedType
                Status = 'Failed'
                Error  = $_.Exception.Message
            }
        }
    }
}
#Set-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso\MyApp' -Name 'ServerUrl' -Value 'https://example.local' -Type 'String'

# Check if winget is installed
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host 'Winget is already installed. Version:'
    winget --version
} else {
    Write-Host 'Winget is not installed. Installing...'

    # Winget ships as the "App Installer" MSIX bundle.
    $url = 'https://aka.ms/getwinget'
    $installerPath = Join-Path $env:TEMP 'AppInstaller.msixbundle'

    try {
        Write-Host "Downloading Winget installer from $url ..."
        Invoke-WebRequest -Uri $url -OutFile $installerPath -UseBasicParsing -ErrorAction Stop

        Write-Host 'Installing Winget...'
        Add-AppxPackage -Path $installerPath -ErrorAction Stop
    } catch {
        Write-Warning "Winget installation step failed: $($_.Exception.Message)"
    } finally {
        if (Test-Path -Path $installerPath) {
            Remove-Item -Path $installerPath -Force -ErrorAction SilentlyContinue
        }
    }

    # Verify installation
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host 'Winget installed successfully. Version:'
        winget --version
        winget source export
    } else {
        Write-Warning 'Winget installation could not be verified. Update Windows or install "App Installer" from the Microsoft Store and re-run this script.'
    }
}

Write-Output 'Configuring...'

function PreferIPv4 {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    ## Prefer IPv4 over IPv6 with 0x20, disable IPv6 with 0xff, revert to default with 0x00.
    $setting = 0x20
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters' -Name 'DisabledComponents' -Type DWord -Value $setting
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

    Write-Output 'Disabling Browser InBuilt DNS...'
    ## Disabled Inbuilt DNS for Microsoft Edge
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Microsoft'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'DnsOverHttpsMode' -Value 'off'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'BuiltInDnsClientEnabled' -Type DWord -Value $disableBuiltInDNS

    ## Disabled Inbuilt DNS for Google Chrome
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Google'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'DnsOverHttpsMode' -Value 'off'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'BuiltInDnsClientEnabled' -Type DWord -Value $disableBuiltInDNS
}

function DisableQUIC {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling network QUIC protocol...'
    ## QUIC is currently supported WITH Private Access and Microsoft 365 workloads but NOT in Internet Access
    $disableQUIC = 0x00
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Microsoft'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Google'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' -Name 'QuicAllowed' -Value $disableQUIC -Type DWord -Force
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Google\Chrome' -Name 'QuicAllowed' -Value $disableQUIC -Type DWord -Force
}

## Configure for MAXIMUM compatibility with Microsoft Global Secure Access and other similar (Cisco Umbrella etc..)
PreferIPv4
# UnbindIPv6
DisableInbuiltDNS
DisableQUIC

function Set-NetworkProfilesToPrivate {
    param(
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $networks = Get-NetConnectionProfile

    foreach ($net in $networks) {
        if ($net.NetworkCategory -ne 'Private') {
            Write-Host "Changing '$($net.Name)' from $($net.NetworkCategory) to Private..."
            Set-NetConnectionProfile -InterfaceIndex $net.InterfaceIndex -NetworkCategory Private -ErrorAction Stop
        } else {
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

    if (-not (Test-Path -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds')) {
        New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' | Out-Null
    }

    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' -Name 'EnableFeeds' -Type DWord -Value 0
}
DisableNewsAndInterests

function Disable-MsnFeedsAndWidgets {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Host "`nDisabling MSN Feeds, Widgets, and Search Highlights..."

    try {
        New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Force | Out-Null
        New-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -PropertyType DWord -Value 0 -Force | Out-Null
        Write-Host 'Widgets disabled via policy (HKLM).'
    } catch {
        Write-Warning "Failed to set system-wide widget policy: $($_.Exception.Message)"
    }

    try {
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'TaskbarDa' -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host 'Taskbar widgets disabled for current user.'
    } catch {
        Write-Warning "Failed to disable taskbar widgets: $($_.Exception.Message)"
    }

    try {
        $searchKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
        New-Item -Path $searchKey -Force | Out-Null
        New-ItemProperty -Path $searchKey -Name 'IsDynamicSearchBoxEnabled' -Value 0 -PropertyType DWord -Force | Out-Null
        New-ItemProperty -Path $searchKey -Name 'IsDynamicSearchBoxEnabledOnTablet' -Value 0 -PropertyType DWord -Force | Out-Null
        Write-Host 'Search highlights disabled.'
    } catch {
        Write-Warning "Failed to configure search highlights: $($_.Exception.Message)"
    }

    try {
        $feedsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds'
        New-Item -Path $feedsKey -Force -ErrorAction SilentlyContinue | Out-Null
        New-ItemProperty -Path $feedsKey -Name 'ShellFeedsTaskbarViewMode' -Value 2 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host 'Personalized content in feeds disabled.'
    } catch {
        Write-Warning "Failed to disable feeds view: $($_.Exception.Message)"
    }
}
Disable-MsnFeedsAndWidgets

function EnableLocation {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocationScripting' -ErrorAction SilentlyContinue

    $cfgKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration'
    if (-not (Test-Path -Path $cfgKey)) {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service' -Name 'Configuration' -Force | Out-Null
    }

    New-ItemProperty -Path $cfgKey -Name 'Status' -PropertyType DWord -Value 1 -Force | Out-Null
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' -Name 'Status' -Value 1

    $capCU = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location'
    if (-not (Test-Path -Path $capCU)) {
        New-Item -Path $capCU -Force | Out-Null
    }

    New-ItemProperty -Path $capCU -Name 'Value' -PropertyType String -Value 'Allow' -Force | Out-Null
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value' -Value 'Allow'

    Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value'

    Set-Service -Name lfsvc -StartupType Automatic -ErrorAction SilentlyContinue
    Restart-Service -Name lfsvc
}
# EnableLocation

function DisableFeedback {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    CreateIfNotExists -Path 'HKCU:\Software\Microsoft\Siuf\Rules'
    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Type DWord -Value 0
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'DoNotShowFeedbackNotifications' -Type DWord -Value 1
    Disable-ScheduledTask -TaskName 'Microsoft\Windows\Feedback\Siuf\DmClient' -ErrorAction SilentlyContinue | Out-Null
    Disable-ScheduledTask -TaskName 'Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload' -ErrorAction SilentlyContinue | Out-Null
}
DisableFeedback

function DisableErrorReporting {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    CreateIfNotExists -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting' -Name 'Disabled' -Type DWord -Value 1
    Disable-ScheduledTask -TaskName 'Microsoft\Windows\Windows Error Reporting\QueueReporting' -ErrorAction SilentlyContinue | Out-Null
}
DisableErrorReporting

function DisableRecoveryAndReset {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $reAgentOutput = & reagentc /info 2>&1 | Out-String
    if ($reAgentOutput -match 'Windows RE status:\s+Disabled') {
        Write-Host 'Windows RE is already disabled.'
        return
    }

    $disableOutput = & reagentc /disable 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        if ($disableOutput -match 'Windows RE is already disabled') {
            Write-Host 'Windows RE is already disabled.'
            return
        }
        throw "Failed to disable Windows RE. Output: $disableOutput"
    }
    Write-Host 'Windows RE disabled.'
}
DisableRecoveryAndReset

function DisableAutoplay {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disable Autoplay...'
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Type DWord -Value 1
    Set-RegistryValue -Hive HKCU -SubKey 'Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1 -Type 'DWORD'
}
DisableAutoplay

function DisableAutorun {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disable Autorun...'

    if (-not (Test-Path -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer')) {
        New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' | Out-Null
    }

    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoDriveTypeAutoRun' -Type DWord -Value 255
}
DisableAutorun

function EnableNTFSLongPaths {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Enabling NTFS Long Paths...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Type DWord -Value 1
}
EnableNTFSLongPaths

function DisableNTFSLastAccess {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Turning off NTFS Last Access Time...'
    fsutil behavior set DisableLastAccess 1 | Out-Null
}
DisableNTFSLastAccess

function EnableAutoRebootOnCrash {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Enabling Auto Reboot on Windows Crash...'
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'AutoReboot' -Type DWord -Value 1
}
EnableAutoRebootOnCrash

function ShowNetworkOnLockScreen {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output "Don't display network location on Lock Screen..."
    Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'DontDisplayNetworkSelectionUI' -ErrorAction SilentlyContinue
}
ShowNetworkOnLockScreen

function DisableAccessibilityKeys {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabiling Accessability Keys...'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Type String -Value '506'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Type String -Value '58'
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Type String -Value '122'
}

function Set-SoundSchemeNone {
    [CmdletBinding()]
    param()

    Write-Output 'Setting Sound Scheme to None...'
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $SoundScheme = '.None'
    $SchemesPath = 'HKCU:\AppEvents\Schemes'
    $AppsPath = 'HKCU:\AppEvents\Schemes\Apps'

    if (-not (Test-Path $AppsPath)) {
        throw "Registry path not found: $AppsPath"
    }

    Get-ChildItem -Path $AppsPath | ForEach-Object {
        $AppKey = $_.PSPath

        Get-ChildItem -Path $AppKey | ForEach-Object {
            $EventKey = $_.PSPath

            $NoneKey = Join-Path $EventKey '.None'
            $CurrentKey = Join-Path $EventKey '.Current'

            if (-not (Test-Path $NoneKey)) {
                New-Item -Path $NoneKey -Force | Out-Null
            }

            if (-not (Test-Path $CurrentKey)) {
                New-Item -Path $CurrentKey -Force | Out-Null
            }

            # None means no sound, so default value should be empty.
            Set-Item -Path $NoneKey -Value ''
            Set-Item -Path $CurrentKey -Value ''
        }
    }

    # Set selected Windows sound scheme to "No Sounds"
    Set-Item -Path $SchemesPath -Value $SoundScheme
}
Set-SoundSchemeNone

function DisableStartupSound {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling Startup Sound...'
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI\BootAnimation' -Name 'DisableStartupSound' -Type DWord -Value 1
}
DisableStartupSound

function DisableVerboseStatus {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling Verbose Status...'
    if ((Get-CimInstance -Class 'Win32_OperatingSystem').ProductType -eq 1) {
        Remove-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'VerboseStatus' -ErrorAction SilentlyContinue
    } else {
        Set-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'VerboseStatus' -Type DWord -Value 0
    }
}
DisableVerboseStatus

function DisableSharingWizard {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Disabling Sharing Wizard...'
    CreateIfNotExists -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'SharingWizardOn' -Type DWord -Value 0
}
DisableSharingWizard

function ShowThisPCOnDesktop {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output "Showing 'This PC' on Desktop..."
    if (-not (Test-Path -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu')) {
        New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu' -Force | Out-Null
    }

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu' -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Type DWord -Value 0

    if (-not (Test-Path -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel')) {
        New-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' -Force | Out-Null
    }

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel' -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Type DWord -Value 0
}
ShowThisPCOnDesktop

function HideMusicFromExplorer {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'Run this function from an elevated PowerShell session (Run as Administrator).'
        return
    }

    $musicGuid = '{a0c69a99-21c8-4671-8703-7934162fcf1d}'
    $propertyBagKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag"
    $wowPropertyBagKey = "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Explorer\FolderDescriptions\$musicGuid\PropertyBag"
    $valueName = 'ThisPCPolicy'

    if (-not (Test-Path -Path $propertyBagKey)) {
        New-Item -Path $propertyBagKey -Force | Out-Null
    }

    if (-not (Test-Path -Path $wowPropertyBagKey)) {
        New-Item -Path $wowPropertyBagKey -Force | Out-Null
    }

    Set-ItemProperty -Path $propertyBagKey -Name $valueName -Type String -Value 'Hide'
    Set-ItemProperty -Path $wowPropertyBagKey -Name $valueName -Type String -Value 'Hide'

    Write-Host "Music folder will be hidden from 'This PC' permanently." -ForegroundColor Green
}
HideMusicFromExplorer

function DisableIEandEdgeWarnings {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path 'HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing')) {
        New-Item -Path 'HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing' -Force | Out-Null
    }

    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Internet Explorer\TabbedBrowsing' -Name 'WarnOnClose' -Type DWord -Value 0

    if (-not (Test-Path -Path 'HKCU:\Software\Policies\Microsoft\Edge')) {
        New-Item -Path 'HKCU:\Software\Policies\Microsoft\Edge' -Force | Out-Null
    }

    Set-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Edge' -Name 'RestoreOnStartup' -Type DWord -Value 1
}
DisableIEandEdgeWarnings

function Set-EdgeNoFirstRun {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $edgePolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'

    if (-not (Test-Path -Path $edgePolicyPath)) {
        New-Item -Path $edgePolicyPath -Force | Out-Null
    }

    $policies = @{
        'HideFirstRunExperience'               = 1
        'ImportFavorites'                      = 0
        'AutoImportAtFirstRun'                 = 0
        'BrowserAddProfileEnabled'             = 0
        'DefaultBrowserSettingEnabled'         = 0
        'BrowserSignin'                        = 2
        'WebToBrowserSignInEnabled'            = 1
        'SeamlessWebToBrowserSignInEnabled'    = 1
        'ConfigureOnPremisesAccountAutoSignIn' = 1
        'ForceSync'                            = 1
    }

    foreach ($policy in $policies.GetEnumerator()) {
        New-ItemProperty -Path $edgePolicyPath -Name $policy.Key -Value $policy.Value -PropertyType DWord -Force | Out-Null
    }

    $userCtaPath = 'HKCU:\Software\Microsoft\Edge\SignIn'
    if (-not (Test-Path -Path $userCtaPath)) {
        New-Item -Path $userCtaPath -Force | Out-Null
    }

    New-ItemProperty -Path $userCtaPath -Name 'SignInCtaShownCount' -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host 'Microsoft Edge configured to skip first run, auto sign-in, and force sync (subject to device/account setup).'
}
Set-EdgeNoFirstRun

function Hide-WindowsSecurityFamilyOptions {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $keyPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender Security Center\Family options'
    $valueName = 'UILockdown'

    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Warning 'Run this function as Administrator to modify HKLM.'
        return
    }

    if (-not (Test-Path -Path $keyPath)) {
        New-Item -Path $keyPath -Force | Out-Null
    }

    New-ItemProperty -Path $keyPath -Name $valueName -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "'Family options' hidden in Windows Security app." -ForegroundColor Green
}
Hide-WindowsSecurityFamilyOptions

function DisableMediaSharing {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer')) {
        New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer' -Force | Out-Null
    }

    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsMediaPlayer' -Name 'PreventLibrarySharing' -Type DWord -Value 1
    Write-Host 'Disabled Media Sharing' -ForegroundColor Green
}
DisableMediaSharing

function Disable-WindowsGaming {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Ensure-Key {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Path
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
    }

    function Set-Dword {
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

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

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

    Write-Verbose 'Stopping Game Bar processes if running...'
    try {
        Get-Process -Name XboxGameBar, GameBar, GameBarFT -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        $summary.GameBarProcessesStopped = $true
    } catch {
        $summary.Notes += "Could not stop Game Bar processes: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
        $summary.GameDVREnforcedPolicy = $true
    } catch {
        $summary.Notes += "Policy write failed: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
        $summary.GameDVREnabledHKCU = $true
    } catch {
        $summary.Notes += "HKCU GameDVR write failed: $($_.Exception.Message)"
    }

    try {
        Set-Dword -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
        $summary.GameConfigDvrDisabled = $true
    } catch {
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
    } catch {
        $summary.Notes += "GameBar settings write failed: $($_.Exception.Message)"
    }

    $runCU = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    foreach ($name in 'XboxGameBar', 'GameBar') {
        try {
            if (Get-ItemProperty -Path $runCU -Name $name -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $runCU -Name $name -Force -ErrorAction SilentlyContinue
                $summary.RunEntriesRemoved += $name
            }
        } catch {
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
            } catch {
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
        } catch {
            $summary.Notes += "Task disable failed for $($task.Path)$($task.Name): $($_.Exception.Message)"
        }
    }

    try {
        # Attempt to remove (not re-register) the Xbox Gaming Overlay for the current user.
        # Note: this app is provisioned by Windows; it may reappear after major updates.
        Get-AppxPackage -Name 'Microsoft.XboxGamingOverlay' -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue
            } catch {
                $summary.Notes += "Overlay removal skipped for $($_.PackageFullName): $($_.Exception.Message)"
            }
        }
    } catch {
        $summary.Notes += "Overlay package handling skipped: $($_.Exception.Message)"
    }

    Write-Verbose 'Done. Some changes apply after sign-out or Explorer restart.'
    return [pscustomobject]$summary
}
Disable-WindowsGaming | Out-Null

function Set-SettingsPageVisibility {
    [CmdletBinding(DefaultParameterSetName = 'Get')]
    param(
        [Parameter(ParameterSetName = 'Set')]
        [Parameter(ParameterSetName = 'Add')]
        [ValidateSet('Hide', 'ShowOnly')]
        [string] $Mode,

        [Parameter(ParameterSetName = 'Set', Mandatory)]
        [Parameter(ParameterSetName = 'Add', Mandatory)]
        [Parameter(ParameterSetName = 'Remove', Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Pages,

        [Parameter(ParameterSetName = 'Add', Mandatory)]
        [switch] $Add,

        [Parameter(ParameterSetName = 'Remove', Mandatory)]
        [switch] $Remove,

        [Parameter(ParameterSetName = 'Clear', Mandatory)]
        [switch] $Clear,

        [Parameter(ParameterSetName = 'Get')]
        [switch] $Get
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $KeyPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    $ValueName = 'SettingsPageVisibility'

    function Test-IsAdministrator {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)

        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Get-CurrentValue {
        if (-not (Test-Path -Path $KeyPath)) {
            return $null
        }

        try {
            return Get-ItemPropertyValue -Path $KeyPath -Name $ValueName -ErrorAction Stop
        } catch [System.Management.Automation.ItemNotFoundException] {
            return $null
        } catch {
            return $null
        }
    }

    function ConvertFrom-SettingsPageVisibilityValue {
        param(
            [AllowNull()]
            [string] $Value
        )

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return [pscustomobject]@{
                Mode  = $null
                Pages = @()
            }
        }

        $parts = $Value.Split(':', 2)
        $modeText = $parts[0].Trim().ToLowerInvariant()

        $parsedMode = switch ($modeText) {
            'hide' { 'Hide' }
            'showonly' { 'ShowOnly' }
            default { $null }
        }

        $parsedPages = @()

        if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $parsedPages = $parts[1].Split(';') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        }

        [pscustomobject]@{
            Mode  = $parsedMode
            Pages = @($parsedPages)
        }
    }

    function ConvertTo-SettingsPageVisibilityValue {
        param(
            [Parameter(Mandatory)]
            [ValidateSet('Hide', 'ShowOnly')]
            [string] $Mode,

            [Parameter(Mandatory)]
            [string[]] $Pages
        )

        $cleanPages = $Pages |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

        if ($cleanPages.Count -eq 0) {
            return $null
        }

        switch ($Mode) {
            'Hide' { return "hide:$($cleanPages -join ';')" }
            'ShowOnly' { return "showonly:$($cleanPages -join ';')" }
        }
    }

    $currentRaw = Get-CurrentValue
    $current = ConvertFrom-SettingsPageVisibilityValue -Value $currentRaw

    if ($PSCmdlet.ParameterSetName -eq 'Get') {
        return [pscustomobject]@{
            Mode  = $current.Mode
            Pages = $current.Pages
            Raw   = $currentRaw
            Path  = "$KeyPath\$ValueName"
        }
    }

    if (-not (Test-IsAdministrator)) {
        throw 'Run elevated as Administrator to modify HKLM.'
    }

    if (-not (Test-Path -Path $KeyPath)) {
        New-Item -Path $KeyPath -Force | Out-Null
    }

    if ($Clear) {
        Remove-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'Set') {
        if ([string]::IsNullOrWhiteSpace($Mode)) {
            throw 'Use -Mode Hide or -Mode ShowOnly when setting the full page list.'
        }

        $newRaw = ConvertTo-SettingsPageVisibilityValue -Mode $Mode -Pages $Pages

        if ([string]::IsNullOrWhiteSpace($newRaw)) {
            Remove-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
            return
        }

        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }

    if ($Add) {
        $targetMode = $current.Mode

        if ([string]::IsNullOrWhiteSpace($targetMode)) {
            if ([string]::IsNullOrWhiteSpace($Mode)) {
                throw 'No existing SettingsPageVisibility value. Use -Add with -Mode Hide or -Mode ShowOnly.'
            }

            $targetMode = $Mode
        }

        $combinedPages = @($current.Pages + $Pages)

        $newRaw = ConvertTo-SettingsPageVisibilityValue -Mode $targetMode -Pages $combinedPages
        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }

    if ($Remove) {
        if ([string]::IsNullOrWhiteSpace($current.Mode)) {
            return
        }

        $removeLookup = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        foreach ($page in $Pages) {
            [void] $removeLookup.Add($page.Trim())
        }

        $remainingPages = @(
            $current.Pages | Where-Object {
                -not $removeLookup.Contains($_)
            }
        )

        $newRaw = ConvertTo-SettingsPageVisibilityValue -Mode $current.Mode -Pages $remainingPages

        if ([string]::IsNullOrWhiteSpace($newRaw)) {
            Remove-ItemProperty -Path $KeyPath -Name $ValueName -ErrorAction SilentlyContinue
            return
        }

        New-ItemProperty -Path $KeyPath -Name $ValueName -PropertyType String -Value $newRaw -Force | Out-Null
        return
    }
}

#Set-SettingsPageVisibility -Get $true | Format-List

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

#Set-SettingsPageVisibility -Get $true | Format-List

function EnableClipboardHistorySync {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Enabling Clipboard history...'
    $regPath = 'Software\Microsoft\Clipboard'
    Set-RegistryValue -Hive HKCU -SubKey $regPath -Name 'EnableClipboardHistory' -Value 1 -Type 'DWORD'
    Set-RegistryValue -Hive HKCU -SubKey $regPath -Name 'CloudClipboardAutomaticUpload' -Value 0 -Type 'DWORD'
    Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name AllowClipboardHistory -ErrorAction SilentlyContinue
    Write-Output 'Clipboard history has been enabled.'
}
EnableClipboardHistorySync

function Set-DefaultTerminalToWindowsTerminal {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$AllUsers = $false
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Write-Output 'Settings Default Terminal to be MSTerminal...'
    
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
        Write-Warning 'Windows Terminal not found. Install from Microsoft Store or winget, then re-run.'
        return $false
    }

    function Set-Delegation {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$Root,

            [Parameter(Mandatory = $true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubKey
        )

        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

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

        if ($AllUsers) {
            foreach ($target in $targets) {
                Set-Delegation -Root $hklm -SubKey $target
            }
        }

        Write-Host 'Default terminal set to Windows Terminal.'
        return $true
    } catch {
        Write-Warning "Failed to set default terminal: $($_.Exception.Message)"
        return $false
    }
}
Write-Output '**Finished Normal Machine config script**'

if ($script:TranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
}

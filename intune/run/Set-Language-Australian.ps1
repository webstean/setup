#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    Write-Host "[$Level] $Message"
}

function Wait-WindowsUptime {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 1440)]
        [int]$Minutes = 10,

        [ValidateRange(1, 60)]
        [int]$CheckIntervalSeconds = 5
    )

    if ($Minutes -eq 0) {
        return
    }

    $targetSeconds = $Minutes * 60
    Write-Status -Message "Waiting for system uptime to reach at least $Minutes minute(s)..."

    while ($true) {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        $seconds = [int]$uptime.TotalSeconds

        if ($seconds -ge $targetSeconds) {
            Write-Status -Message "Uptime reached $([math]::Round($seconds / 60, 1)) minute(s)."
            break
        }

        $remaining = $targetSeconds - $seconds
        Write-Status -Message "Current uptime: $([math]::Round($seconds / 60, 1)) min; waiting $remaining second(s) more..."
        Start-Sleep -Seconds ([Math]::Min($CheckIntervalSeconds, $remaining))
    }
}

function Install-WindowsCapabilityIfPresent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LanguageTag,

        [Parameter(Mandatory)]
        [ValidateSet('Basic', 'OCR', 'Speech', 'TextToSpeech', 'Handwriting')]
        [string]$CapabilityType,

        [bool]$Required = $false
    )

    $pattern = "Language.$CapabilityType~~~$LanguageTag~*"
    $capability = Get-WindowsCapability -Online | Where-Object { $_.Name -like $pattern } | Select-Object -First 1

    if (-not $capability) {
        $message = "Capability type '$CapabilityType' is not published for $LanguageTag on this OS image."
        if ($Required) {
            throw $message
        }

        Write-Status -Level 'WARN' -Message $message
        return $false
    }

    if ($capability.State -eq 'Installed') {
        Write-Status -Message "$($capability.Name) already installed."
        return $true
    }

    Write-Status -Message "Installing $($capability.Name)..."
    $null = Add-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop

    $installedCapability = Get-WindowsCapability -Online -Name $capability.Name -ErrorAction Stop
    if ($installedCapability.State -ne 'Installed') {
        throw "Capability '$($capability.Name)' did not reach Installed state. Current state: $($installedCapability.State)."
    }

    return $true
}

function Test-LanguageInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LanguageTag
    )

    if (Get-Command Get-InstalledLanguage -ErrorAction SilentlyContinue) {
        $installed = Get-InstalledLanguage | Where-Object { $_.LanguageId -eq $LanguageTag }
        return $null -ne $installed
    }

    $languageList = Get-WinUserLanguageList -ErrorAction SilentlyContinue
    return $null -ne ($languageList | Where-Object { $_.LanguageTag -eq $LanguageTag })
}

function Set-OneCoreSpeechDefaults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LanguageTag
    )

    $speechKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings'
    if (-not (Test-Path -LiteralPath $speechKey)) {
        $null = New-Item -Path $speechKey -Force
    }

    $null = New-ItemProperty -Path $speechKey -Name 'SpeechLanguage' -Value $LanguageTag -PropertyType String -Force

    $voicePrefix = 'MSTTS_V110_' + $LanguageTag.Replace('-', '')
    $voiceKey = 'HKLM:\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens'
    $voice = Get-ChildItem -Path $voiceKey -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like "$voicePrefix*" } |
        Select-Object -First 1

    if (-not $voice) {
        Write-Status -Level 'WARN' -Message "No OneCore default voice token found for $LanguageTag."
        return
    }

    $sapiVoicesKey = 'HKCU:\Software\Microsoft\Speech\Voices'
    if (-not (Test-Path -LiteralPath $sapiVoicesKey)) {
        $null = New-Item -Path $sapiVoicesKey -Force
    }

    $voiceTokenValue = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\' + $voice.PSChildName
    $null = New-ItemProperty -Path $sapiVoicesKey -Name 'DefaultTokenId' -Value $voiceTokenValue -PropertyType String -Force
}

function Enable-LanguagePack {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$LanguageTag = 'en-AU',

        [ValidateRange(0, 1440)]
        [int]$MinimumUptimeMinutes = 10
    )

    Wait-WindowsUptime -Minutes $MinimumUptimeMinutes

    $cultureInfo = [System.Globalization.CultureInfo]::GetCultureInfo($LanguageTag)
    Write-Status -Message "LCID: $($cultureInfo.LCID)"
    Write-Status -Message "Display name: $($cultureInfo.DisplayName)"
    Write-Status -Message "Language tag: $LanguageTag"

    try {
        if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
            Write-Status -Message "Invoking Install-Language for $LanguageTag..."
            $null = Install-Language -Language $LanguageTag -CopyToSettings -ErrorAction Stop
        } else {
            Write-Status -Level 'WARN' -Message 'Install-Language cmdlet not found; continuing with capability-based installation only.'
        }

        $mandatoryCapabilityTypes = @('Basic')
        $optionalCapabilityTypes = @('OCR', 'Speech', 'TextToSpeech', 'Handwriting')

        foreach ($capabilityType in $mandatoryCapabilityTypes) {
            $null = Install-WindowsCapabilityIfPresent -LanguageTag $LanguageTag -CapabilityType $capabilityType -Required $true
        }

        foreach ($capabilityType in $optionalCapabilityTypes) {
            $null = Install-WindowsCapabilityIfPresent -LanguageTag $LanguageTag -CapabilityType $capabilityType
        }

        if (-not (Test-LanguageInstalled -LanguageTag $LanguageTag)) {
            throw "Language '$LanguageTag' is still not reported as installed after setup completed."
        }

        Write-Status -Message 'Applying user and system language settings...'
        Set-WinUILanguageOverride -Language $LanguageTag -ErrorAction Stop
        Set-Culture -CultureInfo $LanguageTag -ErrorAction Stop

        $languageList = New-WinUserLanguageList -Language $LanguageTag -ErrorAction Stop
        Set-WinUserLanguageList -LanguageList $languageList -Force -ErrorAction Stop
        Set-WinSystemLocale -SystemLocale $LanguageTag -ErrorAction Stop
        Set-WinHomeLocation -GeoId 12 -ErrorAction SilentlyContinue

        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
        }

        Set-OneCoreSpeechDefaults -LanguageTag $LanguageTag

        $summary = @{
            LanguageTag = $LanguageTag
            Installed = (Test-LanguageInstalled -LanguageTag $LanguageTag)
            UserCulture = (Get-Culture).Name
            SystemLocale = (Get-WinSystemLocale).Name
            UILanguageOverride = (Get-WinUILanguageOverride).Name
        }

        Write-Output $summary
        Write-Status -Message "$LanguageTag has been installed and applied. Sign out or restart if the shell does not pick up the new UI language immediately."
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match '0x800f0954|0x800f081e|0x800f0950') {
            $message += ' This often means the language feature source is unavailable through Windows Update, WSUS, or the local image.'
        }

        Write-Error "Failed to install language pack for ${LanguageTag}: $message"
        throw
    }
}
Enable-LanguagePack -LanguageTag 'en-AU'

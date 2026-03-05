function Wait-WindowsUptime {
    $Minutes = 10
    $targetSeconds = $Minutes * 60
    $CheckInterval = 1
    Write-Host "[INFO] Waiting for system uptime to reach $Minutes minute(s)..."

    while ($true) {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $seconds = [int]$uptime.TotalSeconds

        if ($seconds -ge $targetSeconds) {
            # Write-Host "[INFO] Uptime reached $([math]::Round($seconds/60,1)) minute(s)."
            break
        }

        $remaining = $targetSeconds - $seconds
        Write-Host "[INFO] Current uptime: $([math]::Round($seconds/60,1)) min — waiting $remaining s more..."
        Start-Sleep -Seconds ([Math]::Min($CheckInterval, $remaining))
    }
    return $true
}

#Requires -RunAsAdministrator
function Enable-AustralianLanguagePack {
    [CmdletBinding()]
    param()

    if (Get-Command Wait-WindowsUptime -ErrorAction SilentlyContinue) {
        Wait-WindowsUptime
    }

    $LanguageTag = "en-AU" # Australian English

    $ci = [System.Globalization.CultureInfo]::GetCultureInfo($LanguageTag)
    $lcid        = $ci.LCID
    $DisplayName = $ci.DisplayName
    $Language    = $ci.Name

    Write-Host "lcid        = $lcid"        # 3081
    Write-Host "DisplayName = $DisplayName" # English (Australia)
    Write-Host "Language    = $Language"    # en-AU
    Write-Output "Installing language pack: $DisplayName"

    try {
        # Install language capabilities (FODs)
        $capabilities = @(
            "Language.Basic~~~$Language~0.0.1.0",
            "Language.Speech~~~$Language~0.0.1.0",
            "Language.TextToSpeech~~~$Language~0.0.1.0",
            "Language.OCR~~~$Language~0.0.1.0"
            # Optional:
            "Language.Handwriting~~~$Language~0.0.1.0"
        )

        foreach ($capability in $capabilities) {
            Write-Output "Ensuring feature: $capability"
            $cap = Get-WindowsCapability -Online -Name $capability -ErrorAction Stop
            if ($cap.State -ne 'Installed') {
                Add-WindowsCapability -Online -Name $capability -ErrorAction Stop | Out-Null
            } else {
                Write-Host "$capability already INSTALLED"
            }
        }

        # Install language pack + copy to system/new user
        if (Get-Command Install-Language -ErrorAction SilentlyContinue) {
            Install-Language -Language $Language -CopyToSettings -ErrorAction Stop | Out-Null
        } else {
            throw "Install-Language cmdlet not found. Ensure Windows 11 / International module support."
        }

        Write-Host "✅ Language installation completed."

        # User UI language (logoff required)
        Set-WinUILanguageOverride -Language $Language -ErrorAction Stop

        # Culture for formats (dates/numbers)
        Set-Culture -CultureInfo $Language -ErrorAction Stop

        # User language list + input methods
        $LangList = New-WinUserLanguageList -Language $Language -ErrorAction Stop
        Set-WinUserLanguageList -LanguageList $LangList -Force -ErrorAction Stop

        # System locale (affects non-Unicode apps)
        Set-WinSystemLocale -SystemLocale $Language -ErrorAction Stop

        # Copy intl settings to Welcome screen + new users (Windows 10/11)
        if (Get-Command Copy-UserInternationalSettingsToSystem -ErrorAction SilentlyContinue) {
            Copy-UserInternationalSettingsToSystem -WelcomeScreen $true -NewUser $true -ErrorAction Stop
        }

        # Speech language (OneCore)
        $speechKey = 'HKCU:\Software\Microsoft\Speech_OneCore\Settings'
        if (-not (Test-Path $speechKey)) { New-Item -Path $speechKey -Force | Out-Null }
        New-ItemProperty -Path $speechKey -Name 'SpeechLanguage' -Value $Language -PropertyType String -Force | Out-Null

        # Optional: set a default OneCore voice if present
        $voiceTokenName = "MSTTS_V110_enAU_CatherineM"
        $voiceTokenHklm = "HKLM:\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\$voiceTokenName"
        $voiceTokenValue = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens\$voiceTokenName"

        if (Test-Path $voiceTokenHklm) {
            $sapiVoicesKey = "HKCU:\Software\Microsoft\Speech\Voices"
            if (-not (Test-Path $sapiVoicesKey)) { New-Item -Path $sapiVoicesKey -Force | Out-Null }

            # DefaultTokenId expects the "HKEY_LOCAL_MACHINE\..." style string
            New-ItemProperty -Path $sapiVoicesKey -Name "DefaultTokenId" -Value $voiceTokenValue -PropertyType String -Force | Out-Null
        }

        Write-Output "$Language pack (and features) has been installed and enabled."

        if (Get-Command Get-Language -ErrorAction SilentlyContinue) {
            Get-Language
        }

        Write-Output "You may need to sign out and sign back in for the change to take effect."
    }
    catch {
        Write-Error "Failed to install language pack: $($_.Exception.Message)"
        throw
    }
}

# If this exists in your profile/module, keep it; otherwise remove it
if (Get-Command SetAustraliaLocation -ErrorAction SilentlyContinue) {
    SetAustraliaLocation
}
EnableAustralianLanguagePack

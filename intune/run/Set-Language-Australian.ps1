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
	
		## Install the language pack with UI, system, and input preferences
		$job = Install-Language -Language $Language -CopyToSettings -ErrorAction SilentlyContinue
		# Wait until the installation completes
		$job | Wait-Job
		Receive-Job $job -ErrorAction SilentlyContinue
		Write-Host "✅ Language installation completed."

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

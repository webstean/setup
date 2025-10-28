
## https://raw.githubusercontent.com/lscph1929/scripts/refs/heads/main/profile/good_profile.ps1

function Update-Profile-Force {
    # Define the remote URL
    $url = 'https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/good_profile.ps1'

    # Ensure the profile directory exists
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Download and overwrite the profile
    Invoke-WebRequest -Uri $url -OutFile $PROFILE -UseBasicParsing
    Write-Host "✅ Profile updated at $PROFILE"
}
#Update-Profile-Force


## If Windows Powershell
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Write-Host "Ignoring Profile - as this is Windows PowerShell"
    return $true | Out-Null
}

## FullLanguage: No restrictions (default in most PowerShell sessions)
## ConstrainedLanguage: Limited .NET access (used in AppLocker/WDAC scenarios)
## RestrictedLanguage: Very limited (e.g., only basic expressions)
## NoLanguage: No scripting allowed at all
$acceptableModes = @("FullLanguage")
$unacceptableModes = @("ConstrainedLanguage", "RestrictedLanguage", "NoLanguage")
$currentMode = $ExecutionContext.SessionState.LanguageMode.ToString()
$IsLanguagePermissive = $currentMode -in $acceptableModes

$UTF8 = $false
if ($IsLanguagePermissive) {
    Write-Host ("Setting PowerShell to UTF-8 output encoding...")
    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
    #$UTF8 = $true
} 
if ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP -eq '65001') { 
    $UTF8 = $true
}

# Get the current language mode
if ($IsLanguagePermissive) {
    if ($UTF8) {
        Write-Host "✅ PowerShell Language Mode is: $currentMode"
    } else {
        Write-Host "PowerShell Language Mode is: $currentMode"
    }
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    if ($UTF8) {
        Write-Host "❌ PowerShell Language Mode is: $currentMode (most advanced things won't work here)"
    } else {
        Write-Host "PowerShell Language Mode is: $currentMode (most advanced things won't work here)"
    }
    $IsAdmin = (whoami /groups | Select-String "S-1-5-32-544") -ne $null
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
} else {
    $InstallScope = 'CurrentUser'
}

function Set-MSTerminalBackground {
    param (
        [string]$settingsfile = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        [string]$backup_settingsfile = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.admin",
        [string]$BackgroundColor = "#993755" ## "#994755" "#506950ff" "#000000"
    )

    ## Forget it if this is Windows PowerShell, because ConvertFrom-Json does not support enough depth edit config file
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return }

    $ErrorActionPreference = 'Ignore'
    try {

        ## Check if the settings file exists
        if (-not (Test-Path $settingsfile  -PathType Leaf)) {
            return $false
        }

        ## Read the settings
        ## -Depth 10 - removed for compatibility with earlier versions
        $json = Get-Content -Path $settingsfile -Raw | ConvertFrom-Json -Depth 10

        ## Ensure the profiles object exists
        if (-Not $json.profiles) {
            $json.profiles = @{}
        }

        ## Ensure the profiles.defaults section exists
        if (-Not $json.profiles.defaults) {
            $json.profiles.defaults = @{}
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["background"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "background" -Value $BackgroundColor
        }
        else {
            $json.profiles.defaults.background = $BackgroundColor
        }
        if (-NOT $json.profiles.defaults.PSObject.Properties["useAcrylic"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "useAcrylic" -Value $true
        }
        else {
            $json.profiles.defaults.useAcrylic = $true
        }
        ## Save the updated JSON content back to the settings file
        ## -Depth 10 - removed for compatibility with earlier versions
        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsfile -Encoding UTF8
    }
    catch {
        Write-Host "Error updating settings: $_"
        return $false
    }
}

# The following code should be outside the function
if ($IsAdmin) {
    Write-Output "Admin Shell - be careful!"
    #Set-MSTerminalBackground -BackgroundColor "#993755"
} else {
    Write-Output "Non-Admin Shell - limited functionality"
    #Set-MSTerminalBackground -BackgroundColor "#000000"
}

#use only for PowerShell and VS Code
#if ($host.Name -eq 'ConsoleHost' -or $host.Name -eq 'Visual Studio Code Host' ) {
function Initialize-PSReadLineSmart {
    <#
    .SYNOPSIS
        Configure PSReadLine predictively, handling different versions at runtime.

    .DESCRIPTION
        - Loads the newest available PSReadLine.
        - Enables prediction from History on any version that supports it.
        - If running PowerShell 7.2+ AND Az.Tools.Predictor is installed, switches to HistoryAndPlugin.
        - Chooses an appropriate view style (Inline if supported; else List; else skips).
        - Adds helpful keybindings when supported.
        - Never throws on older builds; degrades gracefully.

    .PARAMETER ViewStyle
        Preferred prediction view. One of: Auto, Inline, List. Default: Auto.
        Auto = Inline if supported, else List if supported, else skip.

    .PARAMETER UsePluginIfAvailable
        If true (default), and running on PowerShell 7.2+ with Az.Tools.Predictor installed,
        sets PredictionSource = HistoryAndPlugin.

    .OUTPUTS
        PSCustomObject summarizing what was applied.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','Inline','List')]
        [string]$ViewStyle = 'Auto',
        [bool]$UsePluginIfAvailable = $true
    )

    if ( -not ($IsLanguagePermissive)) { return }

    if (-not ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15)) { return }

    $result = [pscustomobject]@{
        PSVersion            = $PSVersionTable.PSVersion.ToString()
        PSEdition            = $PSVersionTable.PSEdition
        PSReadLineVersion    = $null
        PredictionEnabled    = $false
        PredictionSource     = $null
        PredictionViewStyle  = $null
        KeybindingsApplied   = @()
        Notes                = @()
    }

    # 1) Load newest PSReadLine available (quietly)
    $rl = Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $rl) {
        $result.Notes += "PSReadLine not installed; skipping configuration."
        return $result
    }
    try {
        Import-Module $rl -ErrorAction Stop
        $result.PSReadLineVersion = (Get-Module PSReadLine).Version.ToString()
    } catch {
        $result.Notes += "Failed to import PSReadLine: $($_.Exception.Message)"
        return $result
    }

    # Helpers to probe capability rather than assume version thresholds
    $setOpt = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
    $hasPredictionSource = $false
    $hasPredictionView   = $false
    if ($setOpt) {
        $params = ($setOpt.Parameters.Keys)
        $hasPredictionSource = $params -contains 'PredictionSource'
        $hasPredictionView   = $params -contains 'PredictionViewStyle'
    }

    # 2) Decide PredictionSource
    $source = $null
    if ($hasPredictionSource) {
        # Default to History everywhere that supports it
        $source = 'History'

        # Optionally upgrade to HistoryAndPlugin when truly supported:
        # Requires PowerShell 7.2+ and Az.Tools.Predictor module available
        $isPS72Plus = ($PSVersionTable.PSVersion.Major -gt 7) -or
                      (($PSVersionTable.PSVersion.Major -eq 7) -and ($PSVersionTable.PSVersion.Minor -ge 2))
        $azPred = Get-Module Az.Tools.Predictor -ListAvailable | Select-Object -First 1

        if ($UsePluginIfAvailable -and $isPS72Plus -and $azPred) {
            try {
                Import-Module Az.Tools.Predictor -ErrorAction Stop
                $source = 'HistoryAndPlugin'
            } catch {
                $result.Notes += "Az.Tools.Predictor present but failed to import: $($_.Exception.Message)"
            }
        }

        try {
            Set-PSReadLineOption -PredictionSource $source
            $result.PredictionEnabled = $true
            $result.PredictionSource  = $source
        } catch {
            $result.Notes += "Set-PSReadLineOption -PredictionSource failed: $($_.Exception.Message)"
        }
    } else {
        $result.Notes += "This PSReadLine does not expose -PredictionSource; skipping predictions."
    }

    # 3) Decide PredictionViewStyle
    if ($hasPredictionView) {
        $viewToSet = $null
        switch ($ViewStyle) {
            'Inline' { $viewToSet = 'InlineView' }
            'List'   { $viewToSet = 'ListView' }
            'Auto'   {
                # Prefer Inline when available; fallback to List
                # If Inline throws, we’ll try List and then skip.
                $viewToSet = 'InlineView'
            }
        }

        if ($viewToSet) {
            $applied = $false
            foreach ($candidate in @($viewToSet, 'ListView')) {
                if ($applied) { break }
                try {
                    Set-PSReadLineOption -PredictionViewStyle $candidate
                    $result.PredictionViewStyle = $candidate
                    $applied = $true
                } catch {
                    # try next candidate if we're in Auto and Inline failed
                }
            }
            if (-not $applied) { $result.Notes += "Could not set any PredictionViewStyle on this build." }
        }
    } else {
        $result.Notes += "This PSReadLine does not expose -PredictionViewStyle; view not set."
    }

    # 4) Edit mode (safe everywhere)
    try {
        Set-PSReadLineOption -EditMode Windows
    } catch { }

    # 5) Helpful keybindings — only if functions exist
    $keyFn = @{
        "Ctrl+RightArrow" = "AcceptNextSuggestionWord"
        "Alt+RightArrow"  = "NextSuggestion"
        "Alt+LeftArrow"   = "PreviousSuggestion"
    }
    foreach ($kvp in $keyFn.GetEnumerator()) {
        try {
            Set-PSReadLineKeyHandler -Key $kvp.Key -Function $kvp.Value
            $result.KeybindingsApplied += "$($kvp.Key)→$($kvp.Value)"
        } catch {
            # Older PSReadLine may not have those functions; ignore
        }
    }

    return $result
}
Initialize-PSReadLineSmart

if ( Test-Path "C:\Program Files\RedHat\Podman\podman.exe" ) {
    Set-Alias -Name docker -Value podman
    [System.Environment]::SetEnvironmentVariable("ASPIRE_CONTAINER_RUNTIME", "podman", "User")
}

function Find-ProgramInPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProgramName
    )
    $ErrorActionPreference = 'Ignore'
    # Get the PATH environment variable and split it into directories
    $PathDirs = [System.Environment]::GetEnvironmentVariable("PATH") -split ";"

    # Search each directory for the program
    foreach ($Dir in $PathDirs) {
        $FullPath = Join-Path -Path $Dir -ChildPath $ProgramName
        if (Test-Path $FullPath) {
            return $true
        }
    }
    return $false
}

# Check for Starship
if (Find-ProgramInPath -ProgramName starship.exe) {
    if (-not $env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG = "$env:OneDriveCommercial\starship.toml"
        $env:STARSHIP_CACHE = "$HOME\AppData\Local\Temp"
    }
    $starshipConfig = "$env:STARSHIP_CONFIG"
    if (-not (Test-Path "$starshipConfig" -PathType Leaf)) {
        Write-Host ("Starship inital config...")
        ## $env:STARSHIP_LOG = "trace starship module rust"
        ## starship preset nerd-font-symbols --output "$env:STARSHIP_CONFIG"
        ## starship preset no-runtime-versions --output "$env:STARSHIP_CONFIG"
        starship preset catppuccin-powerline --output "$env:STARSHIP_CONFIG"
        $azurecfg = '
[azure]
disabled = true
format = "on [$symbol($username)]($style) "
symbol = "󰠅 "
style = "blue bold"
'
        ## $azurecfg | Out-File -FilePath "$env:STARSHIP_CONFIG" -Encoding UTF8 -Append
        ## ~/.azure/azureProfile.json - created/manged via Azure CLI   
    }
}

if ($IsLanguagePermissive) {
    Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
        -BriefDescription BuildCurrentDirectory `
        -LongDescription "DotNet Build the current directory" `
        -ScriptBlock {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet build")
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
    }
}

function Invoke-Starship-TransientFunction {
    &starship module character
}

function Install-OrUpdateModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [switch]$Prerelease          # Optional: install prerelease versions
    )

    # Check if PSResourceGet is available
    if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
        Write-Host "PSResourceGet not found. Installing it first..." -ForegroundColor Yellow
        Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope $InstallScope -Force
        Import-Module Microsoft.PowerShell.PSResourceGet
    }

    # Check if module is already installed
    $installed = Get-PSResource -Name $ModuleName -ErrorAction SilentlyContinue -Scope $Installscope

    try {
        if ($null -eq $installed) {
            Write-Host "Module '$ModuleName' not found. Installing (${InstallScope})..." -ForegroundColor Green
            if ($prerelease) {
                Install-PSResource -Name $ModuleName -Prerelease $true -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            } else {
                ## Install-PSResource -Name PackageManagement -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
                Install-PSResource -Name $ModuleName -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            }
        }
        else {
            Write-Host "Module '$ModuleName' found. Updating (${InstallScope})..." -ForegroundColor Cyan
            ## Update-PSResource -Name PackageManagement -AcceptLicense $true -Confirm $false -ErrorAction Stop -WarningAction SilentlyContinue
            if ($prerelease) {
                Update-PSResource -Name $ModuleName -Prerelease $true -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            } else {
                Update-PSResource -Name $ModuleName -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            }
        }
        # Optional: import after install/update
        Import-Module $ModuleName -Force
        Write-Host "✅ '$ModuleName' is installed (and up to date.)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to install or update '$ModuleName': $_" -ForegroundColor Red
    }
}

#Only works for Powershell naked (no starship,Oh My Posh etc..)
function prompt {
    #if (-not ($IsLanguagePermissive)) { return  }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal] $identity
    $adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

    if ($principal.IsInRole($adminRole)) {
        $color = "Red"
        Write-Host ("PS (Admin) " + $(Get-Location) + ">") -NoNewline -ForegroundColor $Color
    }
    else {
        $color = "Green"    
        Write-Host ("PS " + $(Get-Location) + ">") -NoNewline -ForegroundColor $Color
    }
    return "`n> "
}

#function prompt {
#    $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
#    $path = (Get-Location).Path
#
#    Write-Host "[$user]" -ForegroundColor Cyan -NoNewline
#    Write-Host " $path" -ForegroundColor Yellow -NoNewline
#    return "`n> "
#}


if ($env:IsDevBox -eq "True" ) {
    if ($env:UPN) {
        Write-Host -ForegroundColor Cyan "Welcome to your Dev Box $env:UPN"
    }
    else {
        Write-Host -ForegroundColor Cyan "Welcome to your Dev Box"
    }
    devbox metadata get list-all
    devbox ai status
}

$ompConfig = "$env:POSH_THEMES_PATH\cloud-native-azure.omp.json"

## Check for Starship
if ($env:STARSHIP_CONFIG -and (Test-Path "$starshipConfig" -PathType Leaf)) {
    Write-Host "Found Starship shell...so starting it..."
    Invoke-Expression (&starship init powershell)
    Enable-TransientPrompt
} elseif ($env:POSH_THEMES_PATH -and (Test-Path "$ompConfig" -Pathtype Leaf)) {
    Write-Host "Found Oh-My-Posh shell...so starting it..."
    & ([ScriptBlock]::Create((oh-my-posh init pwsh --config $ompConfig --print) -join "`n"))
} else {
    if ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15) {
        ## Set stuff here
    }
}

## Test Nerd Fonts
if ($IsLanguagePermissive) {
    $char = [System.Text.Encoding]::UTF8.GetString([byte[]](0xF0, 0x9F, 0x90, 0x8D))
    if ([string]::IsNullOrEmpty($char)) {
        Write-Host -ForegroundColor "Yellow" "Warning: Nerd Fonts are NOT installed!" 
    }
}

function Get-OsInfo {
  [PSCustomObject]@{
    ProductName = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ProductName
    ReleaseId   = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').ReleaseId
    DisplayVer  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).DisplayVersion
    Build       = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    UBR         = [int](Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').UBR
  }
}

## Linux touch 
function touch {
    param (
        [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    foreach ($Path in $Paths) {
        if (Test-Path $Path) {
            (Get-Item $Path).LastWriteTime = Get-Date
        }
        else {
            New-Item -ItemType File -Path $Path | Out-Null
        }
    }
}

function which {
    Get-Command
}

function Reset-GitBranch {

    # Check Git availability
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error "Git is not installed or not available in PATH."
        return
    }

    # Ensure we are inside a Git repo
    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
    } catch {
        Write-Error "Not a Git repository."
        return
    }

    if (-not $branch) {
        Write-Error "Unable to determine current branch."
        return
    }

    Write-Host "You are on branch: $branch" -ForegroundColor Cyan

    Write-Host "`nFetching latest changes from origin..." -ForegroundColor Cyan
    git fetch origin

    Write-Host "Resetting local branch '$branch' to origin/$branch..." -ForegroundColor Yellow
    git reset --hard "origin/$branch"

    Write-Host "Cleaning untracked files and directories..." -ForegroundColor Red
    git clean -fd

    Write-Host "`n✅ Local branch '$branch' is now identical to origin/$branch." -ForegroundColor Green
}

# Alias management
foreach ($alias in 't', 'tf', 'tv') {
    if (Get-Alias $alias -ErrorAction SilentlyContinue) { Remove-Alias $alias -ErrorAction SilentlyContinue }
}
#Set-Alias t terraform.exe
function tf { terraform.exe fmt }
function tv { terraform.exe validate }
function ti { terraform.exe init -upgrade }

function cdw { Set-Location c:\workspaces }

function free {
    (Get-Volume -DriveLetter C).SizeRemaining | ForEach-Object {
        $sizeInGB = [math]::Round($_ / 1GB, 2)
        if ($sizeInGB -lt 5) {
            Write-Host "Warning: Free space on Drive C: is $sizeInGB GB!" -ForegroundColor Red
       } else {
            Write-Output "Free space on Drive C: is $sizeInGB GB"
        }
    }
}

function checkdiskspace {
    if (-not ($IsLanguagePermissive)) { return }
    (Get-Volume -DriveLetter C).SizeRemaining | ForEach-Object {
        $sizeInGB = [math]::Round($_ / 1GB, 2)
        if ($sizeInGB -lt 5) {
            Write-Host "Warning: Free space on Drive C: less than 5GB. Space remaining is $sizeInGB GB!" -ForegroundColor Red
        }
    }
}
checkdiskspace

function grep {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
        [string[]]$Files
    )

    # Only run on Windows
    if ((Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) -and (-not $IsWindows)) {
        Write-Warning "This grep function is only available on Windows"
        return
    }
    if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) -and 
        [System.Environment]::OSVersion.Platform -ne "Win32NT") {
        Write-Warning "This grep function is only available on Windows"
        return
    }

    foreach ($file in $Files) {
        # Expand wildcards manually
        $resolvedFiles = Get-ChildItem -Path $file -File -ErrorAction SilentlyContinue
        if ($resolvedFiles.Count -eq 0) {
            Write-Warning "No matching file for: $file"
            continue
        }

        foreach ($resolvedFile in $resolvedFiles) {
            $filePath = $resolvedFile.Name
            $lines = Get-Content -LiteralPath $filePath

            for ($i = 0; $i -lt $lines.Length; $i++) {
                $line = $lines[$i]
                if ($line -match $Pattern) {
                    Write-Output "${filePath}:$line"
                }
            }
        }
    }
}

function curl {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Url,

        [string]$Method = "GET",

        [string]$Output,

        [string[]]$Headers,

        [string]$Data,

        [switch]$VerboseOutput
    )

    # Only run on Windows
    if ((Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) -and (-not $IsWindows)) {
        Write-Warning "This grep function is only available on Windows"
        return
    }
    if (-not (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) -and 
        [System.Environment]::OSVersion.Platform -ne "Win32NT") {
        Write-Warning "This grep function is only available on Windows"
        return
    }

    # Create headers hashtable if headers are provided
    $headersTable = @{}
    if ($Headers) {
        foreach ($header in $Headers) {
            $key, $value = $header -split ":", 2
            $headersTable[$key.Trim()] = $value.Trim()
        }
    }

    # Build Invoke-RestMethod parameters
    $invokeParams = @{
        Uri     = $Url
        Method  = $Method.ToUpper()
        Headers = $headersTable
    }

    if ($Data) {
        $invokeParams["Body"] = $Data
        $invokeParams["ContentType"] = "application/x-www-form-urlencoded"
    }

    try {
        if ($Output) {
            # Use Invoke-WebRequest to download file
            Invoke-WebRequest @invokeParams -OutFile $Output
            Write-Output "Saved to $Output"
        }
        else {
            $response = Invoke-RestMethod @invokeParams
            Write-Output $response
        }
    }
    catch {
        Write-Error "Error: $_"
    }

    if ($VerboseOutput) {
        Write-Verbose "URL: $Url"
        Write-Verbose "Method: $Method"
        if ($Headers) { Write-Verbose "Headers: $Headers" }
        if ($Data) { Write-Verbose "Data: $Data" }
    }
}

function Restore-Terminal {
    <#
    .SYNOPSIS
        Restores normal console input/echo if Windows Terminal or PowerShell
        gets stuck in "secure input mode" (dots instead of pasted text).
    #>

    try {
        # Reset Ctrl+C handling
        [System.Console]::TreatControlCAsInput = $false

        # Ensure echo is on
        [System.Console]::Echo = $true

        Write-Host "✅ Console input reset. You should now be able to paste normally."
    }
    catch {
        Write-Warning "⚠️ Could not reset console state. Try closing and reopening the terminal."
    }
}

# Function to normalize clipboard text (LF → CRLF)
#function Get-NormalizedClipboard {
#    if (Get-Clipboard -Format Text -ErrorAction SilentlyContinue) {
#        $text = Get-Clipboard -Raw -Format Text
#        # Replace lone LF with CRLF
#        $normalized = $text -replace "(?<!`r)`n","`r`n"
#        return $normalized
#    }
#    return ""
#}

# Override the default Paste (Ctrl+V) behavior
#Set-PSReadLineKeyHandler -Key Ctrl+V -BriefDescription "Paste normalized text" -ScriptBlock {
#    $clip = Get-NormalizedClipboard
#    if ($clip) {
#        [Microsoft.PowerShell.PSConsoleReadLine]::Paste($clip)
#    }
#}

if ($IsLanguagePermissive) {
    $CLSIDs = @()
    foreach($registryKey in (Get-ChildItem "Registry::HKEY_CLASSES_ROOT\CLSID" -Recurse -ErrorAction SilentlyContinue)){
        If (($registryKey.GetValueNames() | %{$registryKey.GetValue($_)}) -eq "Drive or folder redirected using Remote Desktop") {
            $CLSIDs += $registryKey
        }
    }
    $drives = @()
    foreach ($CLSID in $CLSIDs.PSPath) {
        $drives += (Get-ItemProperty $CLSID)."(default)"
    }
    if (Get-Module -ListAvailable -Name Terminal-Icons | Out-Null ) {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
}


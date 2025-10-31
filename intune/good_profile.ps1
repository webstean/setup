

## https://raw.githubusercontent.com/lscph1929/scripts/refs/heads/main/profile/good_profile.ps1
## This FILE is ASCiI encoded, for compability with Windows Powershell, so any Unicode characters need to be eliminated

#Set-ExecutionPolicy Unrestricted -Scope Process
#Set-ExecutionPolicy Unrestricted -Scope CurrentUser

function Update-Profile-Force {
    # Define the remote URL
    $url = 'https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/good_profile.ps1'

    # Ensure the profile directory exists
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Download and overwrite the profile
    $response = Invoke-WebRequest -Uri $url -ContentType "text/plan" -UseBasicParsing
    $response.Content | Out-File -FilePath $PROFILE -Encoding ASCII

    Write-Host -ForegroundColor DarkGreen "PowerShell Profile updated at $PROFILE"
    #Write-Host -ForegroundColor DarkRed 
    #Write-Host -ForegroundColor DarkYellow
}
#Update-Profile-Force

function Set-WslNetConfig {
    ## make WSL compatible with Podman, especially being able to access containers via loopback/127.0.0.1

    if (-not ($IsLanguagePermissive)) { return }
    
    # Ensure WSL networking mode is Mirror
    # Ensure WSL autoproxy is off
    $wslConfigPath = [System.IO.Path]::Combine($env:HOMEPATH, ".wslconfig")
    # Check if the .wslconfig file exists
    if (Test-Path $wslConfigPath) {
        # Read the contents of the .wslconfig file
        $wslConfigContent = Get-Content -Path $wslConfigPath -Raw
        
        # Check if 'networkingMode' is set to 'mirrored'
        if ($wslConfigContent -notmatch "networkingMode\s*=\s*mirrored") {
            # Add or update the networkingMode setting
            $newConfig1 = $wslConfigContent -replace "(\[.*?\])", "`$1`r`nnetworkingMode = mirrored"
            $newConfig2 = $wslConfigContent -replace "(\[.*?\])", "`$1`r`nautoProxy = false"
            
            # Write the updated content back to the file
            Set-Content -Path $wslConfigPath -Value $newConfig1 -Force
            Set-Content -Path $wslConfigPath -Value $newConfig2 -Force
            Write-Host "Added 'networkingMode = mirrored' to .wslconfig"
        } else {
            Write-Host "Updated existing .wslconfig"
        }
    } else {
        # If .wslconfig doesn't exist, create it with the networkingMode setting
        $configContent1 = "[network]" + "`r`n" + "networkingMode = mirrored"
        Set-Content -Path $wslConfigPath -Value $configContent1
        $configContent2 = "[network]" + "`r`n" + "autoProxy = false"
        Set-Content -Path $wslConfigPath -Value $configContent2
        
        Write-Host "Created new .wslconfig"
    }
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
    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
} 
if ([bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP -eq '65001') { 
    Write-Host  -ForegroundColor DarkGreen ("UTF-8 output encoding enabled")
    $UTF8 = $true
}

# Get the current language mode
if ($IsLanguagePermissive) {
    Write-Host -ForegroundColor DarkGreen "PowerShell Language Mode is: $currentMode"
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    Write-Host -ForegroundColor DarkYellow "PowerShell Language Mode is: $currentMode (most advanced things won't work here)"
    $IsAdmin = (whoami /groups | Select-String "S-1-5-32-544") -ne $null
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
} else {
    $InstallScope = 'CurrentUser'
}

function Set-Developer-Variables {
    ## Edit as required
    
    ## Dont send telemetry to Microsoft
    Set-Item -Path Env:\FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\POWERSHELL_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\DOTNET_UPGRADEASSISTANT_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\DOTNET_CLI_TELEMETRY_OPTOUT -Value $true

    ## AZD get rid of annoying update prompt
    Set-Item -Path Env:\AZD_SKIP_UPDATE_CHECK -Value $true
    
    ## Azure PowerShell - suppress breaking change message
    Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

    ## .Net environment variables: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables
    ## Note: Generally speaking a value set in the project file or runtimeconfig.json has a higher priority than the environment variable.
    Set-Item -Path Env:\DOTNET_GENERATE_ASPNET_CERTIFICATE -Value $false
    Set-Item -Path Env:\DOTNET_NOLOGO -Value $true
    Set-Item -Path Env:\DOTNET_EnableDiagnostics_Debugger -Value $true
    Set-Item -Path Env:\DOTNET_EnableDiagnostics_Profiler -Value $true
    Set-Item -Path Env:\COREHOST_TRACE -Value $false
    Set-Item -Path Env:\COREHOST_TRACEFILE -Value 'corehost_trace.log'
    Set-Item -Path Env:\DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE -Value $true
    Set-Item -Path Env:\COREHOST_TRACE_VERBOSITY -Value 4
    ## 4 (All)- all tracing information is written
    ## 3 (Info, Warn, Error)
    ## 2 (Warn & Errors)
    ## 1 (Only Errors)
    Set-Item -Path Env:\SuppressNETCoreSdkPreviewMessage -Value $true ## invoking dotnet won't produce a warning when a preview SDK is being used.
    ## DOTNET_SYSTEM_NET_HTTP_ENABLEACTIVITYPROPAGATION ## Indicates whether or not to enable activity propagation of the diagnostic handler for global HTTP settings.
    ## DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_HTTP2SUPPORT ## When set to false or 0, disables HTTP/2 support, which is enabled by default.
    ## DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_HTTP3SUPPORT ## When set to true or 1, enables HTTP/3 support, which is disabled by default.
    ## DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_HTTP2FLOWCONTROL_DISABLEDYNAMICWINDOWSIZING ## When set to false or 0, overrides the default and disables the HTTP/2 dynamic window scaling algorithm.
    ## DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_FLOWCONTROL_MAXSTREAMWINDOWSIZE ## Defaults to 16 MB. When overridden, the maximum size of the HTTP/2 stream receive window cannot be less than 65,535.
    ## DOTNET_SYSTEM_NET_HTTP_SOCKETSHTTPHANDLER_FLOWCONTROL_STREAMWINDOWSCALETHRESHOLDMULTIPLIER ## Defaults to 1.0. When overridden, higher values result in a shorter window but slower downloads. Can't be less than 0.
    ## DOTNET_SYSTEM_GLOBALIZATION_INVARIANT ## See set invariant mode.
    ## DOTNET_SYSTEM_GLOBALIZATION_PREDEFINED_CULTURES_ONLY ## Specifies whether to load only predefined cultures.
    ## DOTNET_SYSTEM_GLOBALIZATION_APPLOCALICU ## Indicates whether to use the app-local International Components of Unicode (ICU). For more information, see App-local ICU.
    ## DOTNET_SYSTEM_GLOBALIZATION_USENLS ## This applies to Windows only. For globalization to use National Language Support (NLS), set DOTNET_SYSTEM_GLOBALIZATION_USENLS to either true or 1. To not use it, set DOTNET_SYSTEM_GLOBALIZATION_USENLS to either false or 0.
    ## DOTNET_SYSTEM_NET_SOCKETS_INLINE_COMPLETIONS
    ## DOTNET_SYSTEM_NET_SOCKETS_THREAD_COUNT ## Socket continuations are dispatched to the System.Threading.ThreadPool from the event thread. This avoids continuations blocking the event handling. To allow continuations to run directly on the event thread, set DOTNET_SYSTEM_NET_SOCKETS_INLINE_COMPLETIONS to 1. It's disabled by default.
    ## DOTNET_SYSTEM_NET_DISABLEIPV6 ## Helps determine whether or not Internet Protocol version 6 (IPv6) is disabled. When set to either true or 1, IPv6 is disabled unless otherwise specified in the System.AppContext.
    ## DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER ## You can use one of the following mechanisms to configure a process to use the older HttpClientHandler:
    ## DOTNET_RUNNING_IN_CONTAINER
    ## DOTNET_RUNNING_IN_CONTAINERS ## These values are used to determine when your ASP.NET Core workloads are running in the context of a container.
    ## DOTNET_SYSTEM_CONSOLE_ALLOW_ANSI_COLOR_REDIRECTION ## When Console.IsOutputRedirected is true, you can emit ANSI color code by setting DOTNET_SYSTEM_CONSOLE_ALLOW_ANSI_COLOR_REDIRECTION to either 1 or true.
    ## DOTNET_SYSTEM_DIAGNOSTICS_DEFAULTACTIVITYIDFORMATISHIERARCHIAL: When 1 or true, the default Activity Id format is hierarchical.
    Set-Item -Path Env:\DOTNET_SYSTEM_DIAGNOSTICS_DEFAULTACTIVITYIDFORMATISHIERARCHIAL -Value $true 
    ## DOTNET_SYSTEM_RUNTIME_CACHING_TRACING: When running as Debug, tracing can be enabled when this is true.
    ## DOTNET_DiagnosticPorts ## Configures alternate endpoints where diagnostic tools can communicate with the .NET runtime. See the Diagnostic Port documentation for more information.
    ## DOTNET_DefaultDiagnosticPortSuspend ## Configures the runtime to pause during startup and wait for the Diagnostics IPC ResumeStartup command from the specified diagnostic port when set to 1. Defaults to 0. See the Diagnostic Port documentation for more information.
    ## DOTNET_EnableDiagnostics ## When set to 0, disables debugging, profiling, and other diagnostics via the Diagnostic Port and can't be overridden by other diagnostics settings. Defaults to 1.
    ## DOTNET_EnableDiagnostics_IPC ## Starting with .NET 8, when set to 0, disables the Diagnostic Port and can't be overridden by other diagnostics settings. Defaults to 1.
    ## DOTNET_EnableDiagnostics_Debugger ## Starting with .NET 8, when set to 0, disables debugging and can't be overridden by other diagnostics settings. Defaults to 1.#
    ## DOTNET_EnableDiagnostics_Profiler ## Starting with .NET 8, when set to 0, disables profiling and can't be overridden by other diagnostics settings. Defaults to 1.
    ## DOTNET_EnableEventPipe ## When set to 1, enables tracing via EventPipe.
    ## DOTNET_EventPipeOutputPath ## The output path where the trace will be written.
    ## DOTNET_EventPipeOutputStreaming ## When set to 1, enables streaming to the output file while the app is running. By default trace information is accumulated in a circular buffer and the contents are written at app shutdown.
    ## DOTNET_CLI_PERF_LOG ## Specifies whether performance details about the current CLI session are logged. Enabled when set to 1, true, or yes. This is disabled by default.
    ## DOTNET_ADD_GLOBAL_TOOLS_TO_PATH ## Specifies whether to add global tools to the PATH environment variable. The default is true. To not add global tools to the path, set to 0, false, or no.
    ## DOTNET_ROLL_FORWARD_TO_PRERELEASE ## If set to 1 (enabled), enables rolling forward to a pre-release version from a release version. By default (0 - disabled), when a release version of .NET runtime is requested, roll-forward will only consider installed release versions.
    ## DOTNET_ROLL_FORWARD_ON_NO_CANDIDATE_FX ## Disables minor version roll forward, if set to 0. This setting is superseded in .NET Core 3.0 by DOTNET_ROLL_FORWARD. The new settings should be used instead.
    ## DOTNET_CLI_FORCE_UTF8_ENCODING ## Forces the use of UTF-8 encoding in the console, even for older versions of Windows 10 that don't fully support UTF-8. For more information, see SDK no longer changes console encoding when finished.
    ## DOTNET_CLI_UI_LANGUAGE ## Sets the language of the CLI UI using a locale value such as en-us. The supported values are the same as for Visual Studio. For more information, see the section on changing the installer language in the Visual Studio installation documentation. The .NET resource manager rules apply, so you don't have to pick an exact match—you can also pick descendants in the CultureInfo tree. For example, if you set it to fr-CA, the CLI will find and use the fr translations. If you set it to a language that is not supported, the CLI falls back to English.
    ## DOTNET_ADDITIONAL_DEPS ## Equivalent to CLI option --additional-deps.
    ## DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_INTERVAL_HOURS ## Specifies the minimum number of hours between background downloads of advertising manifests for workloads. The default is 24, which is no more frequently than once a day. For more information, see Advertising manifests.
    ## DOTNET_TOOLS_ALLOW_MANIFEST_IN_ROOT ## Specifies whether .NET SDK local tools search for tool manifest files in the root folder on Windows. The default is false.
    ## The typical way to get detailed trace information about application startup is to set COREHOST_TRACE=1 andCOREHOST_TRACEFILE=host_trace.txt and then run the application. A new file host_trace.txt will be created in the current directory with the detailed information.
    ## SuppressNETCoreSdkPreviewMessage ## If set to true, invoking dotnet won't produce a warning when a preview SDK is being used.
    ## DOTNET_CLI_RUN_MSBUILD_OUTOFPROC ## 1, true, or yes. By default, MSBuild will execute in-proc. To force MSBuild to use an external working node long-living process for building projects, set DOTNET_CLI_USE_MSBUILDNOINPROCNODE to 1, true, or yes. This will set the MSBUILDNOINPROCNODE environment variable to 1, which is referred to as MSBuild Server V1, as the entry process forwards most of the work to it.
    ## DOTNET_MSBUILD_SDK_RESOLVER_* ## These are overrides that are used to force the resolved SDK tasks and targets to come from a given base directory and report a given version to MSBuild, which may be null if unknown. One key use case for this is to test SDK tasks and targets without deploying them by using the .NET Core SDK.
    ## DOTNET_MSBUILD_SDK_RESOLVER_SDKS_DIR ## Overrides the .NET SDK directory.
    ## DOTNET_MSBUILD_SDK_RESOLVER_SDKS_VER ## Overrides the .NET SDK version.
    ## DOTNET_MSBUILD_SDK_RESOLVER_CLI_DIR  ## Overrides the dotnet.exe directory path.
    ## DOTNET_NEW_PREFERRED_LANG ## Configures the default programming language for the dotnet new command when the -lang|--language switch is omitted. The default value is C#. Valid values are C#, F#, or VB. For more information, see dotnet new.
}
Set-Developer-Variables

## If Windows Powershell
if ($PSVersionTable.PSEdition -eq 'Desktop') {
    Write-Host -ForegroundColor DarkYellow "Exiting PowerShell Profile - as this is Windows PowerShell"
    return $true | Out-Null
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

    if ( -not ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15)) { return }

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
if ([bool](Get-Command -ErrorAction SilentlyContinue starship.exe).Source) {
    if (-not $env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG = "$env:OneDriveCommercial\starship.toml"
        $env:STARSHIP_CACHE  = "$HOME\AppData\Local\Temp"
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
        Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope $InstallScope -Force -ErrorAction SilentlyContinue
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
        Write-Host "'$ModuleName' is installed (and up to date.)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed to install or update '$ModuleName': $_" -ForegroundColor Red
    }
}

#Only works for Powershell naked (no starship,Oh My Posh etc..)
function prompt {

    if ( $IsAdmin ) {
        $color = "Red"
        Write-Host ("PS (Admin) " + $(Get-Location) + ">") -NoNewline -ForegroundColor $Color
    } else {
        $color = "Green"    
        Write-Host ("PS " + $(Get-Location) + ">") -NoNewline -ForegroundColor $Color
    }
    return "`n> "
}

if ($env:IsDevBox -eq "True" ) {
    if ($env:UPN) {
        Write-Host -ForegroundColor Cyan "Welcome to your Dev Box $env:UPN"
    }
    else {
        Write-Host -ForegroundColor Cyan "Welcome to your Dev Box"
    }
    if ( [bool](Get-Command jq.exe -ErrorAction SilentlyContinue )) {
        devbox metadata get list-all | jq
        devbox ai status | jq
    } else {
        devbox metadata get list-all
        devbox ai status
    }
}

$ompConfig = "$env:POSH_THEMES_PATH\cloud-native-azure.omp.json"

## Check for Starship
#(Get-Command -ErrorAction SilentlyContinue starship.exe).Source

## Check for Starship
if ($env:STARSHIP_CONFIG -and (Test-Path "$starshipConfig" -PathType Leaf)) {
    Write-Host "Found Starship shell...so starting it..."
    Invoke-Expression (&starship init powershell)
    Enable-TransientPrompt
    $Host.UI.RawUI.WindowTitle = "PowerShell - Starship"
} elseif ($env:POSH_THEMES_PATH -and (Test-Path "$ompConfig" -Pathtype Leaf)) {
    Write-Host "Found Oh-My-Posh shell...so starting it..."
    & ([ScriptBlock]::Create((oh-my-posh init pwsh --config $ompConfig --print) -join "`n"))
    $Host.UI.RawUI.WindowTitle = "PowerShell - Oh-My-Posh"
} else {
    if ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15) {
        $Host.UI.RawUI.WindowTitle = "PowerShell"
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

    Write-Host "`nLocal branch '$branch' is now identical to origin/$branch." -ForegroundColor Green
}

# Alias management
foreach ($alias in 't', 'tf', 'tv', 'ti' ) {
    if ([bool](Get-Alias $alias -ErrorAction SilentlyContinue)) { Remove-Item Alias:$alias -force }
}

function t { terraform.exe @args }
function tf { terraform.exe fmt @args}
function tv { terraform.exe validate @args }
function ti { terraform.exe init -upgrade @args}
 
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
    if ( -not ($IsLanguagePermissive)) { return } 

    try {
        # Reset Ctrl+C handling
        [System.Console]::TreatControlCAsInput = $false

        # Ensure echo is on
        [System.Console]::Echo = $true

        Write-Host "Console input reset. You should now be able to paste normally."
    }
    catch {
        Write-Warning "Could not reset console state. Try closing and reopening the terminal."
    }
}

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
    if ( -not [bool](Get-Module -ListAvailable -Name Terminal-Icons | Out-Null )) {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
    if ( -not [bool](Get-Module -ListAvailable -Name Az.Tools.Predictor | Out-Null )) {
        Import-Module Az.Tools.Predictor -ErrorAction SilentlyContinue
    }

    if ($subscription_id = (Get-AzSubscription -ErrorAction SilentlyContinue).Id ) {
        Set-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Value $subscription_id
    } else {
        Remove-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Force
    }
    if ($tenant_id = (Get-AzTenant -ErrorAction SilentlyContinue).Id ) {
        Set-Item -Path Env:\AZURE_TENANT_ID -Value $tenant_id
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_ID -Force
    }
    if ($tenant_name = (Get-AzTenant -ErrorAction SilentlyContinue).Name ) {
        Set-Item -Path Env:\AZURE_TENANT_NAME -Value $tenant_name
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_NAME -Force
    }
    
    # $Host.UI.RawUI.WindowTitle = "Andrew"
    
    #$raw = $Host.UI.RawUI
    #$raw.BufferSize = New-Object System.Management.Automation.Host.Size(
    #[Math]::Max($raw.BufferSize.Width, 160),  # width
    #5000                                      # height
    #)
    ## Alternative
    #$Host.UI.RawUI.BufferSize.Width = 120
    #$Host.UI.RawUI.BufferSize.Height = 5000
    #$Host.UI.RawUI.WindowTop = 0
}


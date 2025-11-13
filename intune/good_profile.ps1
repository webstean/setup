
## Note: This FILE is ASCII encoded, for compatibility with Windows Powershell, so any Unicode characters need to be eliminated

#Set-ExecutionPolicy Unrestricted -Scope Process
#Set-ExecutionPolicy Unrestricted -Scope CurrentUser
#Set-ExecutionPolicy -ExecutionPolicy Unrestricted

## Show verbose messages
#$VerbosePreference = 'Continue'

function Update-Profile-Force {
    # Define the remote URL
    $url = 'https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/good_profile.ps1'

    # Ensure the profile directory exists
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Download and overwrite the profile
    # Download the file content
    $response = Invoke-WebRequest -Uri $url -ContentType "text/plain" -UseBasicParsing
    $response.StatusCode
    
    $newContent = $response.Content

    # Check if file already exists
    if (Test-Path $PROFILE -ErrorAction SilentlyContinue) {
        $oldContent = Get-Content -Path $PROFILE -Raw -Encoding ASCII

        if ($oldContent -eq $newContent.content) {
            Write-Host "The downloaded file is identical to the existing one - no update needed." -ForegroundColor Yellow
        } else {
            $newContent | Out-File -FilePath $PROFILE -Encoding ASCII
            Write-Host "The downloaded file is an UPDATED version - existing file replaced." -ForegroundColor Green
        }
    } else {
        $newContent | Out-File -FilePath $PROFILE -Encoding ASCII
        Write-Host "No existing file found - new file created." -ForegroundColor Cyan
    }
}
# Update-Profile-Force

function Search {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Filter
    )

    Get-ChildItem -Path 'C:\' -Recurse -ErrorAction SilentlyContinue -Filter $Filter
}

function Reset-Podman {
    ## Run as required
    if ( -not ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue ))) {
        Write-Host "Podman was not found!"
        return $false
    }
    podman machine stop
    podman machine set --rootful
    podman machine start
    podman machine inspect | jq
}

function Reset-Podman2 {
    ## Run as required (bigger reset)
    if ( -not ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue ))) {
        Write-Host "Podman was not found!"
        return $false
    }
    podman machine reset --force
    podman machine init --rootful --timezone "Australia/Melbourne"
    podman machine start
    podman machine inspect | jq
}

if ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue )) {
    Set-Alias -Name docker -Value podman
    Set-Item -Path Env:\ASPIRE_CONTAINER_RUNTIME -Value "podman"
    #Set-WslNetConfig
    ## podman run -dt -p 8080:80/tcp docker.io/library/httpd:latest
    ## docker run -it mcr.microsoft.com/azure-cli:azurelinux3.0
    ## docker run -it mcr.microsoft.com/devcontainers/base:ubuntu
    ## docker run -it mcr.microsoft.com/azure-cloudshell
    ## podman run -it --env AZURE_SUBSCRIPTION_ID=$env:AZURE_SUBSCRIPTION_ID --env AZURE_TENANT_ID=$env:AZURE_TENANT_ID --env AZURE_USERNAME=$env:AZURE_USERNAME mcr.microsoft.com/azure-cloudshell 
    ## docker run --rm -it ghcr.io/baresip/docker/baresip:latest
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
    $IsAdmin = $null -ne (whoami /groups | Select-String "S-1-5-32-544")
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
    Write-Host -ForegroundColor DarkRed "User permisisons is        : ADMIN"
} else {
    $InstallScope = 'CurrentUser'
    Write-Host -ForegroundColor DarkYellow "User permisisons is        : USER"
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

# Run Starship if installed
function Invoke-Starship-TransientFunction {
    &starship module character
}

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

## Test Nerd Fonts
if ($IsLanguagePermissive) {
    $char = [System.Text.Encoding]::UTF8.GetString([byte[]](0xF0, 0x9F, 0x90, 0x8D))
    if ([string]::IsNullOrEmpty($char)) {
        Write-Host -ForegroundColor "Yellow" "Warning: Nerd Fonts are NOT installed!" 
    }
}

function Get-OsInfo {

    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if ($cv) {
        $props = Get-ItemProperty -Path $cv -ErrorAction SilentlyContinue
        $major = $props.CurrentMajorVersionNumber
        $minor = $props.CurrentMinorVersionNumber
        $build = $props.CurrentBuildNumber
        $ubr   = $props.UBR
        $osVersion = "$major.$minor.$build.$ubr"
    } else {
        return 
    }    
    if ($IsLanguagePermissive) {
        [PSCustomObject]@{
            ProductName = (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).ProductName
            ReleaseId   = (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).ReleaseId
            DisplayVer  = (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).DisplayVersion
            Build       = [int](Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).CurrentBuildNumber
            UBR         = [int]$ubr
            OSVersion   = $osVersion
            Type        = (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).InstallationType
        } 
    } else {
        Write-Host "ProductName : " -NoNewline
        (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).ProductName
        Write-Host "ReleaseId   : " -NoNewline
        (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).ReleaseId
        Write-Host "DisplayVer  : " -NoNewline
        (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).DisplayVersion
        Write-Host "Build       : " -NoNewline
        [int](Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).CurrentBuildNumber
        Write-Host "UBR         : " -NoNewline
        [int]$ubr
        Write-Host "OSVersion   : $osVersion"
        Write-Host "Type        : " -NoNewline
        (Get-ItemProperty "$cv" -ErrorAction SilentlyContinue).InstallationType
    }
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
$ompConfig = "C:\Program Files\WindowsApps\ohmyposh.cli_27.5.0.0_x64__96v55e8n804z4\themes\cloud-native-azure.omp.json"

## Check for Starship
#(Get-Command -ErrorAction SilentlyContinue starship.exe).Source

## Check for Starship
if ($env:STARSHIP_CONFIG -and (Test-Path "$starshipConfig" -PathType Leaf)) {
    Write-Host "Found Starship shell...so starting it..."
    Invoke-Expression (&starship init powershell)
    Enable-TransientPrompt
    if ( -not $IsAdmin ) { $Host.UI.RawUI.WindowTitle = "PowerShell - Starship" }
} elseif ($env:POSH_THEMES_PATH -and (Test-Path "$ompConfig" -Pathtype Leaf)) {
    Write-Host "Found Oh-My-Posh shell...so starting it..."
    & ([ScriptBlock]::Create((oh-my-posh init pwsh --config $ompConfig --print) -join "`n"))
    $Host.UI.RawUI.WindowTitle = "PowerShell - Oh-My-Posh"
} else {
    if ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15) {
        if ($IsLanguagePermissive) {
            $Host.UI.RawUI.WindowTitle = "PowerShell"
        }
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
    Get-Command @args
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

    $subscription_id = (Get-AzSubscription -ErrorAction SilentlyContinue).Id
    if (-not [string]::IsNullOrEmpty($subscription_id)) {
        Set-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Value $subscription_id
    } else {
        Remove-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant_id = (Get-AzTenant -ErrorAction SilentlyContinue).Id
    if (-not [string]::IsNullOrEmpty($tenant_id)) {
        Set-Item -Path Env:\AZURE_TENANT_ID -Value $tenant_id
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant_name = (Get-AzTenant -ErrorAction SilentlyContinue).Name
    if (-not [string]::IsNullOrEmpty($tenant_name)) {
        Set-Item -Path Env:\AZURE_TENANT_NAME -Value $tenant_name
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_NAME -Force -ErrorAction SilentlyContinue
    }
    
    if (![string]::IsNullOrEmpty($UPN)) {
        Set-Item -Path Env:\AZURE_USERNAME -Value $UPN
    } else {
        Remove-Item -Path Env:\AZURE_USERNAME -Force -ErrorAction SilentlyContinue
    }
    
    @"
# $env:AZURE_TENANT_NAME .env file
AZURE_SUBSCRIPTION_ID=$env:AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID=$env:AZURE_TENANT_ID
AZURE_USERNAME=$env:UPN
"@ | Out-File -Encoding UTF8 -FilePath "$HOME/.env-default"
    Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env-default" -Force
    Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env" -Force
    
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

function Get-EnvFile {
    [CmdletBinding()]
    param(
        # Don't set a static default here—compute it at runtime instead
        [Parameter(Mandatory = $false)]
        [string]$Path
    )

    # Compute default path at call time if Path wasn't provided or is blank
    if (-not $PSBoundParameters.ContainsKey('Path') -or [string]::IsNullOrWhiteSpace($Path)) {
        if ($env:OneDriveCommercial) {
            $Path = Join-Path $env:OneDriveCommercial ".env-default"
        }
        elseif ($env:OneDrive) {
            $Path = Join-Path $env:OneDrive ".env-default"
        }
        else {
            $Path = Join-Path $HOME ".env-default"
        }
    }

    if (-not (Test-Path -Path $Path)) {
        Write-Error "The specified .env file was not found: $Path"
        return $null
    }

    Write-Verbose "Loading environment variables from: $Path"

    $envVars = @{}

    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()

        # Skip blanks and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }

        # Split on the first '=' only
        $parts = $trimmed -split '=', 2
        if ($parts.Count -lt 2) { continue }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim()

        # Strip optional wrapping quotes
        if ($value -match '^(["''])?(.*?)(\1)?$') { $value = $matches[2] }

        $envVars[$key] = $value
    }

    return $envVars
}

function Import-EnvFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path "$Path")) {
        if (-not (Test-Path "$HOME\$Path")) {
            throw "File not found: $Path or $Home\$Path"
        } else {
            $Path = "$HOME\$Path"
        }
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()

        # Skip blank lines and comments
        if ($line -eq "" -or $line -match '^\s*#') { return }

        # Split KEY=value — supports values with '=' inside quotes
        if ($line -match '^\s*([^=]+?)\s*=\s*(.*)\s*$') {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()

            # Remove optional surrounding quotes
            if ($val -match '^"(.*)"$') { $val = $matches[1] }
            elseif ($val -match "^'(.*)'$") { $val = $matches[1] }

            # Set environment variable
            [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
            Write-Verbose "Set `$Env:$key = '$val'"
        }
    }
    if ($env:AZURE_USERNAME) {
        Write-Host "Logon as: $env:AZURE_USERNAME"
        Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -Scope User.Read"
        Write-Host "or"
        Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID --ClientId $env:AZURE_CLIENT_ID -Scope User.Read"
    }
    ## [System.Environment]::UnSetEnvironmentVariable("AZURE_TENANT_NAME", 'Process')
}

function Get-Logon {
    $meta = Invoke-RestMethod "https://login.microsoftonline.com/$env:AZURE_TENANT_ID/v2.0/.well-known/openid-configuration" -ErrorAction Stop
    $meta | Format-List authorization_endpoint, token_endpoint, issuer, jwks_uri
}

function Enable-PIMRole {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # Default to Global Reader
        [Parameter()]
        [string]$RoleName = "Global Reader",

        [Parameter()]
        [string]$Justification = "DA",

        [Parameter()]
        [object]$Duration = "00:08:00",

        [Parameter()]
        [string]$DirectoryScopeId = "/",

        [Parameter()]
        [string]$TicketNumber,

        [Parameter()]
        [string]$TicketSystem,

        [int]$TimeoutSeconds = 120
    )

    ## if ( -not ($IsLanguagePermissive)) { return } 

    function Convert-ToIso8601Duration([object]$ts) {
        if ($ts -is [string]) { $ts = [System.TimeSpan]::Parse($ts) }
        if ($ts -isnot [System.TimeSpan]) { throw "Duration must be a TimeSpan or 'HH:MM:SS' string." }
        $h=[int][math]::Floor($ts.TotalHours); $m=$ts.Minutes; $s=$ts.Seconds
        "PT" + ($(if($h){"$hH"})+$(if($m){"$mM"})+$(if($s -or (-not $h -and -not $m)){"$sS"}))
    }

    ## 
    function Check-Graph {
        Write-Host "Importing Microsoft Graph modules..."
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        $ctx = Get-MgContext
                if (-not $ctx -or -not $ctx.Account -or ($ctx.Scopes -notcontains "User.Read")) {
            if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
            Connect-MgGraph -NoWelcome -Scopes "User.Read" -ErrorAction Stop | Out-Null
        }
        if (-not $ctx -or -not $ctx.Account -or ($ctx.Scopes -notcontains "User.ReadBasic.All")) {
            if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
            Connect-MgGraph -NoWelcome -Scopes "User.ReadBasic.All" -ErrorAction Stop | Out-Null
        }
        if (-not $ctx -or -not $ctx.Account -or ($ctx.Scopes -notcontains "RoleAssignmentSchedule.Read.Directory")) {
            if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
            Connect-MgGraph -NoWelcome -Scopes "RoleAssignmentSchedule.Read.Directory" -ErrorAction Stop | Out-Null
        }
        #if (-not $ctx -or -not $ctx.Account -or ($ctx.Scopes -notcontains "RoleAssignmentSchedule.ReadWrite.Directory")) {
        #    if ($ctx) { Disconnect-MgGraph -ErrorAction SilentlyContinue }
        #    Connect-MgGraph -Scopes "RoleAssignmentSchedule.ReadWrite.Directory" -ErrorAction Stop | Out-Null
        #}
    }

    function Get-MyUserId {
        $ctx = Get-MgContext
        $ctx.account
        if ($ctx -and $ctx.Account -and $ctx.Account.Id) { return $ctx.Account.Id }
        return $false
    }

    try {
        Write-Host "Trying to activate $RoleName..."
        Check-Graph
        $principalId = Get-MyUserId

        # Pull eligibilities
        $ctx.roles
        $eligible = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All | Where-Object { $_.PrincipalId -eq $principalId }

        if (-not $eligible) {
            throw "No PIM-eligible directory roles found for the signed-in user."
        }

        # ---- Build activation request --------------------------------------
        $isoDur = Convert-ToIso8601Duration $Duration
        $body = @{
            action           = "selfActivate"
            justification    = $Justification
            directoryScopeId = $DirectoryScopeId
            principalId      = $principalId
            roleDefinitionId = $RoleDefinitionId
            scheduleInfo     = @{
                startDateTime = (Get-Date).ToUniversalTime()
                expiration    = @{
                    type     = "AfterDuration"
                    duration = $isoDur
                }
            }
        }

        if ($TicketNumber -or $TicketSystem) {
            $tn = if ($TicketNumber) { $TicketNumber } else { "" }
            $ts = if ($TicketSystem) { $TicketSystem } else { "" }

            $body.ticketInfo = @{
                ticketNumber = $tn
                ticketSystem = $ts
            }
        }

        if ($PSCmdlet.ShouldProcess("RoleDefinitionId=$RoleDefinitionId for PrincipalId=$principalId", "PIM self-activate")) {
            $req = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest -BodyParameter $body -ErrorAction Stop
        }

        # ---- Poll until active --------------------------------------------
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Seconds 3
            $active = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All |
                      Where-Object { $_.PrincipalId -eq $principalId -and $_.RoleDefinitionId -eq $RoleDefinitionId }
        } while (-not $active -and (Get-Date) -lt $deadline)

        if (-not $active) {
            Write-Warning "Activation submitted (Id=$($req.Id)), but role did not appear active within $TimeoutSeconds seconds."
            return $req
        }

        [pscustomobject]@{
            RequestId        = $req.Id
            RoleDefinitionId = $RoleDefinitionId
            RoleName         = if ($PSCmdlet.ParameterSetName -eq 'ByName') { $RoleName } else { $active[0].RoleDefinitionDisplayName }
            PrincipalId      = $principalId
            ActiveAssignment = $active | Select-Object Id, StartDateTime, EndDateTime, Status, RoleDefinitionId, DirectoryScopeId
        }
    }
    catch {
        if ( $IsLanguagePermissive) { 
            throw "Failed to activate PIM role ($RoleName): $($_.Exception.Message)"
        } else {
            throw "Error occured trying to activate $RoleName"
        }
    }
}
## Enable-PIMRole
## Connect-MgGraph -NoWelcome
## $user = Get-MgUserMe

# Verify if the logged-in user is the expected user
## if ($user.UserPrincipalName -eq $targetUserPrincipalName) {
##    Write-Host "Successfully logged in as $($user.UserPrincipalName) in the correct tenant."
## } else {
##    Write-Host "Error: Logged in as $($user.UserPrincipalName), but expected $targetUserPrincipalName."
##    Write-Host "Please log in as the correct user."
## }

function Get-Token-Graph {  ## with Graph PowerShell Modules
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @('Mail.ReadBasic','Mail.Read')
    )

    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    Write-Host "Requesting Access Token via Microsoft Graph PowerShell modules for scopes: $Scopes" -ForegroundColor Cyan

    # Ensure we're connected with the scopes we need
    if (-not (Get-MgContext)) {
        Connect-MgGraph -Scopes $Scopes -NoWelcome
    }

    $params = @{
        Method     = 'GET'
        Uri        = 'https://graph.microsoft.com/v1.0/me/messages'
        OutputType = 'HttpResponseMessage'
    }

    try {
        $response = Invoke-MgGraphRequest @params
    }
    catch {
        throw "Get-Token call failed. $($_.Exception.Message)"
    }

    # Primary path: read the Bearer token from the *request* Authorization header
    $authHeader = $response.RequestMessage.Headers.Authorization
    if ($authHeader -and $authHeader.Scheme -eq 'Bearer' -and $authHeader.Parameter) {
        $token = $authHeader.Parameter
    } else {
        # Fallback: some SDK versions expose the token on the MgContext
        $token = (Get-MgContext).AccessToken
    }

    if ($token) {
        $env:ACCESS_TOKEN = $token              # save for this session
        $token | Set-Clipboard
        Write-Host "Access token saved to ENV:ACCESS_TOKEN and copied to clipboard."
        $VerbosePreference = $preserve
        return $true
    }

    Write-Host "Access denied or token not available."
    $VerbosePreference = $preserve
    return $false
}

function Get-MyToken-Device-Flow { ## without Graph Modules
    param(
        ## Provide if you want; otherwise we'll pick it up from env vars
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        
        ## [string]$ClientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # Microsoft Graph PowerShell public client
        [string]$ClientId = "263a42c4-78c3-4407-8200-3387c284c303",  # DTP PnP

        [string[]]$Scopes = @('Mail.ReadBasic','Mail.Read')
    )

    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    Write-Host "Requesting Access Token via Entra ID Device Code flow for scopes: $Scopes" -ForegroundColor Cyan
    
    ## Resolve TenantId in priority order: explicit param → common env vars
    $tenantCandidates = @(
        $TenantId,
        $env:AZURE_TENANT_ID,  # Azure CLI / general
        $env:ARM_TENANT_ID,    # Terraform/ARM conventions
        $env:AAD_TENANT_ID     # some orgs use this
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $TenantId = $tenantCandidates | Select-Object -First 1
    if (-not $TenantId) {
        throw "TenantId not provided and no environment variable (AZURE_TENANT_ID/ARM_TENANT_ID/AAD_TENANT_ID) was found."
    }
    Write-Verbose "Using TenantId: $TenantId"
    Write-Verbose "Using ClientId: $ClientId"
    Write-Verbose "Using Scopes  : $Scopes"
        
    # Request a device code for the given scopes
    $deviceCodeResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
        -Body @{
            client_id = $ClientId
            scope     = $Scopes
        }

    Write-Host "`nGo to $($deviceCodeResponse.verification_uri) and enter code: $($deviceCodeResponse.user_code)" -ForegroundColor Yellow
    Write-Host "Waiting for sign-in and consent..." -ForegroundColor DarkGray

    # Poll until user signs in and token is issued
    while ($true) {
        Start-Sleep -Seconds $deviceCodeResponse.interval

        try {
            $tokenResponse = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Body @{
                    grant_type  = "device_code"
                    client_id   = $ClientId
                    device_code = $deviceCodeResponse.device_code
                }

            if ($tokenResponse.access_token) {
                Write-Host "Access token saved to ENV:ACCESS_TOKEN and copied to clipboard."
                $env:ACCESS_TOKEN = $tokenResponse.access_token              # save for this session
                $tokenResponse.access_token | Set-Clipboard
                $VerbosePreference = $preserve
                return $true
            }
        }
        catch {
            # Entra ID returns 'authorization_pending' until user completes login
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            $errormsg = $errorJson.error
            if ($errormsg -ne "authorization_pending") {
                Write-Warning "❌ Unexpected error: $($_.ErrorDetails.Message)"
                $VerbosePreference = $preserve
                break
            }
        }
    }
    $VerbosePreference = $preserve
    return $false
}

function Get-Token-Interactive {
    <#
        .SYNOPSIS
        Interactive Microsoft Entra ID / Microsoft Graph login that works in
        Constrained Language Mode (no .NET object creation).

        .DESCRIPTION
        Opens the Microsoft login URL for an Authorization Code Flow.
        The user signs in and copies the `code` query-string parameter
        from the browser redirect URL back into PowerShell.
    #>

    param(
        ## Provide if you want; otherwise we'll pick it up from env vars
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        ## [string]$ClientId = "04b07795-8ddb-461a-bbee-02f9e1bf7b46",  # Microsoft Graph PowerShell public client
        [string]$ClientId = "263a42c4-78c3-4407-8200-3387c284c303",  # DTP PnP

        [string]$RedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient",

        [string[]]$Scopes = @('Mail.ReadBasic','Mail.Read')
    )

    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    Write-Host "Requesting Access Token via Native Client flow: $Scopes" -ForegroundColor Cyan

    ## Resolve TenantId in priority order: explicit param → common env vars
    $tenantCandidates = @(
        $TenantId,
        $env:AZURE_TENANT_ID,  # Azure CLI / general
        $env:ARM_TENANT_ID,    # Terraform/ARM conventions
        $env:AAD_TENANT_ID     # some orgs use this
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $TenantId = $tenantCandidates | Select-Object -First 1
    if (-not $TenantId) {
        throw "TenantId not provided and no environment variable (AZURE_TENANT_ID/ARM_TENANT_ID/AAD_TENANT_ID) was found."
    }
    Write-Verbose "Using TenantId: $TenantId"
    Write-Verbose "Using ClientId: $ClientId"
    Write-Verbose "Using Scopes  : $Scopes"

    # Build the authorize URL
    $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize" +
               "?client_id=$ClientId" +
               "&response_type=code" +
               "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
               "&response_mode=query" +
               "&scope=$([uri]::EscapeDataString($Scopes))" +
               "&state=12345"

    Write-Host "Opening browser for Microsoft sign-in..." -ForegroundColor Cyan
    Start-Process $authUrl

    Write-Host "`nAfter you sign in, you'll be redirected to a URL similar to:`n"
    Write-Host "$RedirectUri?code=YOUR_CODE_HERE&state=12345" -ForegroundColor Yellow
    Write-Host "`nCopy the 'code' value from that URL and paste it below.`n"

    # 2️⃣ Prompt user for authorization code
    $authCode = Read-Host "Enter the authorization code"

    if ([string]::IsNullOrWhiteSpace($authCode)) {
        Write-Warning "No code entered. Aborting."
        return
    }

    # 3️⃣ Exchange authorization code for access token
    $body = @{
        grant_type   = "authorization_code"
        client_id    = $ClientId
        code         = $authCode
        redirect_uri = $RedirectUri
        scope        = $Scopes
    }

    $tokenResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $body

    if ($tokenResponse.access_token) {
        Write-Host "Access token saved to ENV:ACCESS_TOKEN and copied to clipboard."
        $env:ACCESS_TOKEN = $tokenResponse.access_token              # save for this session
        $tokenResponse.access_token | Set-Clipboard
        $VerbosePreference = $preserve
        return $true
    } else {
        Write-Warning "Failed to retrieve access token."
        $VerbosePreference = $preserve
        return $false
    }
}

function Get-EntraUserInfo {
    <#
    .SYNOPSIS
        Retrieves userinfo from Entra ID using an existing access token.
    .DESCRIPTION
        Uses the OAuth 2.0 /userinfo endpoint.
        Requires an already-acquired access token in $env:ACCESS_TOKEN.
    #>

    if (-not $env:ACCESS_TOKEN) {
        throw "No ACCESS_TOKEN found in environment variables."
    }

    $endpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/userinfo"

    try {
        $params = @{
            Method  = "GET"
            Uri     = $endpoint
            Headers = @{
                "Authorization" = "Bearer $($env:ACCESS_TOKEN)"
            }
            ErrorAction = "Stop"
        }

        $response = Invoke-RestMethod @params
        return $response
    }
    catch {
        throw "Failed to retrieve userinfo: $($_.Exception.Message)"
    }
}

function Test-Token { ## with Graph Modules

    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    $params = @{
        Method  = "GET"
        Uri = "https://graph.microsoft.com/v1.0/me/messages" +
           "?`$select=subject,receivedDateTime" +
           "&`$orderby=receivedDateTime%20desc" +
           "&`$top=5"
    }
    try {
        $response = Invoke-RestMethod @params `
        -Headers @{
            Authorization = "Bearer $env:ACCESS_TOKEN"
            Prefer        = "outlook.body-content-type='text'"
        } -ErrorAction Stop
    }
    catch {
        throw "Get email failed. $_"
    }
    ## Write-Verbose "OData Context:" $response.'@odata.context'
    $Response.Headers
    Write-Verbose ("OData Context: {0}" -f $response.'@odata.context')
    $items = if ($response.PSObject.Properties.Name -contains 'value') { $response.value } else { @($response) }
    $items
    # Extract and process the message collection
    $messages = $response.value | Select-Object `
    @{n='ReceivedLocal';e={[datetime]$_.receivedDateTime.ToLocalTime()}},
    @{n='Subject';e={$_.subject}}

    $messages | Format-Table -AutoSize
    $VerbosePreference = $preserve
}

function Show-Token {
    Install-OrUpdateModule JWTDetails
    Import-Module JWTDetails
    ## or goto: https://jwt-decoder.com/
    ##          https://jwt.ms
    JWTDetails.Decode-JWT $env:ACCESS_TOKEN
    ## JWTDetails.Show-JWTDetails $env:ACCESS_TOKEN
}

function Get-EntraID-Info {
    # Retrieve the OpenID Connect metadata (no modules required)
    $openidConfig = Invoke-RestMethod -Uri "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"

    # Show top-level keys
    $openidConfig | Format-List
}

function Set-StarShip {
    if ( $env:STARSHIP_CONFIG ) {
        # Download a config
        $url = 'https://raw.githubusercontent.com/TaouMou/starship-presets/refs/heads/main/starship_pills.toml'
        $response = Invoke-WebRequest -Uri $url -ContentType "text/plain" -UseBasicParsing
        $response.Content | Out-File $HOME/.starship_pill.toml
        Copy-Item $HOME/.starship_pill.toml $env:STARSHIP_CONFIG
        
        ## Other options
        #starship preset pastel-powerline -o $env:STARSHIP_CONFIG
        #starship preset nerd-font-symbols -o $env:STARSHIP_CONFIG
        #starship preset gruvbox-rainbow -o $env:STARSHIP_CONFIG
        #starship preset plain-text-symbols -o $env:STARSHIP_CONFIG
        #starship preset bracketed-segments -o $env:STARSHIP_CONFIG
        
        ## Implement 
        Invoke-Expression (&starship init powershell -o $env:STARSHIP_CONFIG)
    }
}

if (Get-Command 'azd' -ErrorAction SilentlyContinue) {
    azd auth login --check-status
}
## Show verbose messages
$VerbosePreference = 'Continue'



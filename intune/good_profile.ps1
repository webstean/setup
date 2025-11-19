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
    $response.StatusDescription
    
    $newContent = $response.Content
    $newContentLength = $response.RawContentLength

    ## (Get-FileHash "$profile").Hash

    # Check if file already exists
    if (Test-Path $PROFILE -ErrorAction SilentlyContinue) {
        $oldContent = Get-Content -Path $PROFILE -Raw -Encoding ASCII

        if ($oldContent.Trim().ToLower() -eq $newContent.Trim().ToLower()) {
            Write-Host "The downloaded file is identical to the existing one - no update needed." -ForegroundColor Yellow
        } else {
            $newContent | Out-File -FilePath $PROFILE -Encoding ASCII
            Write-Host "The downloaded file is an UPDATED version - replacing..." -ForegroundColor Green
        }
    } else {
        $newContent | Out-File -FilePath $PROFILE -Encoding ASCII
        Write-Host "No existing file found - new file created." -ForegroundColor Cyan
    }
}
#Update-Profile-Force

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

$VirtualMachine = $true
$type = $null

function Get-HostPlatform {

    if ($env:IsDevBox -eq "True" ) {
        $VirtualMachine = $true
        $type = "Azure DevBox"
        return
    }

    $cs = Get-CimInstance Win32_ComputerSystem
    $model = "$($cs.Manufacturer) $($cs.Model)"
    
    switch -Regex ($model) {
        "VMware" {
            $VirtualMachine = $true
            $type = "VMware virtual machine"
        }
        "VirtualBox" {
            $VirtualMachine = $true
            $type = "Oracle VirtualBox VM"
        }
        "Microsoft.*Virtual" {
            $VirtualMachine = $true
            $type = "Hyper-V / Azure virtual machine"
        }
        "QEMU|KVM" {
            $VirtualMachine = $true
            $type = "KVM/QEMU virtual machine"
        }
        default {
            $VirtualMachine = $false
            $type = "Likely bare-metal physical machine"
        }
    }

    if ($IsLanguagePermissive) {
        [pscustomobject]@{
            VirtualMachine = $virtualMachine
            Type           = $type
        }
    }
}
Get-HostPlatform

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
        Write-Host "Podman was not found/not installed!"
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
        Write-Host "Podman was not found/not installed!"
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

function Set-Developer-Variables {
    ## Edit as required
    if ( -not ( $env:DEVELOPER -eq "Yes" )) { return }
    Write-Host "Setting Developer environment variables..."
    ## Dont send telemetry to Microsoft
    Set-Item -Path Env:\FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\POWERSHELL_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\DOTNET_UPGRADEASSISTANT_TELEMETRY_OPTOUT -Value $true
    Set-Item -Path Env:\DOTNET_CLI_TELEMETRY_OPTOUT -Value $true

    ## AZD get rid of annoying update prompt and opt out of telemetry
    Set-Item -Path Env:\AZD_SKIP_UPDATE_CHECK -Value $true
    Set-Item -Path Env:\AZURE_DEV_COLLECT_TELEMETRY -Value 'no'
    
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
        } else {
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

if ( ($env:IsDevBox ) -and (Get-Command "devbox") )  {
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
if ($env:STARSHIP_CONFIG -and (Test-Path "$starshipConfig" -PathType Leaf) -and $IsLanguagePermissive ) {
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

## Terraform shortcuts
function t { terraform.exe @args }
function tf { terraform.exe fmt @args}
function tv { terraform.exe validate @args }
function ti { terraform.exe init -upgrade @args}
## Sysinternal shortcuts
function handle { handle.exe init -nobanner @args}
 
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

## Won't display anything, unless less than 5GB
function checkdiskspace {
    if (-not ($IsLanguagePermissive -eq $true )) { return }
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

function Get-RDS-Drives {
    if ($IsLanguagePermissive) {
        Write-Host "Checking for Mapped Drives..."
        $CLSIDs = @()
        foreach($registryKey in (Get-ChildItem "Registry::HKEY_CLASSES_ROOT\CLSID" -Recurse -ErrorAction SilentlyContinue)){
            If (($registryKey.GetValueNames() | ForEach-Object {$registryKey.GetValue($_)}) -eq "Drive or folder redirected using Remote Desktop") {
                $CLSIDs += $registryKey
            }
        }
        $drives = @()
        foreach ($CLSID in $CLSIDs.PSPath) {
            $drives += (Get-ItemProperty $CLSID)."(default)"
        }
    }
}
#if ($VirtualMachine -eq $true) {
#    Get-RDS-Drives
#}

function Import-Nice-Modules {
    if ( -not [bool](Get-Module -ListAvailable -Name Terminal-Icons | Out-Null )) {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
    if ( -not [bool](Get-Module -ListAvailable -Name Az.Tools.Predictor | Out-Null )) {
        Import-Module Az.Tools.Predictor -ErrorAction SilentlyContinue
    }    
}
Import-Nice-Modules

function Set-Azure-Environment {
    
    ## if ( -not ( $env:DEVELOPER -eq "Yes" )) { return }

    $subscription_id = (Get-AzSubscription -ErrorAction SilentlyContinue).Id | Out-Null
    if (-not [string]::IsNullOrEmpty($subscription_id)) {
        Set-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Value $subscription_id
    } else {
        Remove-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant_id = (Get-AzTenant -ErrorAction SilentlyContinue).Id | Out-Null
    if (-not [string]::IsNullOrEmpty($tenant_id)) {
        Set-Item -Path Env:\AZURE_TENANT_ID -Value $tenant_id
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant_name = (Get-AzTenant -ErrorAction SilentlyContinue).Name | Out-Null
    if (-not [string]::IsNullOrEmpty($tenant_name)) {
        Set-Item -Path Env:\AZURE_TENANT_NAME -Value $tenant_name
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_NAME -Force -ErrorAction SilentlyContinue
    }
    if (-not [string]::IsNullOrEmpty($UPN)) {
        Set-Item -Path Env:\AZURE_USERNAME -Value $UPN
    } else {
        Remove-Item -Path Env:\AZURE_USERNAME -Force -ErrorAction SilentlyContinue
    }
}
#Set-Azure-Developer-Environment

function Check-Azure-Environment {
    ## If we have AZURE environment variables then we are good
    if (
        -not [string]::IsNullOrEmpty($env:AZURE_CLIENT_ID) -or
        -not [string]::IsNullOrEmpty($env:AZURE_SUBSCRIPTION_ID) -or
        -not [string]::IsNullOrEmpty($env:AZURE_TENANT_ID)
    ) {
        return $false
    }
    return $true
}
function Check-Graph-Token {
    ## If we have ACCESS_TOKEN variable we are good
    if ( -not [string]::IsNullOrEmpty($env:ACCESS_TOKEN) ) {
        return $true
    }
    return $false
}
function Check-Sharepoint-Token {
    ## If we have ACCESS_TOKEN_SHAREPOINT variable we are good
    if ( -not [string]::IsNullOrEmpty($env:ACCESS_TOKEN_SHAREPOINT) ) {
        return $true
    }
    return $false
}

function Create-Default-Env-File {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false
    
    if ( (Check-Azure-Environment) -eq $true ) {
        Write-Host "Writing out default .env file"
        @"
# $env:AZURE_TENANT_NAME .env file
AZURE_SUBSCRIPTION_ID=$env:AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID=$env:AZURE_TENANT_ID
AZURE_USERNAME=$env:UPN
"@ | Out-File -Encoding UTF8 -FilePath "$HOME/.env-default"
        Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env-default" -Force
        Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env" -Force
    } else {
        Write-Host "Not enough environment variables defined!"
        Write-Host " Run: Set-Azure-Environment" 
    }
}
#Create-Default-Env-File

function Import-Env-File {
    param(
        [Parameter(Mandatory)]
        [string]$EnvId,

        [bool]$silent = $false
    )
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

    # Decide candidate paths in order
    $paths = @()

    if ($env:OneDriveCommercial) {
        $paths += (Join-Path $env:OneDriveCommercial ".env-$envId")
    }
    if ($env:OneDrive) {
        $paths += (Join-Path $env:OneDrive ".env-$envId")
    }
    $paths += (Join-Path $HOME ".env-$envId")

    # Select the first existing path
    $Path = $null
    foreach ($p in $paths) {
        if (Test-Path -Path $p) {
            $Path = $p
            break
        }
    }
    
    if (-not (Test-Path -Path $Path)) {
        Write-Error "The .env file was not found: $envId"
        return $null
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
            if ($IsLanguagePermissive) {
                ## Make it permanent, if not constrained by PowerShell
                [System.Environment]::SetEnvironmentVariable($key, $val, 'User')
            } else {
                Set-ItemProperty -Path "HKCU:\Environment" -Name $key -Value $val
            }
            Set-Item -Path "Env:\$key" -Value "$val"
            
            Write-Verbose "Set `$Env:$key = '$val'"
        }
    }
    if ( ($null -eq $env:AZURE_TENANT_ID ) -and ($null -eq $env:AZURE_CLIENT_ID )) {
        Write-Host "Something is wrong with $envId file"
        return 
    }
    if (-not $silent ) {
        Write-Host "Portal Logon: https://entra.microsoft.com/?tenant=$env:AZURE_TENANT_ID"
        if ( $env:AZURE_CLIENT_ID ) {
            Write-Host "DELEGATION"
            Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -Scope User.Read -NoWelcome"
            Write-Host "Get-MgContext"
        }  else {
            Write-Host "AS USER"
            Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -Scope User.Read" -NoWelcome
            Write-Host "Get-MgContext"
        }
    }
    $PSDefaultParameterValues['*:Verbose']   = $preserve
}

function Get-Default-Env-File {
    Import-Env-File default -silent $true
}
Get-Default-Env-File

function Get-EntraID {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

    if ( -not $env:AZURE_TENANT_ID ) {
        throw "Environment variable AZURE_TENANT_ID not set"
    }
    $response = Invoke-RestMethod "https://login.microsoftonline.com/$env:AZURE_TENANT_ID/v2.0/.well-known/openid-configuration" -ErrorAction Stop
    if ($response ) {
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        $response | Format-List authorization_endpoint, token_endpoint, issuer, jwks_uri
        return $true
    } else {
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        throw "Tenant $env:AZURE_TENANT_ID was not found!"
        return $false
    }
}

function Get-Meta { ##IMDS
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

    $headers = @{ "Metadata" = "true" }
    $uri = "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -ErrorAction Stop
    if ($response ) {
        $response | Format-List 
    } else {
        throw "This machine is not running inside Azure"
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        return $false
    }
    $PSDefaultParameterValues['*:Verbose']   = $preserve
    return $true
}

function Get-Token { ##IMDS
    if (-not $env:ACCESS_TOKEN) {
        ## uses WAM broker 
        Connect-MgGraph -Scopes ".default" -UseDeviceAuthentication:$false -NoWelcome
        $token = (Get-MgContext).AccessToken
    } else {
        $token = $env:ACCESS_TOKEN
    }
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
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

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

    $PSDefaultParameterValues['*:Verbose']   = $preserve
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

function New-GraphRequestParams {
    <#
    .SYNOPSIS
        Builds a @params splat hashtable for Invoke-MgGraphRequest.

    .DESCRIPTION
        Supports GET/POST/PATCH/DELETE, optional query parameters,
        Microsoft Graph headers, and automatic JSON body conversion.

    .EXAMPLE
        $params = New-GraphRequestParams -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/me"

        $response = Invoke-MgGraphRequest @params
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET","POST","PATCH","DELETE","PUT")]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [hashtable]$Query,
        [hashtable]$Headers,
        $Body,
        [string]$AccessToken,
        [string]$OutputType = "Json"
    )

    #
    # Build final URI with query parameters
    #
    if ($Query) {
        $encoded = $Query.GetEnumerator() |
            ForEach-Object { "{0}={1}" -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode($_.Value) }

        if ($Uri.Contains("?")) {
            $Uri = "$Uri&$($encoded -join '&')"
        } else {
            $Uri = "$Uri?$($encoded -join '&')"
        }
    }

    #
    # Build headers
    #
    $finalHeaders = @{}

    if ($Headers) {
        foreach ($k in $Headers.Keys) {
            $finalHeaders[$k] = $Headers[$k]
        }
    }

    # Add Authorization header if token provided
    if ($AccessToken) {
        $finalHeaders["Authorization"] = "Bearer $AccessToken"
    }

    #
    # Build params hashtable
    #
    $params = @{
        Method     = $Method
        Uri        = $Uri
        OutputType = $OutputType
    }

    if ($finalHeaders.Count -gt 0) {
        $params["Headers"] = $finalHeaders
    }

    #
    # Add Body if provided
    #
    if ($PSBoundParameters.ContainsKey("Body")) {
        # Convert PowerShell objects to JSON automatically
        if ($Body -isnot [string] -and $Body -isnot [byte[]]) {
            $Body = ($Body | ConvertTo-Json -Depth 10)
        }

        $params["Body"] = $Body
    }

    return $params
}

function Get-SPODelegatedAccessToken {
    <#
    .SYNOPSIS
        Acquire a delegated SharePoint Online access token (Entra ID) for the signed-in user.

    .DESCRIPTION
        Uses OAuth 2.0 device code flow against the v2.0 endpoint to obtain
        a delegated access token for SharePoint Online (SPO).

        The token's audience (aud) will be the SPO resource:
            00000003-0000-0ff1-ce00-000000000000

    .PARAMETER Tenant
        Your Entra ID tenant, either as a domain (contoso.onmicrosoft.com)
        or GUID.

    .PARAMETER SharePointHost
        The SharePoint Online host used for scoping (e.g. contoso.sharepoint.com).

    .PARAMETER ClientId
        Public client application ID. By default uses the Microsoft 1st-party
        public client (Azure PowerShell / MSAL client). "1950a258-227b-4e31-a9cf-717495945fc2"

    .PARAMETER StoreInEnv
        If specified, the token is also stored in $env:ACCESS_TOKEN.

    .OUTPUTS
        [string] - The access token (JWT).
    #>

    [CmdletBinding()]
    param(
        [string]$Tenant = $Env:AZURE_TENANT_ID,

        [string]$SharePointHost = $Env:AZURE_SHAREPOINT,

        [string]$ClientId = $Env:AZURE_CLIENT_ID,

        [switch]$StoreInEnv = $true
    )

    # ----- Step 1: Request device code -----
    $scope = "https://${SharePointHost}.sharepoint.com/.default offline_access openid profile"

    $deviceCodeBody = @{
        client_id = $ClientId
        scope     = $scope
    }

    $deviceCodeUri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/devicecode"

    Write-Verbose "Requesting device code for tenant '$Tenant' and scope '$scope'..."
    $device = Invoke-RestMethod -Method POST -Uri $deviceCodeUri -Body $deviceCodeBody

    Write-Host ""
    Write-Host "To sign in, open the following URL in a browser and enter the code:" -ForegroundColor Cyan
    Write-Host "  URL : $($device.verification_uri)" -ForegroundColor Yellow
    Write-Host "  Code: $($device.user_code)" -ForegroundColor Yellow
    Write-Host ""

    # ----- Step 2: Poll token endpoint -----
    $tokenUri = "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token"

    $pollBody = @{
        grant_type  = "urn:ietf:params:oauth:grant-type:device_code"
        client_id   = $ClientId
        device_code = $device.device_code
    }

    $expiresIn   = [int]$device.expires_in
    $intervalSec = [int]$device.interval
    $startTime   = Get-Date

    Write-Verbose "Polling token endpoint every $intervalSec seconds for up to $expiresIn seconds..."

    $token = $null

    while (-not $token) {
        # Check timeout
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -ge $expiresIn) {
            throw "Device code has expired. Please run the function again to start a new sign-in."
        }

        try {
            $token = Invoke-RestMethod -Method POST -Uri $tokenUri -Body $pollBody
        }
        catch {
            $errorResponse = $_.ErrorDetails.Message
            if ($errorResponse -match "authorization_pending") {
                # User hasn't completed login yet – wait and retry
                Start-Sleep -Seconds $intervalSec
                continue
            }
            elseif ($errorResponse -match "slow_down") {
                # Service is asking us to slow down – wait a bit more
                Start-Sleep -Seconds ($intervalSec + 2)
                continue
            }
            else {
                throw "Failed to obtain token. Error response: $errorResponse"
            }
        }
    }

    $accessToken = $token.access_token

    if (-not $accessToken) {
        throw "Token response did not contain an access_token."
    }

    # ----- Optional: store in environment variable -----
    if ($StoreInEnv) {
        $env:ACCESS_TOKEN_SHAREPOINT = $accessToken
        $accesstoken | Set-Clipboard
        Write-Host "Stored access token in environment variable ACCESS_TOKEN_SHAREPOINT and in Clipboard."
    }

    Write-Host "Connect-PnPOnline -Url ""https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com"" -AccessToken "'$env:ACCESS_TOKEN_SHAREPOINT'
    Write-Host "Get-PnpConnection"
    return ##$accessToken
}

function Test-SharePoint {
    Get-SPODelegatedAccessToken
    Connect-PnPOnline -Url "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com" -AccessToken $env:ACCESS_TOKEN_SHAREPOINT
    Get-PnPAuthenticationRealm
    Get-PnpConnection
}

function Get-Token-Graph {  ## with Graph PowerShell Modules
    [CmdletBinding()]
    param(
        [string[]]$Scopes = @('User.Read')  ## e.g. @('Mail.ReadBasic','Mail.Read')
    )

    # Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    Write-Host "Requesting Access Token via Microsoft Graph PowerShell modules for scopes: $($Scopes -join ' ')" -ForegroundColor Cyan

    if ( (Check-Azure-Environment) -eq $false ) {
        throw "Correct environment variables are NOT defined!"
    }

    Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -Scopes $($Scopes -join ' ') -NoWelcome
    
    ## 'https://graph.microsoft.com/v1.0/me/messages'
    ## 'https://graph.microsoft.com/v1.0/users'
    ## 'https://graph.microsoft.com/v1.0/me'
    #New-GraphRequestParams -Method 'GET' -Uri 'https://graph.microsoft.com/v1.0/me' -OutputType = 'HttpResponseMessage'
    $params = @{
        Method     = 'GET'
        Uri        = 'https://graph.microsoft.com/v1.0/me'
        OutputType = 'HttpResponseMessage'
    }

    try {
        $response = Invoke-MgGraphRequest @params
    }
    catch {
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        throw "Get-Token call failed. $($_.Exception.Message)"
    }

    # Primary path: read the Bearer token from the *request* Authorization header
    $authHeader = $response.RequestMessage.Headers.Authorization
    if ($authHeader -and $authHeader.Scheme -eq 'Bearer' -and $authHeader.Parameter) {
        $accesstoken = $authHeader.Parameter
    } else {
        # Fallback: some SDK versions expose the token on the MgContext
        $accesstoken = (Get-MgContext).AccessToken
    }

    if ($accesstoken -and $accesstoken.Length -gt 1) {
        Set-Item -Path Env:\ACCESS_TOKEN -Value $accesstoken
        $accesstoken | Set-Clipboard
        Write-Host "Access token saved to ENV:ACCESS_TOKEN and copied to clipboard."
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $true
    }

    Write-Host "Access denied or token not available."
    
    $PSDefaultParameterValues['*:Verbose'] = $preserve

    return $false
}

function Get-Token-Device-Flow { ## without Graph Modules
    ## https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
    param(
        ## Provide if you want; otherwise we'll pick it up from env vars
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,
        
        [string]$ClientId,

        [string[]]$Scopes = @('User.Read')  ## e.g. @('Mail.ReadBasic','Mail.Read')
    )
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

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
    $clientCandidates = @(
        $ClientId,
        $env:AZURE_CLIENT_ID,  # Azure CLI / general
        $env:ARM_CLIENT_ID,    # Terraform/ARM conventions
        $env:AAD_CLIENT_ID     # some orgs use this
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $ClientId = $clientCandidates | Select-Object -First 1
    if (-not $ClientId) {
        throw "ClientId not provided and no environment variable (AZURE_CLIENT_ID/ARM_CLIENT_ID/AAD_CLIENT_ID) was found."
    }
    if ( (Check-Azure-Environment) -eq $false ) {
        throw "Correct environment variables are NOT defined!"
    }
    Write-Verbose "Using TenantId: $TenantId"
    Write-Verbose "Using ClientId: $ClientId"
    Write-Verbose "Using Scopes  : $($Scopes -join ' ')"
        
    # Request a device code for the given scopes
    $deviceCodeResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
        -Body @{
            client_id = $ClientId
            scope     = $($Scopes -join ' ')
        }

    Write-Host "Attempting to logon as Client_ID $ClientId to Tenant: $TenantId with these scopes: $Scopes"
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
                Set-Item -Path Env:\ACCESS_TOKEN -Value $tokenResponse.access_token 
                $tokenResponse.access_token | Set-Clipboard
                $PSDefaultParameterValues['*:Verbose']   = $preserve
                return $true
            }
        }
        catch {
            # Entra ID returns 'authorization_pending' until user completes login
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            $errormsg = $errorJson.error
            if ($errormsg -ne "authorization_pending") {
                Write-Warning "❌ Unexpected error: $($_.ErrorDetails.Message)"
                $PSDefaultParameterValues['*:Verbose']   = $preserve
                break
            }
        }
    }
    $PSDefaultParameterValues['*:Verbose']   = $preserve
    return $false
}

function Get-Token-Interactive { ## via Browser
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

        [ValidateNotNullOrEmpty()]
        [string]$ClientId,

        [string]$RedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient",

        [string[]]$Scopes = @('User.Read')  ## e.g. @('Mail.ReadBasic','Mail.Read')
    )

    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

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
    $clientCandidates = @(
        $ClientId,
        $env:AZURE_CLIENT_ID,  # Azure CLI / general
        $env:ARM_CLIENT_ID,    # Terraform/ARM conventions
        $env:AAD_CLIENT_ID     # some orgs use this
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $ClientId = $clientCandidates | Select-Object -First 1
    if (-not $ClientId) {
        throw "ClientId not provided and no environment variable (AZURE_CLIENT_ID/ARM_CLIENT_ID/AAD_CLIENT_ID) was found."
    }
    Write-Verbose "Using TenantId: $TenantId"
    Write-Verbose "Using ClientId: $ClientId"
    Write-Verbose "Using Scopes  : $Scopes"

    Write-Host "Attempting to logon as Client_ID $ClientId to Tenant: $TenantId with these scopes: $Scopes"
    # Build the authorize URL
    $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize" +
               "?client_id=$ClientId" +
               "&response_type=code" +
               "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
               "&response_mode=query" +
               "&scope=$([uri]::EscapeDataString($Scopes))" +
               "&state=12345"
    Write-Host $authUrl

    Write-Host "Opening browser for Entra ID sign-in..." -ForegroundColor Cyan
    Start-Process $authUrl

    Write-Host "`nAfter you sign in, you'll be redirected to a URL similar to:`n"
    Write-Host "$RedirectUri?code=YOUR_CODE_HERE&state=12345" -ForegroundColor Yellow
    Write-Host "`nCopy the 'code' value from that URL and paste it below.`n"

    # Prompt user for authorization code
    $authCode = Read-Host "Enter the authorization code"

    if ([string]::IsNullOrWhiteSpace($authCode)) {
        Write-Warning "No code entered. Aborting."
        return
    }

    # Exchange authorization code for access token
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
        Set-Item -Path Env:\ACCESS_TOKEN -Value $tokenResponse.access_token 
        $tokenResponse.access_token | Set-Clipboard
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        return $true
    } else {
        Write-Warning "Failed to retrieve access token."
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        return $false
    }
}

function Get-Token-MSAL {
    # Install once:
    # Install-Package Microsoft.Identity.Client -Source https://www.nuget.org/api/v2 -Scope CurrentUser
    Add-Type -Path "$env:USERPROFILE\.nuget\packages\microsoft.identity.client\*\lib\net472\Microsoft.Identity.Client.dll"

    $tenantId = $env.AZURE_TENANT_ID
    $clientId = $env.AZURE_CLIENT_ID  ##"04b07795-8ddb-461a-bbee-02f9e1bf7b46"  # Public client (Graph PowerShell / Azure CLI style)
    $scopes   = @("User.Read")

    $app = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId).
        WithAuthority("https://login.microsoftonline.com/$tenantId").
        WithDefaultRedirectUri().
        Build()

    $result = $app.AcquireTokenInteractive($scopes).ExecuteAsync().GetAwaiter().GetResult()

    $accessToken = $result.AccessToken    
    $accessToken | Set-Clipboard
    Write-Host "Access token copied to clipboard."
}

function Get-EntraUserInfo {
    <#
    .SYNOPSIS
        Retrieves userinfo from Entra ID using an existing access token.
    .DESCRIPTION
        Uses the OAuth 2.0 /userinfo endpoint.
        Requires an already-acquired access token in $env:ACCESS_TOKEN.
    #>
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

    if (-not $env:ACCESS_TOKEN) {
        throw "No ACCESS_TOKEN found in environment variables."
    }

    $endpoint = "https://graph.microsoft.com/oidc/userinfo"

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
        $response | Format-List
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        return $true
    }
    catch {
        throw "Failed to retrieve userinfo: $($_.Exception.Message)"
    }
    $PSDefaultParameterValues['*:Verbose']   = $preserve
    return false
}

function Get-Token-Info {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

    Install-OrUpdateModule JWTDetails
    Import-Module JWTDetails
    ## or goto: https://jwt-decoder.com/
    ##          https://jwt.ms
    $jwt = Get-JWTDetails $env:ACCESS_TOKEN
    if ( -not ($jwt) ) {
        Write-Host "Failed to decode token." -ForegroundColor Red
        $PSDefaultParameterValues['*:Verbose']   = $preserve
        return
    }
    $jwt.name
    $jwt.upn
    $jwt.app_displayname
    #$jwt.aud
    $jwt.iss
    $jwt.tid
    ## exp should be a UNIX timestamp (seconds since epoch)
    $expUnix = [long]$jwt.exp

    ## Convert exp to local DateTime
    $expiry = [DateTimeOffset]::FromUnixTimeSeconds($expUnix).ToLocalTime()

    ## Compute difference
    $now = Get-Date
    $minutesRemaining = [math]::Round(($expiry - $now).TotalMinutes, 2)
    if ($minutesRemaining -le 0) {
        Write-Host "Token has already expired!" -ForegroundColor Red
        Write-Host "Expired at: $expiry" -ForegroundColor Red                
    } else {
        Write-Host "Token expires in $minutesRemaining minutes"
    }
    $PSDefaultParameterValues['*:Verbose']   = $preserve
}

function Test-Token-Email { ## with Graph Modules
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false

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
    $PSDefaultParameterValues['*:Verbose']   = $preserve
}

function Test-Token-Access { ## with Graph Modules
 ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose']   = $false
    if (-not $env:ACCESS_TOKEN) {
        throw "No ACCESS_TOKEN found in environment variables."
    }
    $SecureAccessToken = ConvertTo-SecureString -String $env:ACCESS_TOKEN -AsPlainText -Force
    Connect-MgGraph -AccessToken $SecureAccessToken -NoWelcome
    Get-MgContext

    $PSDefaultParameterValues['*:Verbose']   = $preserve
}


function Get-EntraID-Info {
    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    # Retrieve the OpenID Connect metadata (no modules required)
    $openidConfig = Invoke-RestMethod -Uri "https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration"

    # Show top-level keys
    $openidConfig | Format-List
    $VerbosePreference = $preserve
}

##if (Get-Command 'azd' -ErrorAction SilentlyContinue) {
##    azd auth login --check-status
##}
## Show verbose messages
$VerbosePreference = 'Continue'

if ( ($env:DEVELOPER -eq "Yes") -and ($IsLanguagePermissive -eq $true) ) { 
    ## dotnet shell completions
    dotnet completions script pwsh | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
    azd completion powershell | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
}

function Set-FolderAclUsersModify {
    <#
    .SYNOPSIS
      Grant Modify to local Users (not Full Control) on a folder tree.

    .DESCRIPTION
      - Ensures elevation
      - (Optional) Takes ownership and sets owner to Administrators
      - (Optional) Breaks inheritance on the target folder (copies ACEs)
      - Removes explicit DENY ACEs for Users/Everyone (so ALLOW can apply)
      - Grants:
            SYSTEM         : FullControl
            Administrators : FullControl
            Users          : Modify
      - Uses well-known SIDs (locale-independent)
      - Applies recursively by default

    .PARAMETER Path
      Target folder path. Default: C:\workspaces

    .PARAMETER TakeOwnership
      Take ownership before ACL changes. Default: $true

    .PARAMETER BreakInheritance
      Break inheritance (copy existing ACEs). Default: $true

    .PARAMETER RemoveDeny
      Remove explicit DENY entries for Users/Everyone. Default: $true

    .PARAMETER Recurse
      Recurse into all children. Default: $true

    .PARAMETER WhatIf
      Shows what would happen if the command runs. No changes made.

    .EXAMPLE
      Set-FolderAclUsersModify -Path 'C:\workspaces' -Verbose

    .EXAMPLE
      Set-FolderAclUsersModify -Path 'D:\Data' -BreakInheritance:$false
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = 'C:\workspaces',

        [bool]$TakeOwnership   = $true,
        [bool]$BreakInheritance = $true,
        [bool]$RemoveDeny      = $true,
        [bool]$Recurse         = $true
    )

    begin {
        # Well-known SIDs (locale independent)
        $SidSystem        = '*S-1-5-18'        # SYSTEM
        $SidAdmins        = '*S-1-5-32-544'    # BUILTIN\Administrators
        $SidUsers         = '*S-1-5-32-545'    # BUILTIN\Users

        # Inheritance flags for files & folders
        $inheritFlags = '(OI)(CI)'

        function Invoke-Icacls {
            param([string[]]$Args)
            Write-Verbose ("icacls {0}" -f ($Args -join ' '))
            if ($PSCmdlet.ShouldProcess("icacls $($Args -join ' ')")) {
                & icacls @Args
            }
        }

        function Assert-Elevated {
            $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $p  = New-Object System.Security.Principal.WindowsPrincipal($id)
            if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw "This function must be run in an elevated PowerShell (Run as Administrator)."
            }
        }
    }

    process {
        try {
            # Sanity checks
            Assert-Elevated
            if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
                throw "Path not found or not a folder: $Path"
            }

            # Normalize path & optional long-path prefix for deep trees
            $target = (Resolve-Path -LiteralPath $Path).Path

            # 1) Take ownership (optional)
            if ($TakeOwnership) {
                if ($PSCmdlet.ShouldProcess($target, "Take ownership (recursive)")) {
                    & takeown /f "$target" /r /d y | Out-Null
                    Invoke-Icacls -Args @("$target", '/setowner', 'Users', '/t', '/c') | Out-Null
                }
            }

            # 2) Inheritance control
            if ($BreakInheritance) {
                ## Disable
                Invoke-Icacls -Args @("$target", '/inheritance:d', '/c') | Out-Null
            }
            else {
                ## Enable
                Invoke-Icacls -Args @("$target", '/inheritance:e', '/c') | Out-Null
            }

            # 3) Remove explicit DENY entries that would override our grant
            if ($RemoveDeny) {
                # These may no-op if none exist; that's fine.
                Invoke-Icacls -Args @("$target", '/remove:d', 'Users',    '/c') | Out-Null
                Invoke-Icacls -Args @("$target", '/remove:d', 'Everyone', '/c') | Out-Null
            }

            # 4) Grant the desired rights
            $recurseFlag = if ($Recurse) { '/t' } else { $null }

            # Keep SYSTEM/Admins Full Control
            Invoke-Icacls -Args @("$target", '/grant', "${SidSystem}:${inheritFlags}(F)",     $recurseFlag, '/c') | Out-Null
            Invoke-Icacls -Args @("$target", '/grant', "${SidAdmins}:${inheritFlags}(F)",     $recurseFlag, '/c') | Out-Null

            # Give Users Modify (NOT Full Control)
            Invoke-Icacls -Args @("$target", '/grant', "${SidUsers}:${inheritFlags}(M)",      $recurseFlag, '/c') | Out-Null

            # 5) Display resulting ACEs on the root for verification
            Write-Verbose "Final ACL (root):"
            & icacls "$target"
        }
        catch {
            throw "Set-FolderAclUsersModify failed: $($_.Exception.Message)"
        }
    }
}
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Bin"
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Workspaces"
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Scripts"

function Get-HttpsCertificateInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$fqdn,                 # e.g. "example.com" (hostname or IP)

        [int]$Port = 443,

        # Optional: save the leaf certificate as a .cer file
        [string]$ExportCerPath,

        # Connection timeout (ms)
        [int]$TimeoutMs = 8000,

        # Use proxy (Zscaler etc..)
        #[bool]$proxy = $true,

        # Optional: constrain TLS versions if needed (useful on older hosts)
        [System.Security.Authentication.SslProtocols]$TlsProtocols = (
            [System.Security.Authentication.SslProtocols]::Tls12 -bor
            [System.Security.Authentication.SslProtocols]::Tls13
        )
    )

    begin {
        # Ensure we're not in ConstrainedLanguage (common in locked-down hosts)
        if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
            Write-Host "Cannot inspect certificates: PowerShell LanguageMode is $($ExecutionContext.SessionState.LanguageMode)."
            exit
        }
        function Get-SubjectAltNames {
            param([System.Security.Cryptography.X509Certificates.X509Certificate2]$cert)
            $out = @()
            foreach ($ext in $cert.Extensions) {
                if ($ext.Oid.Value -eq '2.5.29.17') {
                    try {
                        $san = New-Object System.Security.Cryptography.AsnEncodedData($ext.Oid, $ext.RawData)
                        $text = $san.Format($true)
                        if ($text) {
                            $out += ($text -split "`r?`n" | Where-Object { $_ }) |
                                    ForEach-Object { ($_ -replace '^\s*DNS Name=\s*','').Trim() } |
                                    Where-Object { $_ -ne '' }
                        }
                    } catch { }
                }
            }
            $out | Select-Object -Unique
        }
    }

    process {
        # Prepare export path if requested
        if ($ExportCerPath) {
            $dir = Split-Path -Path $ExportCerPath -Parent
            if ($dir -and -not (Test-Path $dir)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        $client = [System.Net.Sockets.TcpClient]::new()
        $stream = $null
        $ssl    = $null

        try {
            $connectTask = $client.ConnectAsync($fqdn, $Port)
            if (-not $connectTask.Wait($TimeoutMs)) {
                throw "Timeout connecting to ${fqdn}:${Port} after ${TimeoutMs} ms."
            }

            $stream = $client.GetStream()
            $ssl    = [System.Net.Security.SslStream]::new($stream, $false, { param($s,$c,$ch,$e) $true })

            # Prefer modern overload if available (PS 7 / .NET 5+) to set protocols explicitly
            $authOptions = [System.Net.Security.SslClientAuthenticationOptions]::new()
            $authOptions.TargetHost   = $fqdn
            $authOptions.EnabledSslProtocols = $TlsProtocols
            try {
                $ssl.AuthenticateAsClient($authOptions)
            }
            catch {
                # Fallback for older .NET where options overload may not exist
                $ssl.AuthenticateAsClient($fqdn)
            }

            $remoteCert = $ssl.RemoteCertificate
            if (-not $remoteCert) {
                throw "No certificate presented by ${fqdn}:${Port}."
            }

            $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($remoteCert)

            # Build a simple chain (no revocation to avoid long waits on locked hosts)
            $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
            $chain.ChainPolicy.RevocationMode    = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chain.ChainPolicy.RevocationFlag    = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EndCertificateOnly
            $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreWrongUsage
            [void]$chain.Build($cert2)

            $san = Get-SubjectAltNames -cert $cert2

            if ($ExportCerPath) {
                [IO.File]::WriteAllBytes(
                    $ExportCerPath,
                    $cert2.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                )
            }

            # $cert2
            # Emit a clean object
            [PSCustomObject]@{
                Hostname           = $fqdn
                Port               = $Port
                OwnerSubject       = $cert2.Subject
                SubjectCN          = $cert2.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::DnsName, $false)
                Issuer             = $cert2.Issuer
#                NotBefore          = $cert2.NotBefore
#                NotAfter           = $cert2.NotAfter
#                IsExpired          = ([DateTime]::UtcNow -ge $cert2.NotAfter.ToUniversalTime())
#                Thumbprint         = $cert2.Thumbprint
#                SerialNumber       = $cert2.SerialNumber
#                SignatureAlgorithm = $cert2.SignatureAlgorithm.FriendlyName
#                KeyAlgorithm       = $cert2.PublicKey.Oid.FriendlyName
#                KeySizeBits        = $cert2.PublicKey.Key.KeySize
#                SANs               = $san
#                ChainStatus        = $chain.ChainStatus.Status.ToString()
#                ExportedCerPath    = $ExportCerPath
            }
        }
        finally {
            ## clean up
            if ($ssl)    { $ssl.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($client) { $client.Dispose() }
        }
    }
}

# Examples:
# Show owner/subject for a site
# Get-HttpsCertificateInfo -Fqdn "www.microsoft.com"
# Get-HttpsCertificateInfo -Fqdn "cnn.com"

# Export the certificate to a file as well
# Get-HttpsCertificateInfo -Fqdn "example.com" -ExportCerPath "C:\Temp\example.cer"

function Show-Toast-Message {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [int]$DurationMs = 5000   # how long to show the balloon
    )

    # Only show toasts in interactive user sessions
    if (-not [Environment]::UserInteractive) { return }

    if ( -not $IsLanguagePermissive) {
        Write-Host ("Toast messages aren't supported when PowerShell is not in FullLanguage mode")
        Write-Host $Title
        Write-Host $Message
        return        
    } 

    # Ensure required assemblies are available
    #try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -AssemblyName System.Drawing       -ErrorAction Stop
    #}
    #catch {
    #    Write-Warning "Windows Forms / Drawing not available in this session: $($_.Exception.Message)"
    #    return
    #}

    $notifyIcon = $null
    try {
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon

        # Try to use the current process icon; fall back to an information icon
        $procPath = (Get-Process -Id $PID).Path
        $icon = $null
        #try { $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($procPath) } catch {}
        #if (-not $icon) { $icon = [System.Drawing.SystemIcons]::Information }
        $icon = [System.Drawing.SystemIcons]::Information
 
        $notifyIcon.Icon            = $icon
        $notifyIcon.Visible         = $true
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText  = $Message

        # Show the notification
        $notifyIcon.ShowBalloonTip($DurationMs)

        # Give Windows time to display before disposing
        Start-Sleep -Milliseconds $DurationMs
    }
    finally {
        if ($notifyIcon) {
            $notifyIcon.Visible = $false
            $notifyIcon.Dispose()
        }
    }
}
#Show-Toast-Message -Title "Title" -Message "Message"

function Get-DefaultRouteAdapter {
    <#
    .SYNOPSIS
        Shows the network adapter used for the default route (internet egress).

    .DESCRIPTION
        Finds the adapter that owns the lowest-metric default route (0.0.0.0/0 or ::/0)
        and displays adapter name, interface index, gateway, and other useful info.

    .EXAMPLE
        Get-DefaultRouteAdapter

    .EXAMPLE
        Get-DefaultRouteAdapter -IncludeIPv6
    #>

    [CmdletBinding()]
    param(
        [switch]$IncludeIPv6
    )

    $routes = @("0.0.0.0/0")
    if ($IncludeIPv6) { $routes += "::/0" }

    $results = foreach ($prefix in $routes) {
        $route = Get-NetRoute -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
            Sort-Object -Property RouteMetric, InterfaceMetric |
            Select-Object -First 1

        if ($null -ne $route) {
            $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue

            [pscustomobject]@{
                AddressFamily       = if ($prefix -eq "::/0") { "IPv6" } else { "IPv4" }
                DefaultRouterAdapter = $adapter.Name
                InterfaceIndex      = $adapter.InterfaceIndex
                InterfaceDescription= $adapter.InterfaceDescription
                MACAddress          = $adapter.MacAddress
                Status              = $adapter.Status
                IPvGateway          = $route.NextHop
                RouteMetric         = $route.RouteMetric
                InterfaceMetric     = $route.InterfaceMetric
            }
        }
    }

    if ($results) {
        $results
    } else {
        Write-Warning "No default routes found."
    }
}

function Get-ZscalerClientState {
    <#
    .SYNOPSIS
        Gathers Zscaler-related configuration/state on a Windows endpoint (read-only).

    .DESCRIPTION
        Enumerates likely locations for Zscaler Client Connector and tunnel info:
        - Installed Apps (registry)
        - Services & Processes
        - System proxy (WinINET) and WinHTTP proxy
        - Network adapters & default route
        - Root certs containing "Zscaler"
        - Common file system paths

        NOTE: Uses broad matching (Zscaler|ZSA) to be resilient across versions.

    .PARAMETER IncludeRoutes
        Include default route and candidate tunnel routes.

    .PARAMETER AsJson
        Emit JSON instead of a PowerShell object.

    .EXAMPLE
        Get-ZscalerClientState -IncludeRoutes | Format-List

    .EXAMPLE
        Get-ZscalerClientState -AsJson | Out-File .\zscaler_state.json -Encoding utf8
    #>

    [CmdletBinding()]
    param(
        [switch]$IncludeRoutes,
        [switch]$AsJson
    )

    function Get-RegistryValues {
        param([string]$Path, [string[]]$Names)
        $h = @{}
        try {
            $item = Get-Item -LiteralPath $Path -ErrorAction Stop
            foreach ($n in $Names) {
                $h[$n] = (Get-ItemProperty -LiteralPath $Path -Name $n -ErrorAction SilentlyContinue).$n
            }
        } catch {}
        [pscustomobject]$h
    }

    # 1) Installed App (Uninstall registry)
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $installed = foreach ($root in $uninstallRoots) {
        Get-ChildItem $root -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PsPath -ErrorAction SilentlyContinue
            if ($p.DisplayName -match 'Zscaler|Client Connector|ZSA') {
                [pscustomobject]@{
                    DisplayName   = $p.DisplayName
                    DisplayVersion= $p.DisplayVersion
                    Publisher     = $p.Publisher
                    InstallLocation= $p.InstallLocation
                    UninstallString= $p.UninstallString
                    RegistryPath  = $_.PsPath
                }
            }
        }
    }

    # 2) Services / Processes
    $services  = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'Zscaler|ZSA' -or $_.Name -match 'Zscaler|ZSA' } |
                 Select-Object Name,DisplayName,Status,StartType
    $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Zscaler|ZSA' } |
                 ForEach-Object {
                    [pscustomobject]@{
                        Name = $_.Name; Id = $_.Id; Path = ($_.Path)
                    }
                 }

    # 3) Proxy (WinINET = user), WinHTTP = machine
    $inetCU = Get-RegistryValues -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Names ProxyEnable,ProxyServer,AutoConfigURL
    $inetLM = Get-RegistryValues -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Names ProxyEnable,ProxyServer,AutoConfigURL

    $winHttpProxy = try {
        $out = & netsh winhttp show proxy 2>$null
        if ($LASTEXITCODE -eq 0) { $out -join "`n" } else { $null }
    } catch { $null }

    # 4) Adapters / Routes (look for “Zscaler”/“ZSA”)
    $adapters = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'Zscaler|ZSA' -or $_.InterfaceDescription -match 'Zscaler|ZSA' } |
                Select-Object Name, InterfaceDescription, InterfaceIndex, Status, MacAddress, ifIndex

    $defaultRoute4 = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
                     Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
    $defaultAdapter = if ($defaultRoute4) {
        Get-NetAdapter -InterfaceIndex $defaultRoute4.InterfaceIndex -ErrorAction SilentlyContinue |
            Select-Object Name, InterfaceDescription, InterfaceIndex, Status
    }

    $routes = $null
    if ($IncludeRoutes) {
        $routes = Get-NetRoute -ErrorAction SilentlyContinue |
                  Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','::/0') -or $_.InterfaceIndex -in ($adapters.InterfaceIndex) } |
                  Sort-Object AddressFamily, RouteMetric, InterfaceMetric |
                  Select-Object AddressFamily, DestinationPrefix, NextHop, InterfaceIndex, RouteMetric, InterfaceMetric
    }

    # 5) Root certificates containing "Zscaler"
    $zscalerCerts = @()
    foreach ($store in @('Cert:\LocalMachine\Root','Cert:\CurrentUser\Root')) {
        $zscalerCerts += Get-ChildItem $store -ErrorAction SilentlyContinue |
            Where-Object { $_.Subject -match 'Zscaler' -or $_.Issuer -match 'Zscaler' } |
            Select-Object @{n='Store';e={$store}},
                          Subject, Issuer, NotAfter, Thumbprint, FriendlyName
    }

    # 6) Common file system paths
    $paths = @(
        'C:\Program Files\Zscaler',
        'C:\Program Files (x86)\Zscaler',
        'C:\ProgramData\Zscaler',
        "$env:LOCALAPPDATA\Zscaler",
        "$env:PROGRAMDATA\Zscaler"
    ) | ForEach-Object {
        if (Test-Path $_) { $_ }
    }

    $result = [pscustomobject]@{
      ComputerName       = $env:COMPUTERNAME
      UserName           = $env:USERNAME
      PowerShellVersion  = $PSVersionTable.PSVersion.ToString()
      InstalledApps      = $installed
      Services           = $services
      Processes          = $processes
      ProxyWinINET_User  = $inetCU
      ProxyWinINET_Machine = $inetLM
      ProxyWinHTTP       = $winHttpProxy
      DefaultAdapter     = $defaultAdapter
      DefaultRouteIPv4   = if ($defaultRoute4) { [pscustomobject]@{ NextHop=$defaultRoute4.NextHop; IfIndex=$defaultRoute4.InterfaceIndex; RouteMetric=$defaultRoute4.RouteMetric; InterfaceMetric=$defaultRoute4.InterfaceMetric } }
      ZscalerAdapters    = $adapters
      RoutesSummary      = $routes
      ZscalerRootCerts   = $zscalerCerts
      ExistingPaths      = $paths
    }

    if ($AsJson) {
        $result | ConvertTo-Json -Depth 6
    } else {
        $result
    }
}

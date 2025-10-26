#Requires -RunAsAdministrator

## Helper Function for JSON files
function Set-JsonValue {
    <#
      .SYNOPSIS
        Set a value inside a JSON-like PSCustomObject using a dotted path with optional [index] parts.

      .EXAMPLE
        $json = Get-Content .\settings.json -Raw | ConvertFrom-Json
        Set-JsonValue -JsonObject $json -Path 'profiles.defaults.colorScheme' -Value 'One Half Dark'

      .EXAMPLE
        Set-JsonValue -JsonObject $json -Path 'profiles.list[0].name' -Value 'PowerShell'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$JsonObject,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    # Helper: get exact property or $null
    function Get-ExactProperty([object]$obj, [string]$name) {
        $prop = $obj.PSObject.Properties | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        if ($prop) { return $prop.Value }
        return $null
    }

    # Helper: set exact property on PSCustomObject (create if missing)
    function Set-ExactProperty([object]$obj, [string]$name, $val) {
        $prop = $obj.PSObject.Properties | Where-Object { $_.Name -ceq $name } | Select-Object -First 1
        if ($prop) {
            $obj.$name = $val
        } else {
            $obj | Add-Member -NotePropertyName $name -NotePropertyValue $val
        }
    }

    # Parse tokens like:  "profiles", "list[0]", "name"
    # For each token, split into Name + optional Index
    $tokens = $Path -split '\.'
    try {
        $current = $JsonObject
        for ($i = 0; $i -lt $tokens.Length; $i++) {
            $token = $tokens[$i]

            # Extract name and optional [index]
            if ($token -match '^(?<name>[^\[\]]+)(\[(?<index>\d+)\])?$') {
                $name  = $Matches['name']
                $index = if ($Matches['index']) { [int]$Matches['index'] } else { $null }
            } else {
                throw "Invalid path token: '$token'"
            }

            $isLast = ($i -eq $tokens.Length - 1)

            # Ensure the property exists (create object/array as needed)
            $propVal = $null
            if ($current -is [System.Collections.IDictionary]) {
                # Hashtable scenario (rare if using ConvertFrom-Json, but safe)
                if (-not $current.Contains($name)) { $current[$name] = $null }
                $propVal = $current[$name]
            } else {
                $propVal = Get-ExactProperty -obj $current -name $name
                if ($null -eq $propVal) {
                    Set-ExactProperty -obj $current -name $name -val $null
                    $propVal = $null
                }
            }

            # If we need an array
            if ($null -ne $index) {
                if ($null -eq $propVal -or -not ($propVal -is [System.Collections.IList])) {
                    # create an array list to allow expansion
                    $propVal = [System.Collections.ArrayList]::new()
                    if ($current -is [System.Collections.IDictionary]) { $current[$name] = $propVal } else { $current.$name = $propVal }
                }
                # Expand array to fit index
                while ($propVal.Count -le $index) { [void]$propVal.Add($null) }

                if ($isLast) {
                    # Set final value
                    $propVal[$index] = $Value
                    if ($current -is [System.Collections.IDictionary]) { $current[$name] = $propVal } else { $current.$name = $propVal }
                } else {
                    # Descend into element, ensure it’s an object
                    if ($null -eq $propVal[$index] -or -not ($propVal[$index].psobject -and $propVal[$index].psobject.TypeNames)) {
                        $propVal[$index] = [PSCustomObject]@{}
                    }
                    $current = $propVal[$index]
                }
                continue
            }

            # No index: property is an object path segment
            if ($isLast) {
                # Final assignment
                if ($current -is [System.Collections.IDictionary]) { $current[$name] = $Value } else { $current.$name = $Value }
            } else {
                # Ensure intermediate object exists
                if ($null -eq $propVal -or -not ($propVal -is [psobject])) {
                    $propVal = [PSCustomObject]@{}
                    if ($current -is [System.Collections.IDictionary]) { $current[$name] = $propVal } else { $current.$name = $propVal }
                }
                $current = $propVal
            }
        }

        return ; ### $JsonObject
    }
    catch {
        Write-Error -Message "Set-JsonValue failed at path '$Path': $($_.Exception.Message)"
        throw
    }
}


function Set-MSTerminalSetting {
    param (
        [string]$settingsfile,
        [string]$BackgroundColor = "#335bc8", ## Default blue background
        [string]$ForegroundColor = "#FFFFFF", ## Default white text
        [int]$opacity = 97, ## Default opacity
        [string]$BackgroundImage = "$env:ALLUSERSPROFILE\logo.png", # "ms-appdata:///Roaming/terminal_cat.jpg", ## background image
        [string]$TabColor = "#012456",
        [string]$face = "Cascadia Code NF", ## Default font
        [int]$FontSize = 12, ## Default font size
        [string]$scheme = "Campbell Powershell"
    )
    
    Write-Output "Settings file: $settingsfile"

    ## Check if the settings file exists
    if (-not (Test-Path $settingsfile  -PathType Leaf)) {
        Write-Output "Settings file not found at: $settingsfile. Creating a new one."
        $json = @{
            profiles = @{
                defaults = @{}
            }
        }
        $json | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $settingsfile -Force
    }

    if (-not (Test-Path $BackgroundImage  -PathType Leaf)) {
        $BackgroundImage = $null
    }

    ## Read the settings
    $json = Get-Content -Path $settingsfile -Raw | ConvertFrom-Json -Depth 10

    ## Ensure the profiles object exists
    if (-Not $json.profiles) {
        $json.profiles = @{}
    }

    ## Ensure the profiles.defaults section exists
    if (-Not $json.profiles.defaults) {
        $json.profiles.defaults = @{}
    }

    ## Global
    Set-JsonValue -JsonObject $json -Path "confirmCloseAllTabs" -value $false
    Set-JsonValue -JsonObject $json -Path "alwaysShowTabs" -value $true
    Set-JsonValue -JsonObject $json -Path "copyOnSelect" -Value $true
    Set-JsonValue -JsonObject $json -Path "copyFormatting" -Value $false
    Set-JsonValue -JsonObject $json -Path "centerOnLaunch" -Value $false
    Set-JsonValue -JsonObject $json -Path "showMarksOnPaste" -Value $false
    Set-JsonValue -JsonObject $json -Path "bellStyle" -Value $false
    Set-JsonValue -JsonObject $json -Path "backgroundImageOpacity" -Value [float]"0.25"
    Set-JsonValue -JsonObject $json -Path "background" -Value $BackgroundColor
    Set-JsonValue -JsonObject $json -Path "foreground" -Value $ForegroundColor
    Set-JsonValue -JsonObject $json -Path "opacity" -Value $opacity
    Set-JsonValue -JsonObject $json -Path "backgroundImageAlignment" -Value "bottomRight"
    Set-JsonValue -JsonObject $json -Path "backgroundImageStretchMode" -Value "none"
    if ( Test-Path "$BackgroundImage" ) {
        Set-JsonValue -JsonObject $json -Path "backgroundImage" -Value $BackgroundImage
    } else {
        Write-Host "$BackgroundImage NOT found!"
    }
    Set-JsonValue -JsonObject $json -Path "focusFollowMouse" -Value $true
    #Set-JsonValue -JsonObject $json -Path "startupActions" -Value "newTab -p 'PowerShell'; newTab -p 'Headless Helper'"
    #Set-JsonValue -JsonObject $json -Path "wt -p "Command Prompt" `; split-pane -p "Windows PowerShell" `; split-pane -H wsl.exe

    ## Profiles
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.historySize" -Value 50000
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.snapOnInput" -Value $true
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.bellStyle" -Value "none"
   
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.useAcrylic" -Value $true
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.useAcrylicInTabRow" -Value $true
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.acrylicOpacity" -Value 0.75
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.cursorColor" -Value "#FFFFFF"
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.scrollbarState" -Value "always"
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.colorScheme" -Value $scheme
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.tabColor" -Value $tabColor
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.useAcrylicInTabRow" -Value $true
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.font.face" -Value $face
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.font.size" -Value $FontSize
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.font.weight" -Value "normal"
    Set-JsonValue -JsonObject $json -Path "multiLinePasteWarning" -Value $false
    Set-JsonValue -JsonObject $json -Path "BellSound" -Value ""
    
    ## Write the updated settings back
    $backupPath = "$settingsfile.bak"
    Copy-Item -Path $settingsfile -Destination $backupPath -Force
    Write-Output "Backup created at: $backupPath"

    $json | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsfile -Force
    Write-Output "Terminal settings updated successfully. Restart Microsoft Terminal to apply changes."
}
## Terminal (unpackaged: Scoop, Chocolately, etc): $env:{LOCALAPPDATA}\Microsoft\Windows Terminal\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    Write-Output "MS Terminal Settings for unpackaged version..."
    Set-MSTerminalSetting -settingsfile $settingsfile
}

## Terminal (preview release): %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    ##Remove-Item $settingsfile -Force
    Write-Output "MS Terminal Settings for preview version..."
    ##Set-MSTerminalSetting $settingsfile
}

## Terminal (stable / general release): $env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    Write-Output "MS Terminal Settings for stable version..."
    Set-MSTerminalSetting -settingsfile $settingsfile
}

## Add or Remote Directory from the Path, add check to see if it is already there first
function Add-DirectoryToPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Directory,

        [ValidateSet('User','System')]
        [string]$Scope = 'User'
    )

    # Normalize the path (remove trailing slash, resolve relative paths)
    $resolvedPath = (Resolve-Path -Path $Directory).Path.TrimEnd('\')

    # Read the current PATH value
    if ($Scope -eq 'User') {
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    } else {
        $currentPath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    }

    # Split PATH into individual entries
    $pathEntries = $currentPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    # Check if the path already exists (case-insensitive)
    if ($pathEntries -contains $resolvedPath) {
        Write-Host "✅ '$resolvedPath' is already in the $Scope PATH."
        return
    }

    # Append the new path
    $newPath = ($pathEntries + $resolvedPath) -join ';'

    if ($PSCmdlet.ShouldProcess("$Scope PATH", "Add '$resolvedPath'")) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
        Write-Host "✅ Added '$resolvedPath' to the $Scope PATH."
    }
}

## Detailed example
## https://raw.githubusercontent.com/microsoft/artifacts-credprovider/refs/heads/master/helpers/installcredprovider.ps1
function Install-NuGetCredentialProviderforAzureArtefacts {
    Invoke-Expression "& { $(Invoke-RestMethod https://aka.ms/install-artifacts-credprovider.ps1) }"
    return (Test-Path "$HOME\.nuget\plugins\netcore\CredentialProvider.Microsoft")
}
## Install Azure Arctefacts Credential Provider
#Install-NuGetCredentialProviderforAzureArtefacts

## Generate StrongPassword for developers, used in scripts such as SQL Server installations
if ( [string]::IsNullOrWhiteSpace($env:STRONGPASSWORD)) {
    Write-Output "Generating a random password retained as an environment variable..."
    ## All uppercase and lowercase letters, all numbers and some special characters.
    ## Make sure the first character is a letter
    $randompwd = @()
    $firstcharlist = @()
    $firstcharlist += [char]65..[char]90  ## A to Z
    $firstcharlist += [char]97..[char]122 ## a to z
    $randompwd += ($firstcharlist[(Get-Random -Minimum 0 -Maximum $firstcharlist.Length)])
    $charlist = @()
    $charlist += [char]33 ## !
    $charlist += [char]37 ## %
    $charlist += [char]38 ## &
    $charlist += [char]48..[char]57  ## 0 to 9
    $charlist += [char]91  ## [
    $charlist += [char]65..[char]90  ## A to Z
    $charlist += [char]97..[char]122 ## a to z
    $charlist = -Join $charlist
    $passwordLength = 32  # Set the desired password length
    for ($i = 1; $i -lt $passwordLength; $i++) {
        $randompwd += ($charlist[(Get-Random -Minimum 0 -Maximum $charlist.Length)])
    }
    ## Join all the individual characters together into one string using the -JOIN operator
    $randompwd = -Join $randompwd
    Write-Output "Generated Password: $randompwd"

    [Environment]::SetEnvironmentVariable('STRONGPASSWORD', "$randompwd", 'User')
}

Write-Output ("Setting Environment Variables for Developers...") 
## Get UPN (User Principal)
$getupn = @(whoami /upn)
if ( -not ([string]::IsNullOrWhiteSpace($getupn))) {
    [Environment]::SetEnvironmentVariable('UPN', "$getupn", 'User')
    $env:UPN = [System.Environment]::GetEnvironmentVariable("UPN", "User")
}
## Share environment variables between Windows and WSL
## https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
[Environment]::SetEnvironmentVariable('WSLENV', 'OneDriveCommercial/p:STRONGPASSWORD:USERDNSDOMAIN:USERDOMAIN:USERNAME:UPN', 'User')

## Dont send telemetry to Microsoft
[Environment]::SetEnvironmentVariable('FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT', '1', 'User')
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_UPGRADEASSISTANT_TELEMETRY_OPTOUT', '1', 'User') ## opt-out of the telemetry being send to Microsoft
[Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'User') ## opt-out of the telemetry being send to Microsoft

## .Net environment variables: https://learn.microsoft.com/en-us/dotnet/core/tools/dotnet-environment-variables
## Note: Generally speaking a value set in the project file or runtimeconfig.json has a higher priority than the environment variable.
[Environment]::SetEnvironmentVariable('DOTNET_GENERATE_ASPNET_CERTIFICATE', 'false', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_NOLOGO', 'yes', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_EnableDiagnostics_Debugger', '1', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_EnableDiagnostics_Profiler', '1', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_ADD_GLOBAL_TOOLS_TO_PATH', '1', 'User') ## this is default
[Environment]::SetEnvironmentVariable('COREHOST_TRACE', '0', 'User')
[Environment]::SetEnvironmentVariable('COREHOST_TRACEFILE', 'corehost_trace.log', 'User')
[Environment]::SetEnvironmentVariable('DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE', 'true', 'User')
[Environment]::SetEnvironmentVariable('COREHOST_TRACE_VERBOSITY', '4', 'User')
## 4 (All)- all tracing information is written
## 3 (Info, Warn, Error)
## 2 (Warn & Errors)
## 1 (Only Errors)
[Environment]::SetEnvironmentVariable('SuppressNETCoreSdkPreviewMessage', 'true', 'User') ## invoking dotnet won't produce a warning when a preview SDK is being used.
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

Write-Output ("Ensuring WSL is upto date...") 
## ensure WSL is upto date, can only be done per user (not system)
Start-Process -FilePath "wsl" -ArgumentList "--status" -NoNewWindow -Wait -PassThru
Start-Process -FilePath "wsl" -ArgumentList "--update" -NoNewWindow -Wait -PassThru

function Set-DockerDesktopBestPractices {
    $configPath = "$env:APPDATA\Docker\settings.json"
    if (-Not (Test-Path $configPath)) {
        Write-Host "Creating new Docker Desktop settings file..."
        New-Item -Path $configPath -ItemType File -Force | Out-Null
        $currentConfig = @{}
    }
    else {
        Write-Host "Loading existing Docker Desktop settings..."
        $currentConfig = Get-Content $configPath | ConvertFrom-Json
    }

    # Docker Best Practices configuration
    $defaultConfig = @{
        "version"              = 3
        "cpuCount"             = 4
        "memoryMiB"            = 8192
        "swapMiB"              = 1024
        "diskSizeMiB"          = 64000
        "useProxy"             = $false
        "httpProxy"            = ""
        "httpsProxy"           = ""
        "noProxy"              = ""
        "exposeDockerAPIOnTCP2375" = $false      # Don’t expose insecure API
        "hosts"                = @("npipe:////./pipe/docker_engine") # Local access only
        "showTrayIcon"         = $true
        "autoStart"            = $true
        "hideDesktopIcon"      = $false
        "wslIntegration"       = @{"docker-desktop" = $true }  # Adjust for installed WSL distros
        "kubernetesEnabled"    = $false
        "kubernetesVersion"    = ""
        "telemetryEnabled"     = $true
        "experimentalFeatures" = $false
        "gpuSupport"           = $false
        "sharedDirs"           = @("$env:HOME", "C:\Workspaces")
        "resources"            = @{
            "cpuCount"    = 4
            "memoryMiB"   = 8192
            "swapMiB"     = 1024
            "diskSizeMiB" = 64000
        }
    }

    # Merge user-provided config if any
    if ($currentConfig) {
        foreach ($key in $currentConfig.Keys) {
            $defaultConfig[$key] = $currentConfig[$key]
        }
    }

    # Save configuration to settings.json
    $configPath = "$env:APPDATA\Docker\settings.json"
    if (-Not (Test-Path $configPath)) {
        New-Item -Path $configPath -ItemType File -Force | Out-Null
    }

    $defaultConfig | ConvertTo-Json -Depth 10 | Set-Content $configPath -Force
    Write-Host "Docker Desktop configuration applied at $configPath"
}
#Set-DockerDesktopBestPractices

function Set-DockerDesktop {

    # Optionally enable WSL 2
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "Enabling WSL 2..."
        wsl --install --no-distribution --no-launch
    }

    $dockerExe = (Get-Item Env:ProgramFiles).Value + "\Docker\Docker Desktop.exe"

    if (-not (Test-Path $dockerEXE )) {
        winget install docker.Desktop
    }

    # Add current user to docker-users group
    Write-Host "Adding user $env:USERNAME to 'docker-users' group..."
    # Check if 'docker-users' group exists before adding user
    if (Get-LocalGroup -Name "docker-users" -ErrorAction SilentlyContinue) {
        Add-LocalGroupMember -Group "docker-users" -Member $env:USERNAME -ErrorAction SilentlyContinue
    }

    if (Test-Path $dockerExe) {
        Write-Host "Starting Docker Desktop service..."
        Stop-Service com.docker.service
        Set-Service -Name com.docker.service -StartupType Automatic
        Start-Service com.docker.service
    }
}
#Set-DockerDesktop

## Azure CLI configuration
try {
    ## Remove configuration files - if install is corrupt
    ##if (Test-Path "$($env:USERPROFILE)\.azure\") {
    ##    Remove-Item "$($env:USERPROFILE)\.azure\" -Recurse -Force -ErrorAction SilentlyContinue
    ##}
    az config set extension.use_dynamic_install=yes_without_prompt
    az config set core.allow_broker=true
    az config set core.survey_message=false
    ## not maintained - so turn it off, just in case
    az config set auto-upgrade.enable=no
    ##az account clear
    ##az fzf install
    ## Upgrade Azure CLI
    ## az upgrade --yes
    az version
    ## az ad user show --id (Get-Item Env:UPN).Value
    ## az ad signed-in-user show
}
catch {
    Write-Output "An error occurred while configuring Azure CLI: $_" 
    Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
    Write-Output "Exception Message: $($_.Exception.Message)" 
    Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
}

## git config for http://github.com
## type "C:\Program Files\Git\etc\gitconfig"
try {
    git config --global color.ui true
    ## git config --global user.name `"$($env:USERNAME)`"
    git config --global user.name `"webstean@gmail.com`"
    if ($env:UPN) {
        git config --global user.email "(Get-Item Env:UPN).Value"
    }
    git config --global core.autocrlf true          # per-user solution
    # git config --global http.sslbackend schannel
    # git config --global http.sslVerify false ## totally disable TLS/SLS certification verification (terible idea!)
    git --no-pager config list
    # Enables the Git repo to use the commit-graph file, if the file is present 
    git config --local core.commitGraph true
    # Update the Git repository’s commit-graph file to contain all reachable commits
    git commit-graph write --reachable

    # Generate the DotNet dev certificate
    $devcertname = (Get-Item Env:OneDrive).Value + "\dotnet-dev-certificate.pfx"
    $devcertpassword = (Get-Item Env:OneDrive).Value + "\dotnet-dev-certificate-password.txt"
    if (-not (Test-Path "$devcertname")) {
        dotnet dev-certs https --clean
        dotnet dev-certs https --trust --quiet --check
        if ( -not (Get-Item -ErrorAction SilentlyContinue Env:STRONGPASSWORD).Value ) { 
            if ($randompwd) { 
                dotnet dev-certs https --export-path "$devcertname" --password "$randompwd"
            }
        } else {
            dotnet dev-certs https --export-path "$devcertname" --password (Get-Item  -ErrorAction SilentlyContinue Env:STRONGPASSWORD).Value
        }
    }
}
catch {
    Write-Output "An exception occurred: $_" 
    Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
    Write-Output "Exception Message: $($_.Exception.Message)" 
    Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
}

## Unpin Microsoft Store on taskbar
function Remove-MicrosoftStore-Taskbar-Icon {
    # Define the application name to unpin
    $appName = "Microsoft Store"

    # Access the taskbar items and filter for the specified application
    $taskbarItems = (New-Object -ComObject Shell.Application).NameSpace('shell:::{4234d49b-0245-4df3-b780-3893943456e1}').Items()
    $appItem = $taskbarItems | Where-Object { $_.Name -eq $appName }

    # Find the "Unpin from taskbar" verb and execute it
    $appItem.Verbs() | Where-Object { $_.Name.Replace('&', '') -match 'Unpin from taskbar' } | ForEach-Object { $_.DoIt() }
}
Remove-MicrosoftStore-Taskbar-Icon

function New-CodeSigningCertificate {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string]$CertName = "MyCodeSigningCert",
        [Parameter()]
        [System.Security.SecureString]$PfxPassword = (ConvertTo-SecureString -String (Get-Item Env:STRONGPASSWORD).Value -AsPlainText -Force),
        [string]$OutputPath = "$env:USERPROFILE\Desktop"
    )

    try {
        # Ensure output path exists
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $pfxPath = Join-Path $OutputPath "$CertName.pfx"
        $cerPath = Join-Path $OutputPath "$CertName.cer"
        $securePass = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText

        Write-Host "==> Creating self-signed code signing certificate..."
        $cert = New-SelfSignedCertificate -Type CodeSigningCert `
            -Subject "CN=MyCodeSigningCert" `
            -KeyExportPolicy Exportable `
            -CertStoreLocation "Cert:\LocalMachine\My" `
            -KeyLength 2048 `
            -NotAfter (Get-Date).AddYears(2) `
            -Type CodeSigningCert `
            -KeySpec Signature `
            -KeyLength 2048 `
            -HashAlgorithm SHA256 `

        Write-Host "Created certificate with Thumbprint:" $cert.Thumbprint

        Write-Host "==> Exporting certificate..."
        Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePass | Out-Null
        Export-Certificate    -Cert $cert -FilePath $cerPath | Out-Null
        Write-Host "PFX exported to $pfxPath"
        Write-Host "CER exported to $cerPath"

        #Write-Host "==> Importing certificate into Trusted Root..."
        #Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
    }

    catch {
        Write-Output "An exception occurred: $_" 
        Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
        Write-Output "Exception Message: $($_.Exception.Message)" 
        Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
    }
}

function New-CodeSigningCertificate {
    try {

        Write-Host "==> Signing script: $ScriptPath"
        $signingCert = Get-ChildItem Cert:\CurrentUser\My\$($cert.Thumbprint)
        Set-AuthenticodeSignature -FilePath $ScriptPath -Certificate $signingCert | Out-Null

        $signature = Get-AuthenticodeSignature -FilePath $ScriptPath
        Write-Host "Signature status: $($signature.Status)"

        ## Uncomment the following line to sign a script file
        ## Set-AuthenticodeSignature -FilePath <FilePath> -Certificate $env:CodeSigningCertificate
    }
    catch {
        Write-Output "An exception occurred: $_" 
        Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
        Write-Output "Exception Message: $($_.Exception.Message)" 
        Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
    }
}
function Set-CodeSigningCertificate {
    ## List of Code Signing Certificates
    $NumberCodeSigningCertificates = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert | Measure-Object).Count
    Write-Output "Looking for code signing certificates..." 

    if ($NumberCodeSigningCertificates -eq 0) {
        Write-Output "Number of Code Signing Certificates: $NumberCodeSigningCertificates"
    }
    else {
        ## Set Code Signing Certificate - only the first one found
        ## Note: Code Signing certificates must have a private key, otherwise the certificates cannot be used for signing.
        Write-Output "Number of Code Signing Certificates: $NumberCodeSigningCertificates"

        $cert = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert)[0]
        [Environment]::SetEnvironmentVariable('CodeSigningCertificate', "$cert", 'User')
        $env:CodeSigningCertificate = [System.Environment]::GetEnvironmentVariable("CodeSigningCertificate", "User")

        Write-Output "env:CodeSigningCertificate = $env:CodeSigningCertificate"
    }
}
# Set-CodeSigningCertificate

$BIN = "$env:SystemDrive\BIN"
Add-MpPreference -ExclusionPath $BIN
Add-DirectoryToPath -Directory "${BIN}" -Scope "User"

Write-Output ("Configuring Oh My Posh, if it isn't already installed...")
## Oh My Posh
If (Test-Path -Path "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" -PathType Leaf ) {
    if (!(Test-Path -Path $PROFILE.AllUsersAllHosts)) {
        New-Item -ItemType File -Path $PROFILE.AllUsersAllHosts -Force -ErrorAction Ignore
    }
    ### Winget sets the POSH_THEMES_PATH variable
    ### FYI: Meslo is the default font for Windows Terminal
    ## $env:POSH_THEMES_PATH = [System.Environment]::GetEnvironmentVariable("POSH_THEMES_PATH","User")
    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\cloud-native-azure.omp.json"
    ### Init in profile
    ## Option #1
    #oh-my-posh init pwsh | Invoke-Expression
    ## Option #2
    #& ([ScriptBlock]::Create((oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\\cloud-native.omp.json" --print) -join "`n"))
    ## Create Profile
    # Create Powershell Profile
    if (!(Test-Path -Path $PROFILE.AllUsersAllHosts)) {
        New-Item -ItemType File -Path $PROFILE.AllUsersAllHosts -Force -ErrorAction Ignore
    }
    #New-Item -Path $PROFILE -Type File -Force
    #"& ([ScriptBlock]::Create((oh-my-posh init pwsh --config `"$env:POSH_THEMES_PATH\cloud-native.omp.json`" --print) -join `"`n`"))" | Out-File $PROFILE
    ## exclude from Defender AV - Oh-My-Posh
    $exclusion = [Environment]::GetFolderPath(“localapplicationdata”) + "\Programs\oh-my-posh"
    Add-MpPreference -ExclusionPath $exclusion
    $exclusion = [Environment]::GetFolderPath(“UserProfile”)
    Add-MpPreference -ExclusionPath $exclusion
    #### wt new-tab "cmd" `; split-pane -p "Windows PowerShell" `; split-pane -H wsl.exe
}
else {
    Write-Output("Skipping... Oh-My-Posh not found!")
}

Add-MpPreference -ExclusionPath 'C:\Program Files\starship\bin'

## Define the path for the .log extension and the program path
$extensionKey = "HKCU:\Software\Classes\.log"

# Define paths and program to associate
$extensionKey = "HKCU:\Software\Classes\.log"
$fileTypeKey = "HKCU:\Software\Classes\LogExpertFile"
$commandKey = "$fileTypeKey\shell\open\command"
$programPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\zarunbal.LogExpert_Microsoft.Winget.Source_8wekyb3d8bbwe\logexpert.exe"

# Ensure the .log extension is associated with LogExpertFile
if (-not (Test-Path $extensionKey)) {
    New-Item -Path $extensionKey -Force
}
Set-ItemProperty -Path $extensionKey -Name "(Default)" -Value "LogExpertFile"

# Ensure LogExpertFile key exists
if (-not (Test-Path $fileTypeKey)) {
    New-Item -Path $fileTypeKey -Force
}

# Create the shell\open\command key
if (-not (Test-Path $commandKey)) {
    New-Item -Path $commandKey -Force
}

# Set the command to open LogExpert for LogExpertFile type
Set-ItemProperty -Path $commandKey -Name "(Default)" -Value "`"$programPath`" `"%1`""

# Now, set LogExpert as the default app for .log files
$defaultAppProgID = "LogExpertFile"
$assocKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.log"

# Remove old file associations (if any)
if (Test-Path $assocKey) {
    Remove-Item -Path $assocKey -Recurse -Force
}

# Set the file extension association for .log to the LogExpertFile type
New-Item -Path $assocKey -Force
Set-ItemProperty -Path $assocKey -Name "UserChoice" -Value @{
    Progid = $defaultAppProgID
}
#cmd.exe /c assoc .log=LogExpertFile
#cmd.exe /c ftype LogExpertFile="$env:LOCALAPPDATA\Microsoft\WinGet\Packages\zarunbal.LogExpert_Microsoft.Winget.Source_8wekyb3d8bbwe\logexpert.exe" "%1"

#dotnet tool install -g dotnet-aspnet-codegenerator
#npm install -g @azure/static-web-apps-cli
#swa --version


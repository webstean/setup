#Requires -RunAsAdministrator

## Helper Function for JSON files
function Set-JsonValue {
    ## Example usage: Set-JsonValue -JsonObject $json -Path "profiles.defaults.colorScheme" -Value "One Half Dark"
    param(
        [Parameter(Mandatory)][object]$JsonObject,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    # Split path into segments
    $parts = $Path -split '\.'

    $current = $JsonObject
    for ($i = 0; $i -lt $parts.Length; $i++) {
        $name = $parts[$i]

        # Last part = set value
        if ($i -eq $parts.Length - 1) {
            if (-not $current.PSObject.Properties.Match($name)) {
                $current | Add-Member -NotePropertyName $name -NotePropertyValue $Value
            }
            $current.$name = $Value
        }
        else {
            # Ensure intermediate object exists
            if (-not $current.PSObject.Properties.Match($name)) {
                $current | Add-Member -NotePropertyName $name -NotePropertyValue ([PSCustomObject]@{})
            }
            $current = $current.$name
        }
    }
}


function Set-MSTerminalSetting {
    param (
        [string]$settingsfile,
        [string]$BackgroundColor = "#335bc8", ## Default blue background
        [string]$ForegroundColor = "#FFFFFF", ## Default white text
        [int]$opacity = 97, ## Default opacity
        [string]$BackgroundImage = $null, # "ms-appdata:///Roaming/terminal_cat.jpg", ## background image
        [string]$TabColor = "#012456",
        [string]$font = "FiraCode Nerd Font", ## Default font
        [int]$FontSize = 10, ## Default font size
        [string]$scheme = "Campbell Powershell"
    )

    try {

        ## Check if the settings file exists
        if (-not (Test-Path $settingsfile  -PathType Leaf)) {
            exit 1
            Write-Output "Settings file not found at: $settingsfile. Creating a new one."
            $json = @{
                profiles = @{
                    defaults = @{}
                }
            }
            $json | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $settingsfile -Force
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

        ## Modify or add properties
        #Set-JsonValue -JsonObject $json -Path "centerOnLaunch" -Value $false
        Set-JsonValue -JsonObject $json -Path "copyOnSelect" -Value $true

        #       if (-NOT $json.PSObject.Properties["centerOnLaunch"]) {
        #            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "centerOnLaunch" -Value $true
        #        }
        #        else {
        #            $json.centerOnLaunch = $true
        #        }
        #        if (-NOT $json.PSObject.Properties["copyOnSelect"]) {
        #            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "copyOnSelect" -Value $true
        #        }
        #        else {
        #            $json.copyOnSelect = $true
        #        }

        if (-NOT $json.PSObject.Properties["showMarksOnPaste"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "showMarksOnPaste" -Value $false
        }
        else {
            $json.showMarksOnPaste = $false
            $json.global.showMarksOnPaste = $false
        }

        ## Modify or add defaults section
        if (-NOT $json.profiles.defaults.PSObject.Properties["bellStyle"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "bellStyle" -Value "none"
        }
        else {
            $json.profiles.defaults.bellStyle = "none"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["backgroundImageOpacity"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "backgroundImageOpacity" -Value [float]"0.25"
        }
        else {
            $json.profiles.defaults.backgroundImageOpacity = [float]"0.25"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["background"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "background" -Value $BackgroundColor
        }
        else {
            $json.profiles.defaults.background = $BackgroundColor
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["foreground"]) {
        }
        else {
            $json.profiles.defaults.foreground = $ForegroundColor
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["opacity"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "opacity" -Value $opacity
        }
        else {
            $json.profiles.defaults.opacity = $opacity
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["backgroundImageOpacity"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "backgroundImageOpacity" -Value 0
        }
        else {
            $json.profiles.defaults.backgroundImageOpacity = 0
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["backgroundImageAlignment"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "backgroundImageAlignment" -Value "bottomRight"
        }
        else {
            $json.profiles.defaults.backgroundImageAlignment = "bottomRight"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["backgroundImageStretchMode"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "backgroundImageStretchMode" -Value "none"
        }
        else {
            $json.profiles.defaults.backgroundImageStretchMode = "none"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["backgroundImage"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "backgroundImage" -Value $BackgroundImage
        }
        else {
            $json.profiles.defaults.backgroundImage = $BackgroundImage
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["focusFollowMouse"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "focusFollowMouse" -Value "true"
        }
        else {
            $json.profiles.defaults.focusFollowMouse = "true"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["useAcrylic"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "useAcrylic" -Value $true
        }
        else {
            $json.profiles.defaults.useAcrylic = $true
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["acrylicOpacity"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "acrylicOpacity" -Value 0.75
        }
        else {
            $json.profiles.defaults.acrylicOpacity = 0.75
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["cursorColor"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "cursorColor" -Value "#FFFFFF"
        }
        else {
            $json.profiles.defaults.cursorColor = "#FFFFFF"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["scrollbarState"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "scrollbarState" -Value "always"
        }
        else {
            $json.profiles.defaults.scrollbarState = "always"
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["colorScheme"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "colorScheme" -Value $scheme
        }
        else {
            $json.profiles.defaults.colorScheme = $scheme
        }

        if (-NOT $json.profiles.defaults.PSObject.Properties["tabColor"]) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "tabColor" -Value $tabColor
        }
        else {
            $json.profiles.defaults.tabColor = $TabColor
        }

        if (-NOT $json.PSObject.Properties["useAcrylicInTabRow"]) {
            $json | Add-Member -MemberType NoteProperty -Name "useAcrylicInTabRow" -Value $true
        }
        else {
            $json.useAcrylicInTabRow = $true
        }

        if (-NOT $json.PSObject.Properties["compatibility"]) {
            $json | Add-Member -MemberType NoteProperty -Name "compatibility" -Value @{ allowHeadless = $true }
        }
        elseif (-NOT $json.compatibility.PSObject.Properties["allowHeadless"]) {
            $json.compatibility | Add-Member -MemberType NoteProperty -Name "allowHeadless" -Value $true
        }
        else {
            $json.compatibility.allowHeadless = $true
        }

        if (-NOT $json.profiles.defaults.font.PSObject.Properties["face"]) {
            $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value $font
        }
        else {
            $json.profiles.defaults.font.face = $font
        }

        if (-NOT $json.profiles.defaults.font.PSObject.Properties["size"]) {
            $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "size" -Value $FontSize
        }
        else {
            $json.profiles.defaults.font.size = $fontSize
        }

        if (-NOT $json.profiles.defaults.font.PSObject.Properties["weight"]) {
            $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "weight" -Value "medium"
        }
        else {
            $json.profiles.defaults.font.weight = "medium"
        }

        ## Write the updated settings back
        $backupPath = "$settingsfile.bak"
        Copy-Item -Path $settingsfile -Destination $backupPath -Force
        Write-Output "Backup created at: $backupPath"

        $json | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsfile -Force
        Write-Output "Terminal settings updated successfully. Restart Microsoft Terminal to apply changes."
    }
    catch {
        Write-Output "An error occurred while updating terminal settings: $_" 
        Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
        Write-Output "Exception Message: $($_.Exception.Message)" 
        Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
    }
}
## Terminal (unpackaged: Scoop, Chocolately, etc): $env:{LOCALAPPDATA}\Microsoft\Windows Terminal\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    Write-Output "MS Terminal Settings for unpackaged version..."
    Set-MSTerminalSetting $settingsfile
}

## Terminal (preview release): %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    Remove-Item $settingsfile -Force
    ##Write-Output "MS Terminal Settings for preview version..."
    ##Set-MSTerminalSetting $settingsfile
}

## Terminal (stable / general release): $env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
## $statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Leaf) {
    Write-Output "MS Terminal Settings for stable version..."
    Set-MSTerminalSetting $settingsfile
}

## Add or Remote Directory from the Path, add check to see if it is already there first
function Add-DirectoryToPath {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DirectoryToAdd,

        [Parameter()]
        [ValidateSet("User", "Machine")]
        [string]$Scope = "User"
    )

    # Get the current PATH environment variable based on the specified scope
    $CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::$Scope)

    # Split the PATH into an array of directories
    $PathArray = $CurrentPath -split ";"

    # Check if the directory already exists in the PATH
    if (-not ($PathArray -contains $DirectoryToAdd)) {
        # Add the directory to the PATH
        $NewPath = "$CurrentPath;$DirectoryToAdd"

        # Update the PATH environment variable
        [System.Environment]::SetEnvironmentVariable("Path", $NewPath, [System.EnvironmentVariableTarget]::$Scope)

        Write-Output "Directory '$DirectoryToAdd' added to $Scope PATH."
    }
    else {
        Write-Output  "Directory '$DirectoryToAdd' already exists in $Scope PATH."
    }
}
# Example usage
# Add-DirectoryToPath -DirectoryToAdd "C:\MyNewPath" -Scope "Machine"



## Detailed example
## https://raw.githubusercontent.com/microsoft/artifacts-credprovider/refs/heads/master/helpers/installcredprovider.ps1
function Install-NuGetCredentialProviderforAzureArtefacts {
    # Define function parameters
    param (
        ## using a tar file, instead of zip to contained powershell limitations
        [string]$DownloadUrl = "https://github.com/microsoft/artifacts-credprovider/releases/latest/download/Microsoft.NuGet.CredentialProvider.tar.gz",
        ## [string]$DownloadUrl = "https://github.com/microsoft/artifacts-credprovider/releases/latest/download/Microsoft.NuGet.CredentialProvider.zip",

        [string]$DestinationPath = "$HOME/.nuget/plugins"
    )

    # Create destination directory if it doesn't exist
    if (-not (Test-Path -Path $DestinationPath)) {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    ## Define the extraction paths
    $TempTarFile = "$env:TEMP\NuGetCredentialProvider.tar.gz"
    $TempExtractPath = "$env:TEMP\NuGetCredentialProvider"
    ##$TempTarFile = "C:\TEMP\NuGetCredentialProvider.tar.gz"
    ##$TempExtractPath = "C:\TEMP\NuGetCredentialProvider"

    # Ensure C:\workspaces exists
    $workspacePath = "C:\workspaces"
    if (-not (Test-Path -Path $workspacePath)) {
        New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null
        Write-Output "Created directory: $workspacePath"
    }

    try {
        # Download the latest release
        ## Invoke-WebRequest -Uri "https://github.com/microsoft/artifacts-credprovider/releases/latest/download/Microsoft.NuGet.CredentialProvider.zip"
        Write-Output "Downloading $DownloadUrl..." 
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempTarFile

        # Extract the tar.gz file
        Write-Output "Extracting $TempTarFile..." 
        New-Item -ItemType Directory -Path $TempExtractPath -Force | Out-Null
        tar -xzf $TempTarFile -C $TempExtractPath

        # Copy the required directories
        $NetCorePath = "$TempExtractPath\plugins\netcore\"
        $NetFxPath = "$TempExtractPath\plugins\netfx\"
        Write-Output ("NetCorePath = $NetCorePath")
        Write-Output ("NetFxPath   = $NetFxPath")

        if (Test-Path -Path $NetCorePath) {
            Write-Output "Copying $NetCorePath directory to $DestinationPath..." 
            Copy-Item -Path "$NetCorePath" -Destination $DestinationPath -Recurse -Force
        }
        else {
            Write-Output "$NetCorePath directory not found in the extracted files." 
        }

        if (Test-Path -Path $NetFxPath) {
            Write-Output "Copying $NetFxPath directory to $DestinationPath..." 
            Copy-Item -Path "$NetFxPath" -Destination $DestinationPath -Recurse -Force
        }
        else {
            Write-Output "$NetFxPath directory not found in the extracted files." 
        }

        Write-Output "Installation complete." 
    }
    catch {
        Write-Output "An exception occurred: $_" 
        Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
        Write-Output "Exception Message: $($_.Exception.Message)" 
        Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
    }
    finally {
        Write-Output "Finished!" 
        # Clean up temporary files
        if (Test-Path -Path $TempTarFile) {
            ## Remove-Item -Path $TempTarFile -Force
        }
        if (Test-Path -Path $TempExtractPath) {
            ## Remove-Item -Path $TempExtractPath -Recurse -Force
        }
    }
}
## Install Azure Arctefacts Credential Provider
Install-NuGetCredentialProviderforAzureArtefacts

## Generate StrongPassword for developers, used in scripts such as SQL Server installations
if ( [string]::IsNullOrWhiteSpace($env:STRONGPASSWORD)) {
    Write-Output "Generating a random password retained in an environment variable..."
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
$Arguments = "--status"
$Process = Start-Process -FilePath "wsl" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
$Arguments = "--update"
$Process = Start-Process -FilePath "wsl" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru

function Set-DockerDesktopBestPractices {
    <#
    .SYNOPSIS
        Applies best-practice configuration for Docker Desktop.

    .DESCRIPTION
        Configures Docker Desktop settings.json with recommended defaults
        such as resource limits, WSL2 integration, and performance options.

    .NOTES
        Run this with Docker Desktop closed, otherwise your changes may be overwritten.
    #>

    # Path to Docker Desktop settings
    $settingsPath = "$env:APPDATA\Docker\settings.json"
    if (-not (Test-Path $settingsPath)) {
        Write-Error "Docker Desktop settings.json not found at $settingsPath"
        return
    }

    # Backup original
    $backupPath = "$settingsPath.bak"
    Copy-Item $settingsPath $backupPath -Force
    Write-Host "Backup created: $backupPath"

    # Load settings
    $json = Get-Content $settingsPath -Raw | ConvertFrom-Json

    # Apply recommended settings
    $json.version = 3
    $json.analyticsEnabled = $true               # Allow anonymous usage stats (optional)
    $json.autoStart = $true                      # Start Docker Desktop at login
    $json.useWindowsContainers = $false          # Prefer Linux containers (WSL2 backend)
    $json.useWslEngine = $true                   # Enable WSL2
    $json.wslEngineEnabled = $true
    $json.wslDistros = @("Ubuntu-22.04")         # Integrate specific distro(s)

    # Resource limits (tune as needed)
    $json.memoryMiB = 4096                       # 4 GB RAM
    $json.cpus = 2                               # 2 vCPUs
    $json.diskSizeMiB = 65536                    # 64 GB virtual disk
    $json.swapMiB = 1024                         # 1 GB swap

    # Networking
    $json.exposeDockerAPIOnTCP2375 = $false      # Don’t expose insecure API
    $json.hosts = @("npipe:////./pipe/docker_engine") # Local access only

    # File sharing (example)
    $json.sharedDirs = @("C:\Users", "D:\Projects")

    # Save modified config
    $json | ConvertTo-Json -Depth 5 | Set-Content $settingsPath -Encoding utf8
    Write-Host "Docker Desktop best-practice configuration applied."
}
#Set-DockerDesktopBestPractices

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
    ## az ad user show --id $env:UPN
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
        git config --global user.email `"$($env:UPN)`"
    }
    git config --global core.autocrlf true          # per-user solution
    # git config --global http.sslbackend schannel
    # git config --global http.sslVerify false ## totally disable TLS/SLS certification verification (terible idea!)
    git --no-pager config list
    # Enables the Git repo to use the commit-graph file, if the file is present 
    git config --local core.commitGraph true
    # Update the Git repository’s commit-graph file to contain all reachable commits
    git commit-graph write --reachable

    # Generate the dev cert (if not already present)
    #dotnet dev-certs https --clean
    dotnet dev-certs https --export-path "$env:TEMP\devcert.pfx" -p $env:STRONGPASSWORD

    # Import into LocalMachine Root (requires Admin)
    Import-PfxCertificate -FilePath "$env:TEMP\devcert.pfx" `
        -Password (ConvertTo-SecureString -String $env:STRONGPASSWORD -Force -AsPlainText) `
        -CertStoreLocation Cert:\LocalMachine\Root

    ## dotnet dev-certs https --trust --quiet
    dotnet nuget config paths
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

function Set-DockerDesktop {

    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    # Add current user to docker-users group
    Write-Host "Adding user $env:USERNAME to 'docker-users' group..."
    # Check if 'docker-users' group exists before adding user
    if (Get-LocalGroup -Name "docker-users" -ErrorAction SilentlyContinue) {
        Add-LocalGroupMember -Group "docker-users" -Member $env:USERNAME -ErrorAction SilentlyContinue
    }
    else {
        Write-Warning "'docker-users' group does not exist. Please install Docker Desktop first."
    }

    # Optionally enable WSL 2
    $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
    if ($wslFeature.State -ne "Enabled") {
        Write-Host "Enabling WSL 2..."
        wsl --install
    }
    else {
        Write-Host "WSL 2 is already enabled."
    }

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

    # Default Docker Desktop configuration
    $defaultConfig = @{
        "cpuCount"             = 4
        "memoryMiB"            = 8192
        "swapMiB"              = 1024
        "diskSizeMiB"          = 64000
        "useProxy"             = $false
        "httpProxy"            = ""
        "httpsProxy"           = ""
        "noProxy"              = ""
        "showTrayIcon"         = $true
        "autoStart"            = $true
        "hideDesktopIcon"      = $false
        "wslIntegration"       = @{"docker-desktop" = $true }  # Adjust for installed WSL distros
        "kubernetesEnabled"    = $false
        "kubernetesVersion"    = ""
        "telemetryEnabled"     = $true
        "experimentalFeatures" = $false
        "gpuSupport"           = $false
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
        
    if (Test-Path $dockerExe) {
        Write-Host "Starting Docker Desktop..."
        # Start-Process $dockerExe
        Set-Service -Name com.docker.service -StartupType Automatic
        Start-Service com.docker.service
    }
    else {
        Write-Warning "Docker Desktop executable not found at $dockerExe"
    }
}
# Set-DockerDesktop

function New-CodeSigningCertificateAndSignScript {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string]$CertName = "MyCodeSigningCert",
        [Parameter()]
        [System.Security.SecureString]$PfxPassword = (ConvertTo-SecureString -String $env:STRONGPASSWORD -AsPlainText -Force),
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
        Export-Certificate   -Cert $cert -FilePath $cerPath | Out-Null
        Write-Host "PFX exported to $pfxPath"
        Write-Host "CER exported to $cerPath"

        Write-Host "==> Importing certificate into Trusted Root..."
        Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null

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

$Bin = "$env:SystemDrive\BIN"
Add-DirectoryToPath -DirectoryToAdd "${Bin}" -Scope "User"
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User")

Write-Output ("Configuring Oh My Posh, if it isn't already installed...")
## Oh My Posh
If (-not(Test-Path -Path "$env:POSH_THEMES_PATH\jandedobbeleer.omp.json" -PathType Leaf )) {
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
    New-Item -Path $PROFILE -Type File -Force
    "& ([ScriptBlock]::Create((oh-my-posh init pwsh --config `"$env:POSH_THEMES_PATH\cloud-native.omp.json`" --print) -join `"`n`"))" | Out-File $PROFILE
}
else {
    Write-Output("Skipping... Oh-My-Posh is already installed")
}
## exclude from Defender AV - Oh-My-Posh
$exclusion = [Environment]::GetFolderPath(“localapplicationdata”) + "\Programs\oh-my-posh"
Add-MpPreference -ExclusionPath $exclusion
$exclusion = [Environment]::GetFolderPath(“UserProfile”)
Add-MpPreference -ExclusionPath $exclusion
#### wt new-tab "cmd" `; split-pane -p "Windows PowerShell" `; split-pane -H wsl.exe

Write-Output ("Upgrading anything else...") 
## bring everything up to date
## winget
$Arguments = "upgrade --all --accept-package-agreements --accept-source-agreements --disable-interactivity"
$ExitCode = $Process.ExitCode
$Process = Start-Process -FilePath winget -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
Write-Output "Winget upgrade exited with code: $ExitCode"

#dotnet tool install -g dotnet-aspnet-codegenerator
#npm install -g @azure/static-web-apps-cli
#swa --version


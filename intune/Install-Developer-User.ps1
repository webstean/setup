#Requires -RunAsAdministrator

function Set-VSCodeProtocolPolicy {
    <#
    .SYNOPSIS
        Configure Microsoft Edge to auto-launch vscode:// links from vscode.dev (and optionally github.dev)
        without showing the "wants to open this application" prompt.

    .DESCRIPTION
        Writes the AutoLaunchProtocolsFromOrigins policy for Microsoft Edge into the registry.
        By default, applies machine-wide (HKLM) and allows vscode:// from:
            - https://vscode.dev
            - https://github.dev  (can be disabled)

        Can also be removed via -Remove switch.

    .PARAMETER Scope
        Where to write the policy:
            - Machine (default): HKLM:\SOFTWARE\Policies\Microsoft\Edge
            - User:    HKCU:\SOFTWARE\Policies\Microsoft\Edge

    .PARAMETER IncludeGithubDev
        Include https://github.dev as an allowed origin in addition to https://vscode.dev.

    .PARAMETER Remove
        Remove the AutoLaunchProtocolsFromOrigins policy (for the chosen scope).

    .EXAMPLE
        Set-VSCodeProtocolPolicy
        # Allows vscode:// from vscode.dev and github.dev (machine-wide).

    .EXAMPLE
        Set-VSCodeProtocolPolicy -Scope User
        # Same, but only for current user.

    .EXAMPLE
        Set-VSCodeProtocolPolicy -IncludeGithubDev:$false
        # Only vscode.dev is allowed as an origin.

    .EXAMPLE
        Set-VSCodeProtocolPolicy -Remove
        # Removes the policy (machine-wide).
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet("Machine", "User")]
        [string]$Scope = "Machine",

        [bool]$IncludeGithubDev = $true,

        [switch]$Remove
    )

    # Determine registry path based on scope
    $policyRoot = if ($Scope -eq "Machine") {
        "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
    } else {
        "HKCU:\SOFTWARE\Policies\Microsoft\Edge"
    }

    $name = "AutoLaunchProtocolsFromOrigins"

    if ($Remove) {
        if (Test-Path $policyRoot) {
            if ($PSCmdlet.ShouldProcess("$policyRoot\$name", "Remove Edge VSCode protocol policy")) {
                Remove-ItemProperty -Path $policyRoot -Name $name -ErrorAction SilentlyContinue
                Write-Host "Removed $name from $policyRoot" -ForegroundColor Yellow
            }
        } else {
            Write-Host "No policy key at $policyRoot to remove." -ForegroundColor DarkYellow
        }
        return
    }

    # Build JSON value
    $origins = @("https://vscode.dev")
    if ($IncludeGithubDev) {
        $origins += "https://github.dev"
    }

    $configObject = @(
        [PSCustomObject]@{
            allowed_origins = $origins
            protocol        = "vscode"
        }
    )

    $json = $configObject | ConvertTo-Json -Compress

    # Ensure key exists
    if (-not (Test-Path $policyRoot)) {
        New-Item -Path $policyRoot -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess("$policyRoot\$name", "Set Edge VSCode protocol policy")) {
        New-ItemProperty -Path $policyRoot `
                         -Name $name `
                         -PropertyType String `
                         -Value $json `
                         -Force | Out-Null

        Write-Host "Set $name on $policyRoot" -ForegroundColor Green
        Write-Host "JSON: $json" -ForegroundColor DarkGray
        Write-Host "Restart Edge and check edge://policy to confirm the policy is applied." -ForegroundColor Cyan
    }
}
Set-VSCodeProtocolPolicy -IncludeGithubDev:$true

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
        [string]$ForegroundColor = "#FFFFFF", ## Default white text
        [int]$opacity = 97, ## Default opacity
        [string]$BackgroundImage = "$env:ALLUSERSPROFILE\logo.png", # "ms-appdata:///Roaming/terminal_cat.jpg", ## background image
        [string]$TabColor = "#012456",
        [string]$face = "Cascadia Code NF", ## Default font
        [int]$FontSize = 12, ## Default font size
        [string]$scheme = "Campbell"
    )
    
    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        return ## This is Windows PowerShell - exit because ConvertTo-Json does not support enough depth
    }
    
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
    Set-JsonValue -JsonObject $json -Path "foreground" -Value $ForegroundColor
    Set-JsonValue -JsonObject $json -Path "opacity" -Value $opacity
    Set-JsonValue -JsonObject $json -Path "focusFollowMouse" -Value $true
    Set-JsonValue -JsonObject $json -Path "multiLinePasteWarning" -Value $false
    Set-JsonValue -JsonObject $json -Path "BellSound" -Value ""
    Set-JsonValue -JsonObject $json -Path "initialRows" -Value 35
    Set-JsonValue -JsonObject $json -Path "focusFollowMouse" -Value $true
    Set-JsonValue -JsonObject $json -Path "update.showReleaseNotes" -Value $false
    Set-JsonValue -JsonObject $json -Path "git.autofetch" -Value $true
    Set-JsonValue -JsonObject $json -Path "editor.formatOnSave" -Value $true
    Set-JsonValue -JsonObject $json -Path "files.autoSave" -Value $true
    Set-JsonValue -JsonObject $json -Path "editor.defaultFormatter" -Value "GitHub.copilot-chat"
           
    #Set-JsonValue -JsonObject $json -Path "startupActions" -Value "newTab -p 'PowerShell'; newTab -p 'Headless Helper'"
    #Set-JsonValue -JsonObject $json -Path "wt -p "Command Prompt" `; split-pane -p "Windows PowerShell" `; split-pane -H wsl.exe

    ## Profiles
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.historySize" -Value 50000
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.snapOnInput" -Value $true
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.bellStyle" -Value "none"

    $Workspace = "$env:SystemDrive\WORKSPACES"
    if ( Test-Path "${Workspace}" ) {
        Set-JsonValue -JsonObject $json -Path "profiles.defaults.startingDirectory" -Value "${Workspace}"
    }
    
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
    Set-JsonValue -JsonObject $json -Path "editor.fontFamily" -Value "FiraCode"

    Set-JsonValue -JsonObject $json -Path "profiles.defaults.backgroundImageAlignment" -Value "bottomRight"
    Set-JsonValue -JsonObject $json -Path "profiles.defaults.backgroundImageStretchMode" -Value "none"
    if ( Test-Path "$BackgroundImage" ) {
        Set-JsonValue -JsonObject $json -Path "profiles.defaults.backgroundImage" -Value $BackgroundImage
    } else {
        if ( Test-Path "$PSScriptRoot/logo.png" ) {
            Copy-Item "$PSScriptRoot/logo.png" "$env:ALLUSERSPROFILE\logo.png" -Force
            Set-JsonValue -JsonObject $json -Path "profiles.defaults.backgroundImage" -Value "$env:ALLUSERSPROFILE\logo.png"
        } else {
            Write-Host "Warning: $BackgroundImage NOT found!"
        }
    }

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

function Set-EnvironmentVariable {
    <#
    .SYNOPSIS
        Sets environment variables at User or Machine scope.

    .PARAMETER Name
        The name of the environment variable.

    .PARAMETER Value
        The value to set.

    .PARAMETER Scope
        The scope for the variable: 'User' or 'Machine'. Defaults to User.

    .PARAMETER Refresh
        If set, updates the current PowerShell session’s environment immediately.

    .EXAMPLE
        Set-EnvironmentVariable -Name "MY_VAR" -Value "hello" -Scope User -Refresh

    .EXAMPLE
        Set-EnvironmentVariable -Name "APP_PATH" -Value "C:\Tools" -Scope Machine
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value,

        [ValidateSet('User','Machine')]
        [string]$Scope = 'User',

        [switch]$Refresh
    )

    try {
        [System.Environment]::SetEnvironmentVariable($Name, $Value, $Scope)
        Write-Output "✅ Environment variable '$Name' set at $Scope scope to '$Value'."

        if ($Refresh) {
            env:${Name} = $Value
            Write-Output "🔄 Session environment updated."
        }
    }
    catch {
        Write-Error "❌ Failed to set environment variable '$Name': $($_.Exception.Message)"
    }
}

## Get UPN (User Principal)
$getupn = @(whoami /upn)
if ( -not ([string]::IsNullOrWhiteSpace($getupn))) {
    [Environment]::SetEnvironmentVariable('UPN', "$getupn", 'User')
    $env:UPN = [System.Environment]::GetEnvironmentVariable("UPN", "User")
}

## Installing Ubuntu
$Distro = "Ubuntu"

function Enable-WSL {

    ## Share environment variables between Windows and WSL
    ## https://devblogs.microsoft.com/commandline/share-environment-vars-between-wsl-and-windows/
    [Environment]::SetEnvironmentVariable('WSLENV', 'OneDriveCommercial/p:STRONGPASSWORD:USERDNSDOMAIN:USERDOMAIN:USERNAME:UPN', 'User')
    $env:WSLENV = [System.Environment]::GetEnvironmentVariable("WSLENV", "User")

    Write-Output ("Ensuring WSL is install and upto date...") 
    ## ensure WSL is upto date, can only be done per user (not system)
    Start-Process -FilePath 'wsl' -ArgumentList '--install --no-launch' -NoNewWindow -Wait -PassThru | Out-Null
    Start-Process -FilePath 'wsl' -ArgumentList '--status' -NoNewWindow -Wait -PassThru | Out-Null
    Start-Process -FilePath 'wsl' -ArgumentList '--update' -NoNewWindow -Wait -PassThru | Out-Null
    ## PreRelease version
    Start-Process -FilePath "wsl" -ArgumentList "--update --pre-release" -NoNewWindow -Wait -PassThru | Out-Null
    Start-Process -FilePath "wsl" -ArgumentList "--set-default-version 2" -NoNewWindow -Wait -PassThru | Out-Null

    ## clean up
    ## wsl --terminate $Distro
    ## wsl --unregister $Distro

    ## Install quietly
    Start-Process -FilePath 'wsl' -ArgumentList "--install -d $Distro --no-launch" -NoNewWindow -Wait -PassThru | Out-Null
    ## Preseed user
    wsl -d $Distro --user root bash -c @"
useradd -m -s /bin/bash -G sudo $env:UserName
"@
    Start-Process -FilePath 'wsl' -ArgumentList "--manage $Distro --set-default-user $env:UserName" -NoNewWindow -Wait -PassThru | Out-Null
    Start-Process -FilePath 'wsl' -ArgumentList "--set-default $Distro" -NoNewWindow -Wait -PassThru | Out-Null

    wsl -d $Distro --user root bash -c @"
if ! (sudo grep NOPASSWD:ALL /etc/sudoers  > /dev/null 2>&1 ) ; then 
    # Everyone
    bash -c "echo '#Everyone - WSL' | sudo EDITOR='tee -a' visudo"
    bash -c "echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
    # Entra ID
    bash -c "echo '#Azure AD - WSL' | sudo EDITOR='tee -a' visudo"
    bash -c "echo '%sudo aad_admins=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
fi
"@

    $wslConfigPath = [System.IO.Path]::Combine($env:USERPROFILE, ".wslconfig")
    if (Test-Path $wslConfigPath) {
        Remove-Item -Force $wslConfigPath
    }
    New-Item -Path $wslConfigPath -ItemType File -Force | Out-Null
    # Define config content as an array (each item = one line)
    $content = @('
[wsl2]
networkingMode=Mirrored

[experimental]
hostAddressLoopback=true

')
    ## Write all lines at once
    Set-Content -Path $wslConfigPath -Value $content ## -Encoding UTF8
    Get-Content -Path $wslConfigPath

    ## Turn of Windows PATH inside Linux
    wsl -d $Distro --user root bash -c @"
sh -c 'echo [interop]                  >>  /etc/wsl.conf'
sh -c 'echo appendWindowsPath = false  >>  /etc/wsl.conf'

sh -c 'echo [boot]                     >>  /etc/wsl.conf'
sh -c 'systemd = true                    >>  /etc/wsl.conf'

sh -c 'echo [gpu]                      >>  /etc/wsl.conf'
sh -c 'enabled = true                    >>  /etc/wsl.conf'
"@

    ## Allow Inbound connections
    Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow
    
    ## Terminate the existing disitribution, so it restarts with new settings
    Start-Process -FilePath 'wsl' -ArgumentList "--terminate $Distro" -NoNewWindow -Wait -PassThru | Out-Null
}
Enable-WSL

function Set-WSLConfig-Ubuntu {

    ## Initial
    #$wslinitalsetup = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/wsl/wslfirstsetup.sh').Content -replace "`r", ''
    #$wslinitalsetup | wsl --user root --distribution ${Distro} --

    ## BIG Setup
    $wslsetup1   = (Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup1.sh).Content -replace "`r", ''
    $wslsetup2   = (Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup2.sh).Content -replace "`r", ''
    $wslsetup1 | wsl --user root --distribution ${Distro} --
    wsl --terminate ${Distro}
    $wslsetup2 | wsl --user root --distribution ${Distro} --
}
#Set-WSLConfig-Ubuntu

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
        [string]$CertName = "MyCodeSigningCert",
        [Parameter()]
        [System.Security.SecureString]$PfxPassword = (ConvertTo-SecureString -String (Get-Item Env:STRONGPASSWORD).Value -AsPlainText -Force),
        [string]$OutputPath = "$env:OneDriveCommercial"
    )

    try { 

        $subject = "CN=$CertName"

        if ( Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$subject*" } ) { return } ## already exists
        
        ## Delete
        # $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$subject*" }
        # Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"
        
        # Ensure output path exists
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $pfxPath = Join-Path $OutputPath "$CertName.pfx"
        $cerPath = Join-Path $OutputPath "$CertName.cer"
        $securePass = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText

        Write-Host "==> Creating self-signed code signing certificate..."
        $cert = New-SelfSignedCertificate `
            -Subject "$subject" `
            -KeyExportPolicy Exportable `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -NotAfter (Get-Date).AddYears(2) `
            -Type CodeSigningCert `
            -KeySpec Signature `
            -KeyLength 2048 `
            -HashAlgorithm SHA256

        Write-Host "Created code signing certificate with Thumbprint:" $cert.Thumbprint

        Write-Host "==> Exporting certificate..."
        Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePass | Out-Null
        Export-Certificate    -Cert $cert -FilePath $cerPath | Out-Null
        Write-Host "PFX exported to $pfxPath"
        Write-Host "CER exported to $cerPath"

        ## Add to Trusted Root store
        Write-Host "==> Importing certificate into Trusted Root..."
        ## Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null ## This User
        Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\Localmachine\Root | Out-Null ## All Users

        ## How to sign something
        #$cert = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert)[0]
        #Set-AuthenticodeSignature -Certificate $cert -FilePath .\aw.ps1  ## -TimestampServer "https://timestamp.fabrikam.com/scripts/timstamper.dll"
        #Set-AuthenticodeSignature -Certificate $cert -FilePath .\aw.ps1 -HashAlgorithm "SHA256" -TimestampServer 'http://timestamp.verisign.com/scripts/timstamp.dll'

        #(Get-AuthenticodeSignature .\aw.ps1).StatusMessage

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
Add-DirectoryToPath -Directory "${BIN}" -Scope "User"

# List of commands you want to exclude from AV
$commands = @(
    "$BIN",
    'starship',
    'oh-my-posh',
    "$PROFILE"
)

foreach ($name in $commands) {
    $cmd = Get-Command -ErrorAction SilentlyContinue $name

    if ($null -ne $cmd -and $null -ne $cmd.Source) {
        $path = Split-Path -Path $cmd.Source
        Write-Host "Excluding $cmd in $path..."
        Add-MpPreference -ExclusionPath $path
    }
}

Write-Output ("Configuring Oh My Posh, if it isn't already installed...")
## Oh My Posh
If (Get-Command -ErrorAction SilentlyContinue aaoh-my-posh ) {
    $config = (Get-Command -ErrorAction SilentlyContinue oh-my-posh).Source
    ### Winget install will set the POSH_THEMES_PATH variable
    ### FYI: Meslo is the default font for Windows Terminal
    ## $env:POSH_THEMES_PATH = [System.Environment]::GetEnvironmentVariable("POSH_THEMES_PATH","User")
    #oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\cloud-native-azure.omp.json" | Invoke-Expression
    oh-my-posh init pwsh --config "C:\Program Files\WindowsApps\ohmyposh.cli_27.5.0.0_x64__96v55e8n804z4\themes\cloud-native-azure.omp.json" | Invoke-Expression
    ### Init in profile
    ## Option #1
    #oh-my-posh init pwsh | Invoke-Expression
    ## Option #2
    #& ([ScriptBlock]::Create((oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\\cloud-native.omp.json" --print) -join "`n"))
    ## Create Profile
} 

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

function Set-PodmanConfig {
    <#
    .SYNOPSIS
        Configure Podman Desktop & engine defaults, manage auto-launch, hide Docker extensions.

    .DESCRIPTION
        Updates:
          - ~/.config/containers/containers.conf
          - %APPDATA%\Podman Desktop\config.json
        Sets:
          • minimize on startup (default: true)
          • disables experimental feedback & telemetry (default)
          • optionally hides Docker Extensions in the dashboard (default: hide)
          • optionally manages Windows startup auto-launch (default: enabled)
          • optional silent mode for unattended scripts (default: off)

    .PARAMETER ShortNameMode
        Image short name resolution mode. Default: 'permissive'.

    .PARAMETER EventsLogger
        Events backend. Default: 'file'.

    .PARAMETER MinimiseOnLogin
        Minimize Podman Desktop on login/startup. Default: $true.

    .PARAMETER ExperimentalFeedback
        Enable experimental feedback. Default: $false.

    .PARAMETER Telemetry
        Enable telemetry. Default: $false.

    .PARAMETER HideDockerExtensions
        Hide/disable Docker Extensions in the dashboard. Default: $true.

    .PARAMETER AutoLaunch
        Add/remove Podman Desktop from Windows startup (HKCU\...\Run). Default: $true.

    .PARAMETER Silent
        Suppress all console output (for login scripts). Default: $false.

    .EXAMPLE
        Set-PodmanConfig
    .EXAMPLE
        Set-PodmanConfig -AutoLaunch:$false -Silent

         podman machine stop
          podman machine rm --force
          podman machine init --timezone "Australia/Melbourne"
          podman machine set --rootful
          podman machine start
          #podman machine ssh podman-machine-default "sudo systemctl enable podman.socket --now"
          wslconfig /setdefault Ubuntu
          podman machine ls
\            Write-Host "Conducting container test (quay.io/podman/hello)"
            if ($PSCmdlet.ShouldProcess("quay.io/podman/hello","Pull & Run")) {
                podman pull quay.io/podman/hello | Out-Null
                podman run --rm quay.io/podman/hello
                Write-Host "Smoke test completed." -ForegroundColor Green
                return $true
            }
            return $false

    ## other good images
    ## Azure CLI
    sudo docker pull mcr.microsoft.com/azure-cli:latest
    ## Azure API Management Gateway
    sudo docker pull mcr.microsoft.com/azure-api-management/gateway:latest
    podman run -it mcr.microsoft.com/azure-api-management/gateway:latest /bin/bash
    podman run -it --entrypoint /bin/bash mcr.microsoft.com/azure-api-management/gateway:latest

    ## Powershell
    sudo docker docker pull mcr.microsoft.com/azure-powershell:latest
    podman run -it mcr.microsoft.com/azure-powershell:latest pwsh

    ## try Spark Workbook
    docker run -it -p 8888:8888 -e ACCEPT_EULA=yes mcr.microsoft.com/mmlspark/release
    


        
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('enforcing','permissive','disabled')]
        [string]$ShortNameMode = 'permissive',
        [ValidateSet('file','journald','none')]
        [string]$EventsLogger = 'file',
        [bool]$MinimiseOnLogin = $true,
        [bool]$ExperimentalFeedback = $false,
        [bool]$Telemetry = $false,
        [bool]$HideDockerExtensions = $true,
        [bool]$AutoLaunch = $true,
        [bool]$Silent = $false
    )

    # Helper: Conditional write
    function Out-Info([string]$msg, [ConsoleColor]$color = [ConsoleColor]::Gray) {
        if (-not $Silent) { Write-Host $msg -ForegroundColor $color }
    }

    # --- Paths ---
    $confRoot       = Join-Path $HOME ".config\containers"
    $containersFile = Join-Path $confRoot "containers.conf"
    $desktopConfig  = Join-Path $Env:APPDATA "Podman Desktop\config.json"

    # Likely install locations (for autostart)
    $exeCandidates = @(
        (Join-Path $Env:LOCALAPPDATA "Programs\Podman Desktop\Podman Desktop.exe"),
        (Join-Path $Env:ProgramFiles  "RedHat\Podman Desktop\Podman Desktop.exe")
    )
    $podmanDesktopExe = $exeCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    # --- Ensure dirs ---
    foreach ($p in @($confRoot, (Split-Path $desktopConfig -Parent))) {
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }

    # --- containers.conf ---
    $containersLines = @(
        "# Generated by Set-PodmanConfig on $(Get-Date -Format s)"
        "[engine]"
        "events_logger = ""$EventsLogger"""
        "short_name_mode = ""$ShortNameMode"""
    )
    Set-Content -Path $containersFile -Value ($containersLines -join "`n") -Encoding UTF8

    # --- Podman Desktop config.json ---
    if (Test-Path $desktopConfig) {
        try {
            $json = Get-Content $desktopConfig -Raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            if (-not $Silent) { Write-Warning "Existing config.json invalid; recreating." }
            $json = @{}
        }
    } else {
        $json = @{}
    }

    $json.minimizeOnStartup               = [bool]$MinimiseOnLogin
    $json.experimentalFeedbackEnabled     = [bool]$ExperimentalFeedback
    $json.telemetryEnabled                = [bool]$Telemetry
    $json.dockerExtensionsEnabled         = -not [bool]$HideDockerExtensions
    $json.showDockerExtensionsInDashboard = -not [bool]$HideDockerExtensions

    $json | ConvertTo-Json -Depth 6 | Set-Content -Path $desktopConfig -Encoding UTF8

    # --- Auto-launch (HKCU Run) ---
    $runKeyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $runValueName = 'Podman Desktop'
    if ($AutoLaunch) {
        if (-not $podmanDesktopExe) { $podmanDesktopExe = $exeCandidates[0] }
        $quoted = '"' + $podmanDesktopExe + '"'
        New-Item -Path $runKeyPath -Force | Out-Null
        New-ItemProperty -Path $runKeyPath -Name $runValueName -Value $quoted -PropertyType String -Force | Out-Null
    } else {
        if (Get-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue) {
            Remove-ItemProperty -Path $runKeyPath -Name $runValueName -ErrorAction SilentlyContinue
        }
    }

    # --- Summary ---
    Out-Info "`n✅ Podman configuration updated:" Green
    Out-Info " - $containersFile"
    Out-Info " - $desktopConfig (minimizeOnStartup=$MinimiseOnLogin, feedback=$ExperimentalFeedback, telemetry=$Telemetry, hideDockerExtensions=$HideDockerExtensions)"
    Out-Info (" - Windows Startup: " + ($(if ($AutoLaunch) { "Enabled" } else { "Disabled" })))
}

function Enable-PodmanFirewallRules {
    <#
    .SYNOPSIS
        Enables or creates Windows Firewall rules for Podman Desktop.

    .DESCRIPTION
        This function finds and enables existing Podman, QEMU, and GVProxy firewall rules.
        If none are found, it creates default inbound/outbound rules for the Podman Desktop executables.
        Must be run with Administrator privileges.

    .EXAMPLE
        Enable-PodmanFirewallRules

    .NOTES
        Author: ChatGPT
        Requires: Windows 10/11 with Podman Desktop installed
    #>

    # Verify admin privileges
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "Please run PowerShell as Administrator."
        return
    }

    Write-Host "Enabling Podman Desktop firewall rules..." -ForegroundColor Cyan

    # Locate Podman executables
    $podmanPaths = @(
        "$Env:ProgramFiles\RedHat\Podman\podman.exe",
        "$Env:ProgramFiles\RedHat\Podman Desktop\resources\app\bin\podman.exe",
        "$Env:LOCALAPPDATA\Programs\Podman Desktop\resources\app\bin\podman.exe",
        "$Env:ProgramFiles\RedHat\Podman Desktop\resources\app\bin\qemu-system-x86_64.exe",
        "$Env:ProgramFiles\RedHat\Podman Desktop\resources\app\bin\gvproxy.exe"
    ) | Where-Object { Test-Path $_ }

    # Find existing firewall rules
    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match 'Podman' -or $_.DisplayName -match 'QEMU' -or $_.DisplayName -match 'GVProxy'
    }

    if ($rules) {
        Write-Host "Found existing Podman-related rules. Ensuring they are enabled..." -ForegroundColor Yellow
        $rules | ForEach-Object {
            if ($_.Enabled -eq 'False') {
                Write-Host "Enabling rule: $($_.DisplayName)" -ForegroundColor Green
                Set-NetFirewallRule -Name $_.Name -Enabled True
            }
        }
    } else {
        Write-Host "No existing Podman firewall rules found. Creating new ones..." -ForegroundColor Yellow
        foreach ($exe in $podmanPaths) {
            $name = Split-Path $exe -Leaf
            Write-Host "Creating firewall rules for $name" -ForegroundColor Green
            New-NetFirewallRule -DisplayName "Podman - $name (Inbound)" -Direction Inbound -Program $exe -Action Allow -Profile Any -Protocol TCP | Out-Null
            New-NetFirewallRule -DisplayName "Podman - $name (Outbound)" -Direction Outbound -Program $exe -Action Allow -Profile Any -Protocol TCP | Out-Null
        }
    }

    Write-Host "✅ Podman Desktop firewall rules are now enabled and active." -ForegroundColor Green
}
Enable-PodmanFirewallRules

function Set-StarshipConfig {
    <#
    .SYNOPSIS
        Adds Starship custom modules that change colour based on elevation (Admin vs User).
    #>
    [CmdletBinding()]
    param(
        [switch]$AddInitToProfile,
        [string]$AdminStyle = 'bold red',
        [string]$UserStyle  = 'bold green',
        [string]$AdminIcon  = '󰷛',
        [string]$UserIcon   = '󰈸'
    )

    $result = [pscustomobject]@{
        ConfigPath        = $null
        ProfileUpdated    = $false
        AdminModuleUpsert = $false
        UserModuleUpsert  = $false
        FormatUpdated     = $false
        Notes             = @()
    }

    # Paths
    $configDir    = Join-Path $env:USERPROFILE '.config'
    $starshipToml = Join-Path $configDir 'starship.toml'
    $result.ConfigPath = $env:STARSHIP_CONFIG
    
    # Download a config
    $url = 'https://raw.githubusercontent.com/TaouMou/starship-presets/refs/heads/main/starship_pills.toml'
    $url = 'https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/starship_pill.toml'
    $response = Invoke-WebRequest -Uri $url -ContentType "text/plain" -UseBasicParsing
    $response.Content | Out-File $HOME/.starship_pill.toml
    Copy-Item $HOME/.starship_pill.toml $result.ConfigPath
    
    # Ensure dirs/files
    if (-not (Test-Path $configDir))   { New-Item -ItemType Directory -Path $configDir   -Force | Out-Null }
    if (-not (Test-Path $starshipToml)){ New-Item -ItemType File      -Path $starshipToml -Force | Out-Null }

    # Use single-quoted here-strings so $ stays literal inside TOML
    $adminBlock = @'
[custom.admin]
command = 'powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Output \"__ADMIN_ICON__\" }"'
when = 'powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"'
shell = ["powershell"]
format = "[$output]($style) "
style = "__ADMIN_STYLE__"
'@

    $userBlock = @'
[custom.user]
command = 'powershell -NoProfile -Command "if (-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) { Write-Output \"__USER_ICON__\" }"'
when = 'powershell -NoProfile -Command "-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"'
shell = ["powershell"]
format = "[$output]($style) "
style = "__USER_STYLE__"
'@

    # Inject chosen styles/icons (NO space before .Replace)
    $adminBlock = $adminBlock.Replace('__ADMIN_STYLE__', $AdminStyle).Replace('__ADMIN_ICON__', $AdminIcon)
    $userBlock  = $userBlock.Replace('__USER_STYLE__',  $UserStyle).Replace('__USER_ICON__',  $UserIcon)

    # Default format (single-quoted so $custom.* is literal)
    $defaultFormat = @'
format = """
$custom.admin\
$custom.user\
$directory\
$git_branch\
$git_status\
$character
"""
'@

    # Helper: upsert a TOML section
    function _Set-TomlSection {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$SectionHeaderRegex,
            [Parameter(Mandatory)][string]$BlockText
        )
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ($content -match $SectionHeaderRegex) {
            $pattern = "(?ms)$SectionHeaderRegex.*?(?=^\[|\Z)"
            $new     = [regex]::Replace($content, $pattern, $BlockText + "`r`n")
            if ($new -ne $content) {
                Set-Content -Path $Path -Value $new -Encoding UTF8
                return $true
            }
            return $false
        } else {
            Add-Content -Path $Path -Value ("`r`n" + $BlockText + "`r`n")
            return $true
        }
    }

    # Upsert modules
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.admin\]\s*$' -BlockText $adminBlock) { $result.AdminModuleUpsert = $true }
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.user\]\s*$'  -BlockText $userBlock)  { $result.UserModuleUpsert  = $true }

    # Ensure our modules appear in the format
    $content = Get-Content -Path $starshipToml -Raw
    if ($content -notmatch '^\s*format\s*=' ) {
        Add-Content -Path $starshipToml -Value ("`r`n" + $defaultFormat + "`r`n")
        $result.FormatUpdated = $true
    } else {
        # Prepend our two module lines if missing (escape $ so TOML keeps it)
        $pattern = '(?ms)^\s*format\s*=\s*"""(.*?)"""'
        if ($content -match $pattern) {
            $inner      = $Matches[1]
            $needsAdmin = ($inner -notmatch '\$custom\.admin')
            $needsUser  = ($inner -notmatch '\$custom\.user')
            if ($needsAdmin -or $needsUser) {
                $prepend = @()
                if ($needsAdmin) { $prepend += '`$custom.admin\' }
                if ($needsUser)  { $prepend += '`$custom.user\' }
                $newInner   = ($prepend -join [Environment]::NewLine) + [Environment]::NewLine + $inner
                $newContent = [regex]::Replace($content, $pattern, 'format = """' + $newInner + '"""')
                if ($newContent -ne $content) {
                    Set-Content -Path $starshipToml -Value $newContent -Encoding UTF8
                    $result.FormatUpdated = $true
                }
            }
        }
    }

    $result
}
Set-StarshipConfig
#Invoke-Expression (&starship init powershell)



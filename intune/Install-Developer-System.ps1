#Requires -RunAsAdministrator

function Set-RdpQueryDirPrefetch {
    <#
    .SYNOPSIS
        Sets the RDP registry value fAllowQueryDirPrefetch to 1.

    .DESCRIPTION
        This function ensures the key:
            HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp
        exists, and then sets the REG_DWORD value:
            fAllowQueryDirPrefetch = 1
        Returns $true if the operation succeeds, otherwise $false.

    .NOTES
        Requires Administrator privileges.
    #>

    [CmdletBinding()]
    param()

    $regPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
    $regName  = 'fAllowQueryDirPrefetch'
    $regValue = 1

    try {
        # Ensure key exists
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        # Set or update value
        New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType DWord -Force | Out-Null

        # Verify the result
        $currentValue = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction Stop).$regName
        if ($currentValue -eq $regValue) {
            Write-Verbose "Successfully set $regName to $regValue at $regPath"
            return $true
        }
        else {
            Write-Error "Failed to verify registry value."
            return $false
        }
    }
    catch {
        Write-Error "Error setting registry value: $($_.Exception.Message)"
        return $false
    }
}

function Test-DeveloperMode {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $regName = 'AllowDevelopmentWithoutDevLicense'

    if (-not (Test-Path $regPath)) {
        return $false
    }

    $val = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
    return ($val -eq 1)
}

function Set-NetworkProfilesToPrivate {
    # Make all the network connection profiles private
    $networks = Get-NetConnectionProfile
    foreach ($net in $networks) {
        Write-Host "Changing '$($net.Name)' from $($net.NetworkCategory) to Private..."
        Set-NetConnectionProfile -InterfaceIndex $net.InterfaceIndex -NetworkCategory Private
    }
    ## Verify
    Get-NetConnectionProfile
}
Set-NetworkProfilesToPrivate

function Install-WinRM {
    ## Network profiles MUST be private for WinRM to work
    Set-NetworkProfilesToPrivate

    ## Open firewall rules for WinRM (HTTP:5985, HTTPS:5986)
    #Get-NetFirewallRule | Select-Object -ExpandProperty DisplayName
    Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any -Action Allow
    Get-NetFirewallRule -Name "WINRM-HTTP-In-TCP"
    #New-NetFirewallRule -DisplayName "Allow WinRM HTTP"  -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -Profile Private | Out-Null
    #New-NetFirewallRule -DisplayName "Allow WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -Profile Private | Out-Null

    ## For the transcript: remoting (WSMAN) configuration
    winrm quickconfig -Force
    Enable-PSRemoting -Force
    winrm enumerate winrm/config/listener
    ## using a certificate for WinRm?
    #Winrm get http://schemas.microsoft.com/wbem/wsman/1/config
    #Get-ChildItem -path WSMAN:\localhost\MaxEnvelopeSizeKb
    ## default is 500, 8192 would be better for performance
    Set-Item -path WSMAN:\localhost\MaxEnvelopeSizeKb 8192 -Force
    Set-Item  WSMan:\localhost\Client\TrustedHosts -Value * -Force  ## $env:COMPUTERNAME -Force
    Set-Item -Path WSMan:\localhost\Client\Auth\Kerberos -Value $false
    Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $false
    Restart-Service WinRM
    winrm get winrm/config/client
    winrm get winrm/config/service
    if (Test-WSMAN localhost -ErrorAction Continue ) {
        $cred = Get-Credential
        Invoke-Command -ComputerName localhost -Authentication Negotiate -Credential $cred -ScriptBlock { hostname }
        Invoke-Command -ComputerName $env:COMPUTERNAME -Authentication Negotiate -Credential $cred -ScriptBlock { hostname }
        return $true
    } else {
        return $false
    }
}
#Install-WinRM

## The tools functionality is only installed via DOTNET SDKs, not Runtimes
function Install-OrUpdate-DotNetTools {
    Write-Output ("Installing/Updating DotNet Tools...") 
    $dotnetTools = @(
        "Microsoft.DataApiBuilder",               ## dab
        "IntuneCLI",                              ## intuneCLI (3rd party)
        "microsoft.powerapps.cli.tool",           ## powerapp tools
        "dotnet-reportgenerator-globaltool",      ## report generator
        "paket",                                  ## Paket dependency manager
        "upgrade-assistant"                       ## upgrade assistant
    )

    foreach ($tool in $dotnetTools) {
        $installedTool = dotnet tool list --global | Where-Object { $_ -match $tool }
        if (-not $installedTool) {
            Write-Output "Installing $tool..." 
            $Arguments = "tool install --ignore-failed-sources --global $tool"
            Start-Process -FilePath "dotnet.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
        }
        else {
            Write-Output "$tool is already installed." 
        }
    }

    $Arguments = "tool list --global"
    Start-Process -FilePath "dotnet.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue

    $Arguments = "tool update --global --all"
    Start-Process -FilePath "dotnet.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue

    $Arguments = "tool list --global"
    Start-Process -FilePath "dotnet.exe" -ArgumentList $Arguments -NoNewWindow -Wait -PassThru -ErrorAction SilentlyContinue
}
Install-OrUpdate-DotNetTools

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

function CleanupDirectoryPath {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet("User", "Machine")]
        [string]$Scope
    )

    # Get the current PATH environment variable based on the specified scope
    $CurrentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::$Scope)

    if (-not $CurrentPath) {
        Write-Output "PATH is empty for the $Scope scope." 
        return
    }

    # Split the PATH into an array of directories
    $PathArray = $CurrentPath -split ";"

    # Remove duplicates and trim whitespace
    $CleanPathArray = $PathArray | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" } | Sort-Object -Unique

    # Recombine the cleaned array into a single string
    $CleanPath = ($CleanPathArray -join ";")

    # Update the PATH environment variable
    [System.Environment]::SetEnvironmentVariable("Path", $CleanPath, [System.EnvironmentVariableTarget]::$Scope)

    Write-Output "Cleaned up PATH for the $Scope scope." 
    Write-Output "Original entries: $($PathArray.Count)"
    Write-Output "Cleaned entries: $($CleanPathArray.Count)"
}
# Example usage
# Clean up the User PATH
#Cleanup-DirectoryPath -Scope "User"

# Clean up the Machine PATH
#Cleanup-DirectoryPath -Scope "Machine"
CleanupDirectoryPath -Scope "User"
CleanupDirectoryPath -Scope "Machine"

function Set-DriveVolumeLabel {
    param (
        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,
        [Parameter(Mandatory = $true)]
        [string]$DesiredVolumeName
    )

    try {
        $SystemVolumeLabel = Get-Volume -DriveLetter $DriveLetter -ErrorAction Stop
        if ($SystemVolumeLabel.FileSystemLabel -ne $DesiredVolumeName) {
            Write-Output ("Labeling Drive $DriveLetter...") 
            Set-Volume -DriveLetter $DriveLetter -NewFileSystemLabel $DesiredVolumeName -ErrorAction SilentlyContinue
        }
        else {
            Write-Output "Drive $DriveLetter already labeled as '$DesiredVolumeName'." 
        }
    }
    catch {
        Write-Output "Error setting volume label for Drive ${DriveLetter}: $($_.Exception.Message)" 
    }
}
Set-DriveVolumeLabel -DriveLetter 'C' -DesiredVolumeName 'Developer'

function New-TempDirectories {
    Write-Output "Creating TEMP/TMP directories..." -ForegroundColor Green

    $TempDirs = @("$env:SystemDrive\Temp", "$env:SystemDrive\Tmp")

    foreach ($Temp in $TempDirs) {
        if (-not (Test-Path -Path ${Temp} -PathType Container)) {
            try {
                New-Item -Path ${Temp} -ItemType Directory -Force | Out-Null
                Write-Output "Created directory: ${Temp}" 
            }
            catch {
                Write-Output "Failed to create ${Temp}: $($_.Exception.Message)" 
            }
        }
        else {
            Write-Output "Directory already exists: ${Temp}" 
        }
    }
}
# Call the function
New-TempDirectories

function Install-LatestWindowsSDK {
    <#
    .SYNOPSIS
        Installs the latest Windows SDK using winget if Developer Mode is enabled.

    .DESCRIPTION
        - Verifies Developer Mode is enabled via registry.
        - Queries winget to detect the latest Windows SDK package ID.
        - Installs it silently.
        - Returns $true on success, $false on failure.

    .NOTES
        - Requires administrator privileges.
        - Works on Windows 10/11.
        - Developer Mode check is based on registry:
          HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock
    #>

    [CmdletBinding()]
    param()

    $packageIdPrefix = 'Microsoft.WindowsSDK.'

    # --- Helper: Check Developer Mode ---

    Write-Verbose "Checking if Developer Mode is enabled..."
    if (-not (Test-DeveloperMode)) {
        Write-Warning "❌ Developer Mode is not enabled. Enable it in Settings > For Developers or via registry."
        return $false
    }

    Write-Verbose "Developer Mode is enabled. Searching for Windows SDK packages..."

    # --- Find latest Windows SDK ---
    $output = winget search "Windows SDK" --accept-source-agreements | Out-String
    if (-not $output -or $output -notmatch $packageIdPrefix) {
        Write-Error "Could not find Windows SDK packages in winget."
        return $false
    }

    $ids = ($output -split "`r?`n") |
        Where-Object { $_ -match $packageIdPrefix } |
        ForEach-Object { ($_ -split '\s+')[0] } |
        Sort-Object -Unique

    if (-not $ids) {
        Write-Error "No matching Windows SDK packages found."
        return $false
    }

    $versions = $ids | ForEach-Object { $_ -replace [regex]::Escape($packageIdPrefix), '' }
    $latestVersion = ($versions | Sort-Object { [version]$_ } -Descending)[0]

    if (-not $latestVersion) {
        Write-Error "Could not determine the latest SDK version."
        return $false
    }

    $latestId = "$packageIdPrefix$latestVersion"
    Write-Verbose "Latest Windows SDK version detected: $latestVersion (ID: $latestId)"

    # --- Install ---
    try {
        & winget install --id $latestId -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Windows SDK $latestVersion installed successfully."
            return $true
        } else {
            Write-Error "❌ Installation failed with exit code $LASTEXITCODE."
            return $false
        }
    }
    catch {
        Write-Error "❌ Exception during installation: $($_.Exception.Message)"
        return $false
    }
}

function Enable-DeveloperDevicePortal {
    ## Device Discovery requires Windows SDK (1803 or later)
    ## 
    
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        Write-Error "❌ This function must be run as Administrator."
        return
    }

    Write-Verbose "Checking if Developer Mode is enabled..."
    if (-not (Test-DeveloperMode)) {
        Write-Warning "❌ Developer Mode is not enabled. Enable it in Settings > For Developers or via registry."
        return $false
    }

    if ( -not (Install-LatestWindowsSDK)) {
        Write-Warning "❌ WindowsSDK installation has failed (or wasn't found)"
        return $false
    }
        
    Write-Host "📦 Installing required Windows capabilities..."
    $capabilities = @(
        "DeviceDiscovery",
        "WindowsDeveloperMode",
        "DevicePortal"
    )

    foreach ($capability in $capabilities) {
        Write-Host "→ Installing $capability..."
        try {
            Add-WindowsCapability -Online -Name "${capability}~~~~0.0.1.0" -ErrorAction Stop
        }
        catch {
            Write-Warning "⚠️ Could not install ${capability}: $_"
        }
    }

    Write-Host "🔐 Enabling Device Portal via registry..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DevicePortal"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "EnableDevPortal" -Value 1 -Force

    Write-Host "🔄 Restarting services..."
    Try {
        Restart-Service -Name dmwappushservice -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "⚠️ Could not restart dmwappushservice: $_"
    }
    if (Get-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -Value 1
    }
    else {
        New-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -PropertyType DWORD -Value 1
    }

    ## Enable authentication (optional but recommended)
    if (Get-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -Value 1
    }
    else {
        New-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -PropertyType DWORD -Value 1
    }

    if (! (Test-Path -Path $WebMgrKeyPath)) {
        New-Item -Path $WebMgrKeyPath -ItemType Directory -Force
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -Value 0x0000c50b
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -PropertyType DWORD -Value 0x0000c50b
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -Value 1
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -PropertyType DWORD -Value 1
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -Value 0
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -PropertyType DWORD -Value 0
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -Value 0
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -PropertyType DWORD -Value 0
    }
    Get-Item -Path $WebMgrKeyPath
    # Open firewall port for Device Portal (usually 50080 for HTTP and 50443 for HTTPS)
    New-NetFirewallRule -DisplayName "Developer Device Portal HTTP" -Direction Inbound -LocalPort 50080 -Protocol TCP -Action Allow
    New-NetFirewallRule -DisplayName "Developer Device Portal HTTPS" -Direction Inbound -LocalPort 50443 -Protocol TCP -Action Allow
    Write-Host "🔄 Restarting Web Management Service..."
    Set-Service -Name webmanagement -StartupType Automatic
    Restart-Service -Name webmanagement -ErrorAction SilentlyContinue

    Write-Host "`n✅ Device Portal is enabled."
    Write-Host "   🔗 Open: https://localhost:50080"
}
#Enable-DeveloperDevicePortal

## Enable sudo, if installed
if (Get-Command sudo ) {
    sudo config --enable enable
    ## https://raw.githubusercontent.com/microsoft/sudo/refs/heads/main/scripts/sudo.ps1
}

## Enable/Install Features
#if ($PSVersionTable.PSVersion.Major -eq 5) {
#    Write-Output "Running in Windows PowerShell."
#    Import-Module DISM 
#}
#else {
#    Write-Output "Not running in Windows PowerShell."
#    Import-Module DISM -UseWindowsPowerShell
#}
$features_to_enable = @(
    "TFTP",
#    "MSMQ-Multicast",
    "Printing-PrintToPDFServices-Features",
    "TelnetClient",
    "ServicesForNFS-ClientOnly",
    "ClientForNFS"
    ## "SMB1Protocol-Deprecation",
    ## "SMB1Protocol-Client",
) | Sort-Object

$features_to_enable | ForEach-Object {
    try {
        Write-Output "Enabling Windows Feature: $_" 
        $feature = Get-WindowsOptionalFeature -FeatureName "$_" -Online
        if ($feature -and ($feature.State -eq "Disabled")) {
            Write-Output ("Enabling $_...") 
            Enable-WindowsOptionalFeature -FeatureName "$_" -Online -All -LimitAccess -NoRestart
        }
    }
    catch {
        Write-Output "Exception with $_"
        Exit-WithError $_
    }
}

$features_to_disable = @(
    "WorkFolders-Client"
) | Sort-Object

$features_to_disable | ForEach-Object {
    try {
        Write-Output "Disabling Windows Feature: $_" 
        $feature = Get-WindowsOptionalFeature -FeatureName "$_" -Online
        if ($feature -and ($feature.State -eq "Enabled")) {
            Write-Output ("Disabling $_...") 
            Disable-WindowsOptionalFeature -FeatureName "$_" -Online -NoRestart
        }
    }
    catch {
        Write-Output "Exception with $_"
        Exit-WithError $_
    }
}

## Check system resources before enabling Containers-DisposableClientVM
try {
    $cpuCores = (Get-WmiObject -Class Win32_Processor).NumberOfLogicalProcessors
    $ramGB = [math]::Round((Get-WmiObject -Class Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)

    if ($cpuCores -ge 4 -and $ramGB -ge 16) {
        Write-Output "Enabling Sandbox (disposable VM)"
        Enable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -All -Online -NoRestart
    }
    else {
        Write-Output "Insufficient resources to enable Windows Sandbox - require at least 4 CPU cores and 16GB of RAM." 
        Disable-WindowsOptionalFeature -FeatureName "Containers-DisposableClientVM" -Online -NoRestart
    }
}
catch {
    Write-Output "An exception occurred: $_" 
    Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
    Write-Output "Exception Message: $($_.Exception.Message)" 
    Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
}

## Show features for transcript
Get-WindowsOptionalFeature -Online | Select-Object FeatureName, State | Format-Table -AutoSize

## NFS example (or use WSL)
# mount -o anon \\10.1.1.211\mnt\vms Z:

## Get rid of Sysinternal EULA messages - if it get installed or is ever installed
## Local User
$Bin = "$env:SystemDrive\BIN"
if (-Not (Test-Path -Path "${Bin}" -PathType Container -ErrorAction SilentlyContinue)) {
    New-Item -Path "${Bin}" -Type Container
}
else {
    Write-Output "Directory $Bin already exists." 
}

Write-Output "Turning off Sysinternals EULA prompt." 
if (-not (Test-Path -Path "HKCU:\Software\Sysinternals")) {
    New-Item -Path "HKCU:\Software\Sysinternals" -Force | Out-Null
}
if (-not (Test-Path -Path "HKLM:\Software\Sysinternals")) {
    New-Item -Path "HKLM:\Software\Sysinternals" -Force | Out-Null
}

if (Get-ItemProperty -Path "HKCU:\Software\Sysinternals" -Name "EulaAccepted" -ErrorAction SilentlyContinue) {
    Set-ItemProperty -Path "HKCU:\Software\Sysinternals" -Name "EulaAccepted" -Value 1
}
else {
    New-ItemProperty -Path "HKCU:\Software\Sysinternals" -Name "EulaAccepted" -PropertyType DWORD -Value 1
}
if (Get-ItemProperty -Path "HKLM:\Software\Sysinternals" -Name "EulaAccepted" -ErrorAction SilentlyContinue) {
    Set-ItemProperty -Path "HKLM:\Software\Sysinternals" -Name "EulaAccepted" -Value 1
}
else {
    New-ItemProperty -Path "HKLM:\Software\Sysinternals" -Name "EulaAccepted" -PropertyType DWORD -Value 1
}

function Install-SysInternalsTools {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Bin
    )

    Write-Output "Installing a small subset of SysInternals tools..." 

    $tools = @(
#        @{ Name = "autoruns.exe";    Friendly = "Autoruns Tool.exe" },
#        @{ Name = "Autologon64.exe"; Friendly = "Auto Logon Utility.exe" },
        @{ Name = "ZoomIt64.exe";    Friendly = "ZoomIt Presentation Tool.exe" },
        @{ Name = "tcpview64.exe";   Friendly = "TCP View.exe" },
        @{ Name = "winobj64.exe";    Friendly = "Windows Object Viewer.exe" },
        @{ Name = "psping64.exe";    Friendly = "PS Ping.exe" },
        @{ Name = "procexp64.exe";   Friendly = "Process Explorer.exe" },
        @{ Name = "procmon64.exe";   Friendly = "Process Monitor.exe" },
        @{ Name = "RDCMan.exe";      Friendly = "Remote Desktop Manager.exe" }
#        @{ Name = "whois64.exe";     Friendly = "Whois Utility.exe" },
#        @{ Name = "PsExec64.exe";    Friendly = "PS Exec.exe" },
#        @{ Name = "Psfile64.exe";    Friendly = "PS File.exe" }
    )

    foreach ($entry in $tools) {
        $tool = $entry.Name
        $friendlyName = $entry.Friendly
        $url = "https://live.sysinternals.com/$tool"
        if ([string]::IsNullOrWhiteSpace($friendlyName)) {
            $outfile = Join-Path -Path $Bin -ChildPath $tool
        } else {
            $outfile = Join-Path -Path $Bin -ChildPath $friendlyName
        }
        Invoke-WebRequest -Uri $url -OutFile $outfile
    }
    ##Invoke-WebRequest -Uri https://www.7-zip.org/a/7z2409-x64.exe -OutFile $Bin\unzip.exe
}
Install-SysInternalsTools -Bin $Bin
Add-MpPreference -ExclusionPath $BIN

function Add-WSLShortcutToDesktop {
    <#
    .SYNOPSIS
        Creates a shortcut to launch WSL on the current user's desktop.

    .DESCRIPTION
        Adds a Windows shortcut to the user's desktop to launch the default WSL distro,
        or a specific one if specified. Supports custom arguments and icons.

    .PARAMETER Distro
        (Optional) The name of a specific WSL distribution to launch.

    .PARAMETER Arguments
        (Optional) Additional arguments to pass to WSL (e.g., `--exec bash`).

    .PARAMETER ShortcutName
        (Optional) Name of the shortcut (default is "WSL Terminal").

    .PARAMETER IconPath
        (Optional) Custom icon path for the shortcut.

    .EXAMPLE
        Add-WSLShortcutToDesktop

    .EXAMPLE
        Add-WSLShortcutToDesktop -Distro "Ubuntu" -ShortcutName "Ubuntu WSL"
    #>

    [CmdletBinding()]
    param (
        [string]$Distro = "",
        [string]$Arguments = "",
        [string]$ShortcutName = "WSL Terminal",
        [string]$IconPath = "$env:SystemRoot\System32\wsl.exe,0"
    )

    # Determine desktop path
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path -Path $desktopPath -ChildPath "$ShortcutName.lnk"

    # Build full argument string
    $fullArguments = ""
    if ($Distro) {
        $fullArguments += "--distribution `"$Distro`" "
    }
    if ($Arguments) {
        $fullArguments += $Arguments
    }

    try {
        # Create COM object and shortcut
        $wshShell = New-Object -ComObject WScript.Shell
        $shortcut = $wshShell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "wsl.exe"
        $shortcut.Arguments = $fullArguments.Trim()
        $shortcut.WorkingDirectory = "$HOME"
        $shortcut.WindowStyle = 1  # Normal window
        $shortcut.IconLocation = $IconPath
        $shortcut.Save()

        Write-Host "✅ Shortcut created: $shortcutPath"
    }
    catch {
        Write-Error "❌ Failed to create WSL shortcut: $_"
    }
}
Add-WSLShortcutToDesktop



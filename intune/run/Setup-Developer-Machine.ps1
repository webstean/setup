#Requires -RunAsAdministrator

$elapsed = [System.Diagnostics.Stopwatch]::StartNew()

## Base URL for raw GitHub content (public`)
$baseUrl = "https://raw.githubusercontent.com/webstean/setup//main/intune/"

## List of script files to download and run
$filesToDownload = @(
    "Config-Normal-Machine.ps1",
    "developer.winget",
    "Install-Developer-Fonts.ps1",
    "Install-Developer-PowershellModules.ps1",
    "Install-Developer-System.ps1",
    "Install-Developer-User.ps1",
    ##"Install-Global-Secure-Access-Client.ps1",
    "Install-Windows-Admin-Centre.ps1",
    "Setup-StarShip-Shell.ps1",
    "logo.png",
    "wallpaper.jpg"
    # Add more filenames as needed
)

Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
if ($ExecutionContext.SessionState.LanguageMode -ne "FullLanguage") {
    Write-Output "PowerShell is NOT running in FullLanguage mode. Current mode: $($ExecutionContext.SessionState.LanguageMode)"  
}
Write-Output "Current Powershell Language mode is $($ExecutionContext.SessionState.LanguageMode)"  
Get-ExecutionPolicy -List | Format-Table -AutoSize

# Be aware, if running via Intune, then logs will be created in: "$($env:ProgramData)\Microsoft\IntuneManagementExtension\Logs"

# Local folder to save downloaded scripts
$TranscriptDir  = "$($env:ProgramData)\$($env:USERDOMAIN)\Transcripts"
$TranscriptFile = "$($env:ProgramData)\$($env:USERDOMAIN)\Transcripts\$($(Split-Path $PSCommandPath -Leaf).ToLower().Replace(".ps1",".log"))"
if (-not (Test-Path "$TranscriptDir")) {
    New-Item -Path "$TranscriptDir" -ItemType Directory | Out-Null
}
## Start again with Transcript File if it over 4MB in size
if (Test-Path "$TranscriptFile") {
    Get-ChildItem -File $TranscriptFile | Where-Object Length -gt 4MB | Clear-Content -Force
}
Start-Transcript -Path $TranscriptFile -Append -Force -IncludeInvocationHeader -ErrorAction SilentlyContinue
## For the transcript: Running in Azure Automation
if ($env:AUTOMATION_ASSET_ACCOUNTID) {
    Write-Output "Running in Azure Automation: $env:AUTOMATION_ASSET_ACCOUNTID"
}

Write-Output "Retrieving current user information..." 
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Output "Current User is: $currentUser" 
$systemcontext = [System.Security.Principal.WindowsIdentity]::GetCurrent().IsSystem
Write-Output "System Context : $systemcontext" 
Write-Output "Env: User Profile: $env:USERPROFILE" 

Write-Host ("Setting PowerShell to UTF-8 output encoding...")
[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

# Check if winget is installed
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($winget) {
    Write-Host "✅ Winget is already installed. Version:" 
    winget --version
} else {
    Write-Host "⚠️ Winget is not installed. Installing..."

    # Winget comes with the "App Installer" package from Microsoft Store
    # Try to install App Installer using winget’s official MSIX package
    $url = "https://aka.ms/getwinget"
    $installerPath = "$env:TEMP\AppInstaller.msixbundle"

    Write-Host "Downloading Winget installer..."
    Invoke-WebRequest -Uri $url -OutFile $installerPath

    Write-Host "Installing Winget..."
    Add-AppxPackage -Path $installerPath

    # Verify installation
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "✅ Winget installed successfully. Version:" 
        winget --version
        winget source export
        
    } else {
        Write-Host "❌ Winget installation failed. You may need to update Windows or install manually from Microsoft Store."
        exit 1
    }
}
winget install Microsoft.Powershell --silent --accept-package-agreements --accept-source-agreements


# Local folder to save downloaded scripts
function New-EmptyTempDirectory {
    [CmdletBinding()]
    param()

    # $env:TEMP gives us the temp folder path
    $basePath = $env:TEMP

    # Use New-Guid (PowerShell 5+) to generate a unique name
    $uniqueName = (New-Guid).Guid
    $fullPath = Join-Path -Path $basePath -ChildPath $uniqueName

    # Ensure it's empty: remove if somehow it already exists
    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Create the empty directory
    $null = New-Item -ItemType Directory -Path $fullPath -Force

    # Return the path as string
    return $fullPath
}
$destination = New-EmptyTempDirectory

# Just download the files - do not execute
function Invoke-GitHub-Download {
    foreach ($file in $filesToDownload) {
        $url = "$baseUrl/$file"
        $filedestination = Join-Path -Path $destination -ChildPath $file
        Write-Output "Downloading (no execute): $url... to $filedestination"
        Invoke-WebRequest -Uri $url -OutFile $filedestination -UseBasicParsing
    }
}

function Invoke-AzBlob-Download {
    <#
    .SYNOPSIS
        Download a list of blobs from Azure Blob Storage using a SAS token.

    .PARAMETER StorageAccount
        Storage account name (e.g., mystorageacct)

    .PARAMETER Container
        Container name (e.g., tools)

    .PARAMETER SasToken
        SAS token string. Can start with '?' or not.

    .PARAMETER FilesToDownload
        Array of blob paths relative to the container (e.g., 'folder/tool.exe')

    .PARAMETER Destination
        Local destination folder. Subfolders are created as needed.

    .PARAMETER Overwrite
        Overwrite existing files if present.

    .PARAMETER MaxRetries
        Number of retries per file (default: 3)

    .PARAMETER RetryDelaySeconds
        Base delay between retries, backoff is linear (default: 2)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StorageAccount,
        [Parameter(Mandatory)][string]$Container,
        [Parameter(Mandatory)][string]$SasToken,
        [Parameter(Mandatory)][string[]]$FilesToDownload = $filesToDownload,
        [Parameter(Mandatory)][string]$Destination = $destination,
        [bool]$Overwrite = $true,
        [int]$MaxRetries = 3,
        [int]$RetryDelaySeconds = 2
    )

    # Normalize SAS (ensure it starts with '?')
    $sas = $SasToken.Trim()
    if ($sas -and -not $sas.StartsWith('?')) { $sas = '?' + $sas }

    # Base URL (public cloud)
    $baseUrl = "https://$StorageAccount.blob.core.windows.net/$Container"

    # Ensure destination exists
    if (-not (Test-Path -LiteralPath $Destination)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    foreach ($file in $FilesToDownload) {
        # Encode path parts safely (keeps slashes, escapes spaces etc.)
        $escapedPath = [System.Uri]::EscapeUriString($file)
        $uri = "$baseUrl/$escapedPath$sas"

        $fileDestination = Join-Path -Path $Destination -ChildPath $file
        $destDir = Split-Path -Path $fileDestination -Parent
        if (-not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        if ((-not $Overwrite) -and (Test-Path -LiteralPath $fileDestination)) {
            Write-Output "Skip (exists): $fileDestination"
            continue
        }

        Write-Output "Downloading: $uri -> $fileDestination"

        $attempt = 0
        $downloaded = $false
        while (-not $downloaded -and $attempt -lt $MaxRetries) {
            $attempt++
            try {
                # Optional header helps some environments; harmless otherwise
                $headers = @{ 'x-ms-version' = '2020-10-02' }
                Invoke-WebRequest -Uri $uri -OutFile $fileDestination -UseBasicParsing -Headers $headers -ErrorAction Stop
                $downloaded = $true
            }
            catch {
                if ($attempt -ge $MaxRetries) {
                    Write-Warning "Failed to download '$file' after $MaxRetries attempt(s). Error: $($_.Exception.Message)"
                } else {
                    $sleep = $RetryDelaySeconds * $attempt
                    Write-Output "Retry $attempt/$MaxRetries in ${sleep}s for '$file'..."
                    Start-Sleep -Seconds $sleep
                }
            }
        }
    }
}

function Invoke-ScriptReliably {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [string[]]$ScriptArgs,
        [switch]$UsePwsh = $true,  # prefer PowerShell 7 if available
        [switch]$Elevate = $false, # run as admin (UAC prompt)
        [switch]$Force64Bit =$false,       # ensure 64-bit host on 64-bit Windows
        [string]$WorkingDirectory = $(Split-Path -Path $ScriptPath),
        [int]$TimeoutSeconds = 0,  # 0 = no timeout
        [switch]$Hidden = $false   # hide window
    )

    # Resolve and pre-flight
    $full = (Resolve-Path -LiteralPath $ScriptPath).Path
    if (Get-Item -LiteralPath $full -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Unblock-File -LiteralPath $full -ErrorAction SilentlyContinue
    }

    # Choose host: pwsh.exe (if asked/available) or Windows PowerShell (64-bit if requested)
    if ($UsePwsh -and (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        $hostExe = (Get-Command pwsh.exe).Source
    } else {
        if ($Force64Bit -and $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432) {
            # 32-bit process on 64-bit OS -> force 64-bit PowerShell via SysNative
            $hostExe = "$env:WINDIR\SysNative\WindowsPowerShell\v1.0\powershell.exe"
        } else {
            $hostExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
        }
    }

    # Build arguments
    $argList = @(
        '-NoLogo','-NoProfile','-NonInteractive',
        '-ExecutionPolicy','Bypass',
        '-File', "`"$full`""
    )
    if ($ScriptArgs) { $argList += @('--') + $ScriptArgs }

    # Log files next to the script
    $outFile = [IO.Path]::ChangeExtension($full, '.out.log')
    $errFile = [IO.Path]::ChangeExtension($full, '.err.log')

    $startInfo = @{
        FilePath                = $hostExe
        ArgumentList            = $argList
        WorkingDirectory        = $WorkingDirectory
        RedirectStandardOutput  = $outFile
        RedirectStandardError   = $errFile
        Wait                    = $true
        PassThru                = $true
        ErrorAction             = 'Stop'
    }
    if ($Elevate) { $startInfo.Verb = 'RunAs' }
    if ($Hidden)  { $startInfo.WindowStyle = 'Hidden' }

    $proc = Start-Process @startInfo

    # Optional timeout
    if ($TimeoutSeconds -gt 0 -and -not $proc.HasExited) {
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try { $proc.Kill() } catch {}
            throw "Timed out after $TimeoutSeconds seconds. See logs: `"$outFile`", `"$errFile`"."
        }
    } else {
        $proc.WaitForExit()
    }

    if ($proc.ExitCode -ne 0) {
        $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        throw "Script failed with exit code $($proc.ExitCode). $err"
    }

    [pscustomobject]@{
        ExitCode     = $proc.ExitCode
        StdOutLog    = $outFile
        StdErrLog    = $errFile
        Host         = $hostExe
        WorkingDir   = $WorkingDirectory
    }
}

function Invoke-IfFileExists {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Host "EXECUTING: Stated $Path.."
        & $Path
        Write-Host "EXECUTING: Finished $Path.."
    }
    else {
        Write-Host "Failed to execute as script was not found: $Path"
    }
}

function Invoke-WingetConfiguration-Developer {
    #winget configure validate --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
    #winget configure show     --file developer.winget --ignore-warnings --disable-interactivity --verbose-logs
    if ( Test-Path "${destination}\developer.winget" ) {
        #winget configure --file developer.winget --accept-configuration-agreements --suppress-initial-details --disable-interactivity --verbose-logs
        winget configure --file ${destination}\developer.winget --accept-configuration-agreements --suppress-initial-details --disable-interactivity --verbose-logs
    } else {
        Write-Host "${destination}\developer.winget not found!!"
        Read-Host "Press Enter to continue..."
    }
    return ;
    ## get-childitem     $env:LOCALAPPDATA\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir\
    #if (-not (Get-Module -ListAvailable -Name Microsoft.WinGet.Client)) {
    #Install-Module Microsoft.WinGet.Client -Force -Scope CurrentUser
    #}
    #if (-not (Get-Module -Name Microsoft.WinGet.Client)) {
    #Import-Module Microsoft.WinGet.Client
    #}
    #if (-not (Get-Module -Name Microsoft.WinGet.Configuration)) {
    #Import-Module Microsoft.WinGet.Configuration
    #}
    #$configSet = Get-WinGetConfiguration -File developer.winget
    #Invoke-WinGetConfiguration -Set $configSet -AcceptConfigurationAgreements
}

## Execute downloaded scripts
try {
    Write-Host "******************= Scripts to EXECUTE =******************************"
    Invoke-GitHub-Download
    If ( Test-Path "$destination\wallpaper.jpg" ) {
        #Copy-Item "wallpaper.jpg" "$env:ALLUSERSPROFILE\default-wallpaper.jpg" -Force -ErrorAction SilentlyContinue
        Copy-Item "$destination\wallpaper.jpg" "$env:ALLUSERSPROFILE\default-wallpaper.jpg" -Force -ErrorAction SilentlyContinue
    }
    If ( Test-Path "$destination\logo.png" ) {
        #Copy-Item "logo.png" "$env:ALLUSERSPROFILE\logo.png" -Force -ErrorAction SilentlyContinue
        Copy-Item "$destination\logo.png" "$env:ALLUSERSPROFILE\logo.png" -Force -ErrorAction SilentlyContinue
    }
   
    ### Normal Machine ###
    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists "$destination\Config-Normal-Machine.ps1"
    $csw.Stop()
    Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."

    if ($env:IsDevBox -eq "True" -or $true) {
        Write-Host "*** This is a Develper Machine ***"

        ### DEVELOPER Machine ###
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WingetConfiguration-Developer
        $csw.Stop()
        Write-Host "⏳ winget configuration completed in $($csw.Elapsed.Minutes) minutes."

        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Developer-PowerShellModules.ps1"
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Global-Secure-Access-Client.ps1"
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Windows-Admin-Centre.ps1"
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Developer-Fonts.ps1" ## need ZIP from PowerShell modules
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Developer-System.ps1" ## installs dotnet, that we need later
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists "$destination\Install-Developer-User.ps1"
        #Invoke-ScriptReliably "$destination\Install-Developer-User.ps1"
        $csw.Stop()
        Write-Host "⏳ Script completed in $($csw.Elapsed.Minutes) minutes."
    }
    
    Write-Host "******************= All scripts executed =******************************"
    $elapsed.Stop()
    Write-Host "⏳ All STEP completed in $($elapsed.Elapsed.Minutes) minutes."
}
catch {
    Write-Error "Error executing: $_"
}
finally {
    # Stop transcript no matter what
    Stop-Transcript
    Write-Host "Transcript stopped."
    Write-Host "COMPLETED."
}
return $true


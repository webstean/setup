#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

## Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/intune/run/Setup-Developer-Machine.ps1' -OutFile '.\Setup-Developer-Machine.ps1'

$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$totalElapsed = [System.Diagnostics.Stopwatch]::StartNew()

$global:TranscriptStarted = $false
$global:destination = $null

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Level = 'INFO'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

function Invoke-WindowsPowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$AsAdmin = $true
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $ps51 = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command', $ScriptBlock
    )

    if ($AsAdmin) {
        Start-Process -FilePath $ps51 -ArgumentList $arguments -Verb RunAs -Wait -ErrorAction Stop | Out-Null
        return
    }

    & $ps51 @arguments
}

function Install-LatestDotNetWindowsDesktopRuntime {
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('9', '8')]
        [string]$Major = '9',

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('x64', 'x86', 'arm64')]
        [string]$Architecture = 'x64'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'winget not found. Run Install-WinGetPrereqsAndAppInstaller first.'
    }

    $id = "Microsoft.DotNet.DesktopRuntime.$Major"

    & winget install --id $id --exact --source winget `
        --accept-source-agreements --accept-package-agreements `
        --disable-interactivity --silent --scope machine `
        --architecture $Architecture

    & "$env:ProgramFiles\dotnet\dotnet.exe" --list-runtimes |
    Select-String -Pattern "Microsoft\.WindowsDesktop\.App $Major\." |
    ForEach-Object { $_.Line }
}

function New-EmptyTempDirectory {
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $basePath = $env:TEMP
    if ([string]::IsNullOrWhiteSpace($basePath)) {
        throw 'TEMP environment variable is not set.'
    }

    $uniqueName = (New-Guid).Guid
    $fullPath = Join-Path -Path $basePath -ChildPath $uniqueName

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    $null = New-Item -ItemType Directory -Path $fullPath -Force
    return $fullPath
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $parent = Split-Path -Path $OutFile -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    Write-Log -Message "Downloading: $Uri -> $OutFile"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
}

function Invoke-GitHub-Download {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$FilesToDownload,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    foreach ($fileName in $FilesToDownload) {
        $url = ($BaseUrl.TrimEnd('/') + '/' + $fileName)
        $fileDestination = Join-Path -Path $Destination -ChildPath $fileName
        Invoke-DownloadFile -Uri $url -OutFile $fileDestination
    }
}

function Invoke-ExtraFile-Download {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$ExtraFilesToDownload,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    foreach ($url in $ExtraFilesToDownload) {
        $fileName = [System.IO.Path]::GetFileName(([System.Uri]$url).AbsolutePath)
        $fileDestination = Join-Path -Path $Destination -ChildPath $fileName
        Invoke-DownloadFile -Uri $url -OutFile $fileDestination
    }
}

function Invoke-ScriptReliably {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptPath,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string[]]$ScriptArgs = @(),

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$UsePwsh = $true,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Elevate = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Force64Bit = $false,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$WorkingDirectory = (Split-Path -Path $ScriptPath -Parent),

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 86400)]
        [int]$TimeoutSeconds = 0,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Hidden = $false
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $full = (Resolve-Path -LiteralPath $ScriptPath).Path
    if (Get-Item -LiteralPath $full -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Unblock-File -LiteralPath $full -ErrorAction SilentlyContinue
    }

    if ($UsePwsh -and (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        $hostExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    } elseif ($Force64Bit -and $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432) {
        $hostExe = Join-Path -Path $env:WINDIR -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    } else {
        $hostExe = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $argList = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $full
    )
    if ($ScriptArgs.Count -gt 0) {
        $argList += $ScriptArgs
    }

    $outFile = [System.IO.Path]::ChangeExtension($full, '.out.log')
    $errFile = [System.IO.Path]::ChangeExtension($full, '.err.log')

    if ($Elevate) {
        $elevatedArguments = $argList | ForEach-Object {
            if ($_ -match '\s') { '"' + $_.Replace('"', '""') + '"' } else { $_ }
        }

        Start-Process -FilePath $hostExe -ArgumentList $elevatedArguments -WorkingDirectory $WorkingDirectory -Verb RunAs -Wait -ErrorAction Stop | Out-Null
        return [pscustomobject]@{
            ExitCode   = 0
            StdOutLog  = ''
            StdErrLog  = ''
            Host       = $hostExe
            WorkingDir = $WorkingDirectory
        }
    }

    $startInfo = @{
        FilePath               = $hostExe
        ArgumentList           = $argList
        WorkingDirectory       = $WorkingDirectory
        RedirectStandardOutput = $outFile
        RedirectStandardError  = $errFile
        Wait                   = $true
        PassThru               = $true
        ErrorAction            = 'Stop'
    }

    if ($Hidden) {
        $startInfo.WindowStyle = 'Hidden'
    }

    $proc = Start-Process @startInfo

    if ($TimeoutSeconds -gt 0 -and -not $proc.HasExited) {
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $proc.Kill()
            } catch {
                Write-Log -Message "Failed to kill timed-out process for $ScriptPath. $($_.Exception.Message)" -Level 'WARN'
            }

            throw "Timed out after $TimeoutSeconds seconds. See logs: '$outFile', '$errFile'."
        }
    } else {
        $proc.WaitForExit()
    }

    if ($proc.ExitCode -ne 0) {
        $err = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        throw "Script failed with exit code $($proc.ExitCode). $err"
    }

    return [pscustomobject]@{
        ExitCode   = $proc.ExitCode
        StdOutLog  = $outFile
        StdErrLog  = $errFile
        Host       = $hostExe
        WorkingDir = $WorkingDirectory
    }
}

function Invoke-IfFileExists {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$UsePwsh = $true
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log -Message "Script was not found: $Path" -Level 'WARN'
        return
    }

    Write-Log -Message "EXECUTING: Started $Path"
    $result = Invoke-ScriptReliably -ScriptPath $Path -UsePwsh $UsePwsh -Elevate $false -Force64Bit $true
    Write-Log -Message "EXECUTING: Finished $Path with exit code $($result.ExitCode)"
}

$microsoftConfig = $null
$developerConfig = $null
function Set-WingetConfiguration-Developer {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    winget configure --enable
    winget settings --enable ProxyCommandLineOptions

    $script:developerConfig = Join-Path -Path $Destination -ChildPath 'developer.winget'
    $script:microsoftConfig = Join-Path -Path $Destination -ChildPath 'dev-config.winget'

    if (-not (Test-Path -LiteralPath $script:microsoftConfig)) {
        throw "'$script:microsoftConfig' from Microsoft not found."
    }

    if (-not (Test-Path -LiteralPath $script:developerConfig)) {
        throw "'$script:developerConfig' not found."
    }
}

function Initialize-TranscriptLogging {
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $domainName = if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN)) { 'UnknownDomain' } else { $env:USERDOMAIN }
    $transcriptDir = Join-Path -Path $env:ProgramData -ChildPath "$domainName\Transcripts"

    $commandName = if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        'setup-developer-machine.ps1'
    } else {
        Split-Path -Path $PSCommandPath -Leaf
    }

    $transcriptFile = Join-Path -Path $transcriptDir -ChildPath ($commandName.ToLowerInvariant().Replace('.ps1', '.log'))

    if (-not (Test-Path -LiteralPath $transcriptDir)) {
        $null = New-Item -Path $transcriptDir -ItemType Directory -Force
    }

    if (Test-Path -LiteralPath $transcriptFile) {
        $existing = Get-Item -LiteralPath $transcriptFile -ErrorAction Stop
        if ($existing.Length -gt 4MB) {
            Clear-Content -LiteralPath $transcriptFile -Force
        }
    }

    Start-Transcript -Path $transcriptFile -Append -Force -IncludeInvocationHeader
    $global:TranscriptStarted = $true
    return $transcriptFile
}

function Install-WinGetIfMissing {
    param()

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -ne $winget) {
        Write-Log -Message 'Winget is already installed.'
        & winget --version
        return
    }

    Write-Log -Message 'Winget is not installed. Installing App Installer bundle.' -Level 'WARN'
    $url = 'https://aka.ms/getwinget'
    $installerPath = Join-Path -Path $env:TEMP -ChildPath 'AppInstaller.msixbundle'

    Invoke-DownloadFile -Uri $url -OutFile $installerPath
    Add-AppxPackage -Path $installerPath -ErrorAction Stop

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw 'Winget installation failed. You may need to update Windows or install manually from Microsoft Store.'
    }

    Write-Log -Message 'Winget installed successfully.'
    & winget --version
}

try {
    $baseUrl = 'https://raw.githubusercontent.com/webstean/setup/main/intune'
    $filesToDownload = @(
        'Config-Normal-Machine.ps1',
        'developer.winget',
        'developer-mcp.winget',
        'Install-Developer-Fonts.ps1',
        'Install-Developer-PowershellModules.ps1',
        'Install-Developer-System.ps1',
        'Install-Developer-User.ps1',
        'Install-Global-Secure-Access-Client.ps1',
        'Install-Windows-Admin-Centre.ps1',
        'Setup-StarShip-Shell.ps1',
        'Setup-MCP-Gateway.ps1',
        'starship_pill.toml',
        'logo1.png',
        'logo2.jpg',
        'logo3.png',
        'wallpaper.jpg'
    )

    $extraFilesToDownload = @(
        'https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/refs/heads/main/windows-dev-config/dev-config.winget'
    )

    try {
        Write-Log -Message 'Initializing PowerShell execution policy...'
        Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
        if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
            Write-Log -Message "PowerShell is NOT running in FullLanguage mode. Current mode: $($ExecutionContext.SessionState.LanguageMode)" -Level 'WARN'
        }

        Write-Log -Message "Current PowerShell Language mode is $($ExecutionContext.SessionState.LanguageMode)"
        Get-ExecutionPolicy -List | Format-Table -AutoSize
    } catch {
        Write-Log -Message "Error during PowerShell initialization: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        Write-Log -Message 'Initializing transcript logging...'
        $transcriptFile = Initialize-TranscriptLogging
        Write-Log -Message "Transcript started: $transcriptFile"
    } catch {
        Write-Log -Message "Error initializing transcript: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    if ($env:AUTOMATION_ASSET_ACCOUNTID) {
        Write-Log -Message "Running in Azure Automation: $env:AUTOMATION_ASSET_ACCOUNTID"
    }

    try {
        Write-Log -Message 'Retrieving current user information...'
        $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        Write-Log -Message "Current User is: $($currentIdentity.Name)"
        Write-Log -Message "System Context: $($currentIdentity.IsSystem)"
        Write-Log -Message "Env: User Profile: $env:USERPROFILE"
    } catch {
        Write-Log -Message "Error retrieving user information: $($_.Exception.Message)" -Level 'WARN'
    }

    try {
        Write-Log -Message 'Setting PowerShell to UTF-8 output encoding...'
        [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    } catch {
        Write-Log -Message "Error setting UTF-8 encoding: $($_.Exception.Message)" -Level 'WARN'
    }

    try {
        Write-Log -Message 'Installing/verifying WinGet...'
        Install-WinGetIfMissing
    } catch {
        Write-Log -Message "Error installing WinGet: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        Write-Log -Message 'Enabling WinGet configuration feature...'
        winget configure --enable
    } catch {
        Write-Log -Message "Error enabling WinGet configuration: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        Write-Log -Message 'Installing Microsoft.PowerShell...'
        winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Log -Message "Error installing Microsoft.PowerShell: $($_.Exception.Message)" -Level 'WARN'
        Write-Log -Message 'Continuing despite PowerShell installation error...'
    }

    try {
        Write-Log -Message 'Creating temporary working directory...'
        $global:destination = New-EmptyTempDirectory
        Write-Log -Message "Working directory: $global:destination"
    } catch {
        Write-Log -Message "Error creating temp directory: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        Write-Log -Message 'Downloading repository assets from GitHub...'
        Invoke-GitHub-Download -BaseUrl $baseUrl -FilesToDownload $filesToDownload -Destination $global:destination
    } catch {
        Write-Log -Message "Error downloading GitHub files: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        Write-Log -Message "Failed files: $($filesToDownload -join ', ')" -Level 'ERROR'
        throw
    }

    try {
        Write-Log -Message 'Downloading extra configuration files...'
        Invoke-ExtraFile-Download -ExtraFilesToDownload $extraFilesToDownload -Destination $global:destination
    } catch {
        Write-Log -Message "Error downloading extra files: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        Write-Log -Message "Failed URLs: $($extraFilesToDownload -join ', ')" -Level 'ERROR'
        throw
    }

    try {
        $wallpaperPath = Join-Path -Path $global:destination -ChildPath 'wallpaper.jpg'
        if (Test-Path -LiteralPath $wallpaperPath) {
            Write-Log -Message "Copying wallpaper to $env:ALLUSERSPROFILE..."
            Copy-Item -LiteralPath $wallpaperPath -Destination "$env:ALLUSERSPROFILE\default-wallpaper.jpg" -Force -ErrorAction Stop
            Write-Log -Message 'Wallpaper copied successfully.'
        } else {
            Write-Log -Message 'Wallpaper file not found.' -Level 'WARN'
        }
    } catch {
        Write-Log -Message "Error copying wallpaper: $($_.Exception.Message)" -Level 'WARN'
    }

    try {
        #$logoPath = Join-Path -Path $global:destination -ChildPath 'logo1.png'
        $logoPath = Join-Path -Path $global:destination -ChildPath 'logo2.jpg'
        #$logoPath = Join-Path -Path $global:destination -ChildPath 'logo3.png'
        if (Test-Path -LiteralPath $logoPath) {
            Write-Log -Message "Copying logo to $env:ALLUSERSPROFILE..."
            Copy-Item -LiteralPath $logoPath -Destination "$env:ALLUSERSPROFILE\logo.jpg" -Force -ErrorAction Stop
            Write-Log -Message 'Logo copied successfully.'
        } else {
            Write-Log -Message 'Logo file not found.' -Level 'WARN'
        }
    } catch {
        Write-Log -Message "Error copying logo: $($_.Exception.Message)" -Level 'WARN'
    }

    Write-Log -Message '******************= Scripts to EXECUTE =******************************'

    try {
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-IfFileExists -Path (Join-Path -Path $global:destination -ChildPath 'Config-Normal-Machine.ps1')
        $csw.Stop()
        Write-Log -Message "Config-Normal-Machine completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."
    } catch {
        Write-Log -Message "Error executing Config-Normal-Machine.ps1: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log -Message 'Configuring WinGet for developer environment...'
        Set-WingetConfiguration-Developer -Destination $global:destination
        $csw.Stop()
        Write-Log -Message "WinGet configuration setup completed in $($csw.Elapsed.TotalSeconds.ToString('F2')) seconds."
    } catch {
        Write-Log -Message "Error configuring WinGet: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    try {
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log -Message "Applying developer WinGet configuration from: $script:developerConfig"
        winget configure --file "$script:developerConfig" --accept-configuration-agreements --disable-interactivity --verbose-logs --no-proxy
        $csw.Stop()
        Write-Log -Message "Developer winget configuration completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."
    } catch {
        Write-Log -Message "Error applying developer winget configuration: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        throw
    }

    #'Install-Windows-Admin-Centre.ps1',
    #'Install-Developer-Fonts.ps1',
    #'Install-Global-Secure-Access-Client.ps1',
    $developerScripts = @(
        'Install-Developer-PowershellModules.ps1',
        'Install-Developer-System.ps1',
        'Setup-MCP-Gateway.ps1',
        'Install-Developer-User.ps1'
    )

    $scriptCount = 0
    $scriptFailures = @()
    foreach ($developerScript in $developerScripts) {
        $scriptCount++
        try {
            $scriptPath = Join-Path -Path $global:destination -ChildPath $developerScript
            if (-not (Test-Path -LiteralPath $scriptPath)) {
                Write-Log -Message "Script not found: $scriptPath" -Level 'WARN'
                $scriptFailures += $developerScript
                continue
            }
            $csw = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Log -Message "[$scriptCount/$($developerScripts.Count)] Executing $developerScript..."
            Invoke-IfFileExists -Path $scriptPath
            $csw.Stop()
            Write-Log -Message "[$scriptCount/$($developerScripts.Count)] $developerScript completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."
        } catch {
            Write-Log -Message "Error executing ${developerScript}: $($_.Exception.Message)" -Level 'ERROR'
            Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
            $scriptFailures += $developerScript
            Write-Log -Message "Continuing with next script despite error in ${developerScript}" -Level 'WARN'
        }
    }

    if ($scriptFailures.Count -gt 0) {
        Write-Log -Message "Warning: $($scriptFailures.Count) developer script(s) failed or were not found: $($scriptFailures -join ', ')" -Level 'WARN'
    }

    Write-Log -Message '******************= All scripts executed =******************************'
    $elapsed.Stop()

    Write-Log -Message '******************= Started WinGetConfiguration (Microsoft)=******************************'
    try {
        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log -Message 'Setting up WinGet configuration for Microsoft dev-config...'
        Set-WingetConfiguration-Developer -Destination $global:destination
        Write-Log -Message "Applying Microsoft WinGet configuration from: $script:microsoftConfig"
        ## The Microsoft supplied config, include functionality to reboot and restart the winget configuration
        ## So it needs to be the last thing we do
        winget configure --file "$script:microsoftConfig" --accept-configuration-agreements --disable-interactivity --verbose-logs --no-proxy
        $csw.Stop()
        Write-Log -Message "All winget configuration steps completed in $($elapsed.Elapsed.TotalMinutes.ToString('F2')) minutes. WinGet may enforce a reboot."
    } catch {
        Write-Log -Message "Error applying Microsoft WinGet configuration: $($_.Exception.Message)" -Level 'ERROR'
        Write-Log -Message "Stack Trace: $($_.Exception.StackTrace)" -Level 'ERROR'
        Write-Log -Message "Config file: $script:microsoftConfig" -Level 'ERROR'
        throw
    }
} catch {
    $invocation = $_.InvocationInfo
    $errorDetails = @{
        Message             = $_.Exception.Message
        StackTrace          = $_.Exception.StackTrace
        ExceptionType       = $_.Exception.GetType().FullName
        ScriptName          = $invocation.ScriptName
        LineNumber          = $invocation.ScriptLineNumber
        PositionMessage     = $invocation.PositionMessage
        CommandName         = $invocation.InvocationName
        FullyQualifiedError = $_.FullyQualifiedErrorId
    }

    try {
        $errorDetailsJson = ConvertTo-Json -InputObject $errorDetails -Depth 4 -Compress
    } catch {
        $errorDetailsJson = '{"message":"Failed to serialize error details for logging."}'
    }

    Write-Error "Fatal error executing script: $($_.Exception.Message)" -ErrorAction Continue
    Write-Log -Message "FATAL ERROR: $($_.Exception.Message)" -Level 'ERROR'
    Write-Log -Message "Exception Type: $($errorDetails.ExceptionType)" -Level 'ERROR'
    Write-Log -Message "Stack Trace: $($errorDetails.StackTrace)" -Level 'ERROR'
    Write-Log -Message "Script: $($errorDetails.ScriptName), Line: $($errorDetails.LineNumber)" -Level 'ERROR'
    Write-Log -Message "Full Error Details: $errorDetailsJson" -Level 'ERROR'
    throw
} finally {
    $elapsed.Stop()
    $scriptElapsedMinutes = '{0:F2}' -f $elapsed.Elapsed.TotalMinutes
    Write-Log -Message "Script execution total time: $scriptElapsedMinutes minutes." -Level 'INFO'
    $totalElapsed.Stop()
    $totalElapsedMinutes = '{0:F2}' -f $totalElapsed.Elapsed.TotalMinutes
    Write-Log -Message "Total running time was: $totalElapsedMinutes minutes." -Level 'INFO'

    if ($global:TranscriptStarted) {
        try {
            Write-Log -Message 'Finalizing transcript logging...'
            Stop-Transcript | Out-Null
            Write-Host 'Transcript stopped.'
        } catch {
            Write-Warning "Failed to stop transcript cleanly. $($_.Exception.Message)"
            Write-Log -Message "Warning: Could not stop transcript cleanly: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    Write-Log -Message '================ SCRIPT EXECUTION COMPLETED ================'
    Write-Host 'COMPLETED.'
}
return $true

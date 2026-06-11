#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

## Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/intune/run/Setup-Developer-Machine.ps1' -OutFile ".\Setup-Developer-Machine.ps1"

$elapsed = [System.Diagnostics.Stopwatch]::StartNew()
$global:TranscriptStarted = $false
$global:destination = $null

function Write-Log {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp] [$Level] $Message"
}

function Invoke-WindowsPowerShell {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$AsAdmin = $true
    )

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
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

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
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param()

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
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile
    )

    $parent = Split-Path -Path $OutFile -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }

    Write-Log -Message "Downloading: $Uri -> $OutFile"
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -ErrorAction Stop
}

function Invoke-GitHub-Download {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

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

    foreach ($fileName in $FilesToDownload) {
        $url = ($BaseUrl.TrimEnd('/') + '/' + $fileName)
        $fileDestination = Join-Path -Path $Destination -ChildPath $fileName
        Invoke-DownloadFile -Uri $url -OutFile $fileDestination
    }
}

function Invoke-ExtraFile-Download {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string[]]$ExtraFilesToDownload,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    foreach ($url in $ExtraFilesToDownload) {
        $fileName = [System.IO.Path]::GetFileName(([System.Uri]$url).AbsolutePath)
        $fileDestination = Join-Path -Path $Destination -ChildPath $fileName
        Invoke-DownloadFile -Uri $url -OutFile $fileDestination
    }
}

function Invoke-AzBlob-Download {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccount,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Container,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$SasToken,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [string[]]$FilesToDownload = @(),

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination = $global:destination,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$Overwrite = $true,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$MaxRetries = 3,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$RetryDelaySeconds = 2
    )

    $sas = $SasToken.Trim()
    if ($sas -and -not $sas.StartsWith('?')) {
        $sas = '?' + $sas
    }

    $baseUrl = "https://$StorageAccount.blob.core.windows.net/$Container"

    if (-not (Test-Path -LiteralPath $Destination)) {
        $null = New-Item -ItemType Directory -Path $Destination -Force
    }

    foreach ($file in $FilesToDownload) {
        $escapedPath = [System.Uri]::EscapeUriString($file)
        $uri = "$baseUrl/$escapedPath$sas"
        $fileDestination = Join-Path -Path $Destination -ChildPath $file
        $destDir = Split-Path -Path $fileDestination -Parent

        if (-not (Test-Path -LiteralPath $destDir)) {
            $null = New-Item -ItemType Directory -Path $destDir -Force
        }

        if ((-not $Overwrite) -and (Test-Path -LiteralPath $fileDestination)) {
            Write-Log -Message "Skip (exists): $fileDestination" -Level 'WARN'
            continue
        }

        $attempt = 0
        $downloaded = $false
        while (-not $downloaded -and $attempt -lt $MaxRetries) {
            $attempt++
            try {
                $headers = @{ 'x-ms-version' = '2020-10-02' }
                Invoke-WebRequest -Uri $uri -OutFile $fileDestination -Headers $headers -ErrorAction Stop
                $downloaded = $true
            }
            catch {
                if ($attempt -ge $MaxRetries) {
                    throw "Failed to download '$file' after $MaxRetries attempt(s). $($_.Exception.Message)"
                }

                $sleep = $RetryDelaySeconds * $attempt
                Write-Log -Message "Retry $attempt/$MaxRetries in ${sleep}s for '$file'." -Level 'WARN'
                Start-Sleep -Seconds $sleep
            }
        }
    }
}

function Invoke-ScriptReliably {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

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

    $full = (Resolve-Path -LiteralPath $ScriptPath).Path
    if (Get-Item -LiteralPath $full -Stream Zone.Identifier -ErrorAction SilentlyContinue) {
        Unblock-File -LiteralPath $full -ErrorAction SilentlyContinue
    }

    if ($UsePwsh -and (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) {
        $hostExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source
    }
    elseif ($Force64Bit -and $env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432) {
        $hostExe = Join-Path -Path $env:WINDIR -ChildPath 'SysNative\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
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
            }
            catch {
                Write-Log -Message "Failed to kill timed-out process for $ScriptPath. $($_.Exception.Message)" -Level 'WARN'
            }

            throw "Timed out after $TimeoutSeconds seconds. See logs: '$outFile', '$errFile'."
        }
    }
    else {
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
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter(Mandatory = $false)]
        [ValidateNotNull()]
        [bool]$UsePwsh = $true
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Log -Message "Script was not found: $Path" -Level 'WARN'
        return
    }

    Write-Log -Message "EXECUTING: Started $Path"
    $result = Invoke-ScriptReliably -ScriptPath $Path -UsePwsh $UsePwsh -Elevate $false -Force64Bit $true
    Write-Log -Message "EXECUTING: Finished $Path with exit code $($result.ExitCode)"
}

function Invoke-WingetConfiguration-Developer {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    winget configure --enable
    winget settings --enable ProxyCommandLineOptions

    $microsoftConfig = Join-Path -Path $Destination -ChildPath 'dev-config.winget'
    $developerConfig = Join-Path -Path $Destination -ChildPath 'developer.winget'

    if (-not (Test-Path -LiteralPath $microsoftConfig)) {
        throw "$microsoftConfig from Microsoft not found."
    }

    if (-not (Test-Path -LiteralPath $developerConfig)) {
        throw "$developerConfig not found."
    }

    winget configure --file $microsoftConfig --accept-configuration-agreements --disable-interactivity --verbose-logs --no-proxy
    winget configure --file $developerConfig --accept-configuration-agreements --disable-interactivity --verbose-logs --no-proxy
}

function Initialize-TranscriptLogging {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param()

    $domainName = if ([string]::IsNullOrWhiteSpace($env:USERDOMAIN)) { 'UnknownDomain' } else { $env:USERDOMAIN }
    $transcriptDir = Join-Path -Path $env:ProgramData -ChildPath "$domainName\Transcripts"

    $commandName = if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
        'setup-developer-machine.ps1'
    }
    else {
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

function Ensure-WinGetInstalled {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    param()

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
        'Install-Developer-Fonts.ps1',
        'Install-Developer-PowershellModules.ps1',
        'Install-Developer-System.ps1',
        'Install-Developer-User.ps1',
        'Install-Windows-Admin-Centre.ps1',
        'Setup-StarShip-Shell.ps1',
        'starship_pill.toml',
        'logo.png',
        'wallpaper.jpg'
    )

    $extraFilesToDownload = @(
        'https://raw.githubusercontent.com/microsoft/WindowsDeveloperConfig/refs/heads/main/windows-dev-config/dev-config.winget'
    )

    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Log -Message "PowerShell is NOT running in FullLanguage mode. Current mode: $($ExecutionContext.SessionState.LanguageMode)" -Level 'WARN'
    }

    Write-Log -Message "Current PowerShell Language mode is $($ExecutionContext.SessionState.LanguageMode)"
    Get-ExecutionPolicy -List | Format-Table -AutoSize

    $transcriptFile = Initialize-TranscriptLogging
    Write-Log -Message "Transcript started: $transcriptFile"

    if ($env:AUTOMATION_ASSET_ACCOUNTID) {
        Write-Log -Message "Running in Azure Automation: $env:AUTOMATION_ASSET_ACCOUNTID"
    }

    Write-Log -Message 'Retrieving current user information...'
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    Write-Log -Message "Current User is: $($currentIdentity.Name)"
    Write-Log -Message "System Context: $($currentIdentity.IsSystem)"
    Write-Log -Message "Env: User Profile: $env:USERPROFILE"

    Write-Log -Message 'Setting PowerShell to UTF-8 output encoding...'
    [Console]::InputEncoding = [System.Text.UTF8Encoding]::new()
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

    Ensure-WinGetInstalled
    winget configure --enable
    winget install Microsoft.PowerShell --silent --accept-package-agreements --accept-source-agreements

    $global:destination = New-EmptyTempDirectory
    Write-Log -Message "Working directory: $global:destination"

    Write-Log -Message 'Downloading repository assets...'
    Invoke-GitHub-Download -BaseUrl $baseUrl -FilesToDownload $filesToDownload -Destination $global:destination
    Invoke-ExtraFile-Download -ExtraFilesToDownload $extraFilesToDownload -Destination $global:destination

    $wallpaperPath = Join-Path -Path $global:destination -ChildPath 'wallpaper.jpg'
    if (Test-Path -LiteralPath $wallpaperPath) {
        Copy-Item -LiteralPath $wallpaperPath -Destination "$env:ALLUSERSPROFILE\default-wallpaper.jpg" -Force -ErrorAction SilentlyContinue
    }

    $logoPath = Join-Path -Path $global:destination -ChildPath 'logo.png'
    if (Test-Path -LiteralPath $logoPath) {
        Copy-Item -LiteralPath $logoPath -Destination "$env:ALLUSERSPROFILE\logo.png" -Force -ErrorAction SilentlyContinue
    }

    Write-Log -Message '******************= Scripts to EXECUTE =******************************'

    $csw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-IfFileExists -Path (Join-Path -Path $global:destination -ChildPath 'Config-Normal-Machine.ps1')
    $csw.Stop()
    Write-Log -Message "Config-Normal-Machine completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."

    if ($env:IsDevBox -eq 'True') {
        Write-Log -Message '*** This is a Developer Machine ***'

        $csw = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-WingetConfiguration-Developer -Destination $global:destination
        $csw.Stop()
        Write-Log -Message "winget configuration completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."

        $developerScripts = @(
            'Install-Developer-PowershellModules.ps1',
            'Install-Global-Secure-Access-Client.ps1',
            'Install-Windows-Admin-Centre.ps1',
            'Install-Developer-Fonts.ps1',
            'Install-Developer-System.ps1',
            'Install-Developer-User.ps1'
        )

        foreach ($developerScript in $developerScripts) {
            $csw = [System.Diagnostics.Stopwatch]::StartNew()
            Invoke-IfFileExists -Path (Join-Path -Path $global:destination -ChildPath $developerScript)
            $csw.Stop()
            Write-Log -Message "$developerScript completed in $($csw.Elapsed.TotalMinutes.ToString('F2')) minutes."
        }
    }
    else {
        Write-Log -Message 'Skipping developer-only steps because IsDevBox is not True.'
    }

    Write-Log -Message '******************= All scripts executed =******************************'
    $elapsed.Stop()
    Write-Log -Message "All steps completed in $($elapsed.Elapsed.TotalMinutes.ToString('F2')) minutes."
}
catch {
    Write-Error "Error executing script: $($_.Exception.Message)"
    throw
}
finally {
    if ($global:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
            Write-Host 'Transcript stopped.'
        }
        catch {
            Write-Warning "Failed to stop transcript cleanly. $($_.Exception.Message)"
        }
    }

    Write-Host 'COMPLETED.'
}

return $true

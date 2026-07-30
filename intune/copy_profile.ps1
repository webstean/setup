
# pwsh
# notepad $profile
# Paste this file's contents into it
# Save and Exit
# pwsh

# New-Item -ItemType File -Path $PROFILE -Force
# Invoke-RestMethod -Uri "https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/copy_profile.ps1" | Set-Content -Path $PROFILE -Force

# Install-PsResource -Name PnP.PowerShell -Scope CurrentUser
# Install-PsResource -Name Microsoft.Graph -Scope CurrentUser
# Install-PsResource -Name ExchangeOnlineManagement -Scope CurrentUser

# D: is temporary storage, with label: 'Temporary Storage',  290GB

function Test-DiskSpace {
    (Get-Volume -DriveLetter C).SizeRemaining | ForEach-Object {
        $sizeInGB = [math]::Round($_ / 1GB, 2)
        if ($sizeInGB -lt 5) {
            Write-Host "Warning: Free space on Drive C: less than 5GB. Space remaining is $sizeInGB GB!" -ForegroundColor Red
        }
    }

    $volumeD = Get-Volume -DriveLetter D -ErrorAction SilentlyContinue
    if ($volumeD) {
        $sizeInGB = [math]::Round($volumeD.SizeRemaining / 1GB, 2)
        Write-Host "Free space on Drive D: is ${sizeInGB}GB"

        if ($volumeD.FileSystemLabel -eq 'Temporary Storage') {
            Write-Host "Warning: Drive D: is labeled 'Temporary Storage' — data here is not persistent (lost on deallocation/redeploy)." -ForegroundColor Red
        }
    }
}
Test-DiskSpace

function Update-Profile {
    [CmdletBinding()]
    param()
    Invoke-RestMethod -Uri "https://raw.githubusercontent.com/webstean/setup/refs/heads/main/intune/copy_profile.ps1" | Set-Content -Path $PROFILE -Force
}


[int]$DefaultThreads = 16
[string]$DefaultHash = 'MD5'

[string]$LogDirectory = 'C:\Logs'
if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force *> $null }

$IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ----------------------------------------------------------------------------
# Elevation check
# ----------------------------------------------------------------------------
function Assert-LocalAdmin {
    [CmdletBinding()]
    param()
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This must be run from an elevated (Run as Administrator) PowerShell session. Current user: $($identity.Name)"
    }
}

# ----------------------------------------------------------------------------
# Test Internet Connection
# ----------------------------------------------------------------------------
function Test-InternetConnection {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $response = $null
    try {
        $request = [System.Net.WebRequest]::Create('http://www.msftconnecttest.com/connecttest.txt')
        $request.Timeout = 5000
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        if ($response.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
            return $true
        }
    } catch {
        return $false
    } finally {
        if ($null -ne $response) {
            $response.Close()
        }
    }

    return $false
}

# ----------------------------------------------------------------------------
# Write Logs
# ----------------------------------------------------------------------------
function Write-StepSummary {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [Parameter()]
        [ValidateSet('info', 'warning', 'success', 'error', 'debug', 'wait', 'waiting', 'warn', 'exception', 'skip', 'start', 'complete', 'completed')]
        [string]$Type = 'info',

        [Parameter()]
        [switch]$PassThru,

        [Parameter()]
        [bool]$ShowTimeStamp = $true
    
    )

    begin {
        $useGitHubSummary = -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)

        $prefixMap = @{
            exception = '❌❌'
            info      = 'ℹ️'
            success   = '✅'
            error     = '❌'
            debug     = '🔍'
            wait      = '⏳'
            waiting   = '⏳'
            warn      = '⚠️'
            warning   = '⚠️'
            skip      = '⏭️'
            start     = '🚀'
            complete  = '🏁'
            completed = '🏁'
        }

        $prefix = $prefixMap[$Type]
    }

    process {
        $text = if ($null -eq $InputObject) {
            ''
        } elseif ($InputObject -is [string]) {
            $InputObject
        } else {
            ($InputObject | Out-String).TrimEnd()
        }

        if ($showTimeStamp) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $line = "${timestamp}: ${prefix}: $text"
        } else {
            $line = "${prefix}: $text"
        }
        
        if ($useGitHubSummary) {
            Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value $line -Encoding utf8
        } else {

            switch ($Type) {
                'error' {
                    Write-Error -Message $line
                }

                'exception' {
                    Write-Error -Message $line
                }

                'debug' {
                    Write-Verbose -Message $line
                }

                { $_ -in @('warn', 'warning') } {
                    Write-Warning -Message $line
                }

                default {
                    Write-Host $line
                }
            }
        }
        if ($PassThru) {
            $line
        }
    }
}

function Test-NFS {
    [CmdletBinding()]
    param()
    # Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to install NFS.'
    }

    $feature = Get-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly -ErrorAction SilentlyContinue
    $service = Get-Service -Name NfsClnt -ErrorAction SilentlyContinue

    $installed     = ($feature.State -eq 'Enabled')
    $serviceExists = ($null -ne $service)

    [PSCustomObject]@{
        Installed     = $installed
        FeatureState  = $feature.State
        ServiceExists = $serviceExists
        ServiceStatus = if ($service) { $service.Status } else { $null }
        Available     = ($installed -and $serviceExists)
    }
}
   
function Install-WindowsNfsClient {
    [CmdletBinding()]
    param()
    # Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to install NFS.'
    }

    Write-StepSummary -type 'info' 'Checking if Windows NFS Client is installed...'
    $featureName = 'ServicesForNFS-ClientOnly'

    $feature = Get-WindowsOptionalFeature `
        -Online `
        -FeatureName $featureName `
        -ErrorAction SilentlyContinue

    if ($feature.State -ne 'Enabled') {
        Write-StepSummary -type 'info' 'Installing Windows NFS Client...'

        $result = Enable-WindowsOptionalFeature `
            -Online `
            -FeatureName $featureName `
            -All `
            -NoRestart `
            -ErrorAction Stop

        if ($result.RestartNeeded) {
            Write-StepSummary -type 'warning' 'A restart is required before the NFS client can be used.'
        }
    }

    $service = Get-Service -Name NfsClnt -ErrorAction Stop

    if ($service.StartType -ne 'Automatic') {
        Set-Service -Name NfsClnt -StartupType Automatic
    }

    if ($service.Status -ne 'Running') {
        Start-Service -Name NfsClnt
    }

    $service = Get-Service -Name NfsClnt

    [PSCustomObject]@{
        Installed       = $true
        FeatureState    = (Get-WindowsOptionalFeature -Online -FeatureName $featureName).State
        ServiceStatus   = $service.Status
        StartupType     = $service.StartType
        MountCommand    = [bool](Get-Command mount.exe -ErrorAction SilentlyContinue)
        RestartRequired = if ($result) { $result.RestartNeeded } else { $false }
        Ready           = (
            (Get-WindowsOptionalFeature -Online -FeatureName $featureName).State -eq 'Enabled' -and
            $service.Status -eq 'Running' -and
            (Get-Command mount.exe -ErrorAction SilentlyContinue)
        )
    }
}

function Invoke-RobocopyMirrorforNAS {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [ValidateRange(1, 128)]
        [int]$Threads = $DefaultThreads,
        [string]$LogDirectory = 'C:\Logs',
        [switch]$VerifyAfterCopy
    )

    Assert-LocalAdmin
    Set-MpPreference -DisableScanningNetworkFiles $true
    if (-not (Test-Path -LiteralPath $Source)) {
        throw "Source path not found: $Source"
    }
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force *> $null
    }

    # Diagnostic info only — must not land on the pipeline alongside the return object
    $robocopyVersion = (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { "Client" } else { "Server" }
    Write-Verbose "Robocopy $robocopyVersion on $type - $($os.Caption) (Build $($os.BuildNumber))"

    # Capture original Defender setting so it can be restored — this is a machine-wide
    # security-relevant setting and must not be left disabled after the function returns
    $originalDisableScanningNetworkFiles = $null
    $mpPreferenceChanged = $false
    try {
        $originalDisableScanningNetworkFiles = (Get-MpPreference -ErrorAction Stop).DisableScanningNetworkFiles
        Set-MpPreference -DisableScanningNetworkFiles $true -ErrorAction Stop
        $mpPreferenceChanged = $true
    }
    catch {
        Write-Warning "Could not adjust Defender network-file scanning preference (may require admin, or Defender is managed by policy): $($_.Exception.Message)"
    }

    # Ensure console/session can render non-English output correctly (cosmetic, but prevents
    # garbled display if anything gets written to host during the run)
    $originalOutputEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    $logPath = Join-Path -Path $LogDirectory -ChildPath "robocopy-mirror-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    $robocopyArgs = @(
        "`"$Source`"",
        "`"$Destination`"",
        "/MIR",
        "/COPY:DAT",
        "/DCOPY:DAT",
        "/MT:$Threads",
        "/R:1",
        "/W:1",
        "/NP",
        "/NDL",
        "/UNILOG:`"$logPath`"",   # Unicode-encoded log so non-English filenames render correctly (plain /LOG produces gibberish)
        "/UNICODE",                # forces Unicode console/output stream from robocopy itself
        "/TEE"
    )

    try {
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -Wait -NoNewWindow -PassThru
        if ($process.ExitCode -ge 8) {
            throw "Robocopy failed with exit code $($process.ExitCode). See log: $logPath"
        }

        $result = [PSCustomObject]@{
            Source          = $Source
            Destination     = $Destination
            ExitCode        = $process.ExitCode
            LogPath         = $logPath
            Success         = $true
            VerificationRun = $false
            MissingItems    = @()
        }

        # Robocopy can silently fail to copy items with malformed/invalid UTF-16 names
        # (unpaired surrogates) and reports success with no error. This step catches that
        # by independently comparing recursive item counts/paths, not relying on robocopy's own reporting.
        if ($VerifyAfterCopy) {
            Write-Verbose "Running post-copy verification for silent Unicode failures..."

            # OrdinalIgnoreCase: NTFS/SMB are case-insensitive, default HashSet comparer is not
            $sourceItems = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $destItems   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Source, '*', 'AllDirectories')) {
                [void]$sourceItems.Add($path.Substring($Source.Length).TrimStart('\'))
            }
            foreach ($path in [System.IO.Directory]::EnumerateFileSystemEntries($Destination, '*', 'AllDirectories')) {
                [void]$destItems.Add($path.Substring($Destination.Length).TrimStart('\'))
            }

            $missing = $sourceItems | Where-Object { -not $destItems.Contains($_) }
            $result.VerificationRun = $true
            $result.MissingItems = @($missing)
            if ($missing.Count -gt 0) {
                Write-Warning "$($missing.Count) item(s) present in source but missing from destination — possible malformed Unicode names. See MissingItems on the returned object."
            }
        }

        return $result
    }
    finally {
        [Console]::OutputEncoding = $originalOutputEncoding
        if ($mpPreferenceChanged) {
            Set-MpPreference -DisableScanningNetworkFiles $originalDisableScanningNetworkFiles
        }
    }
}

function Compare-FileChecksum {
    <#
    .SYNOPSIS
        Compares two files by MD5 checksum to verify they are identical.

    .DESCRIPTION
        Computes an MD5 hash for each file independently and compares them.
        Useful for verifying copy integrity across a migration/transfer path
        (e.g. NFS -> DataBox, robocopy destination verification) without
        relying on file size/timestamp alone.

    .PARAMETER Path1
        Path to the first file.

    .PARAMETER Path2
        Path to the second file, typically at a different location.

    .EXAMPLE
        Compare-FileChecksum -Path1 'D:\Source\file.zip' -Path2 '\\nas\share\file.zip'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path1,

        [Parameter(Mandatory)]
        [string]$Path2
    )

    if (-not (Test-Path -LiteralPath $Path1)) {
        throw "File not found: $Path1"
    }
    if (-not (Test-Path -LiteralPath $Path2)) {
        throw "File not found: $Path2"
    }

    $hash1 = Get-FileHash -LiteralPath $Path1 -Algorithm MD5
    $hash2 = Get-FileHash -LiteralPath $Path2 -Algorithm MD5

    [PSCustomObject]@{
        Path1      = $Path1
        Path2      = $Path2
        Hash1      = $hash1.Hash
        Hash2      = $hash2.Hash
        AreIdentical = $hash1.Hash -eq $hash2.Hash
    }
}

function Compare-DirectoryChecksum {
    <#
    .SYNOPSIS
        Compares two directories, one level deep only, verifying both file
        count and MD5 checksum match for every file.

    .DESCRIPTION
        Does NOT recurse into subdirectories — only files directly inside
        Path1/Path2 are compared. Subdirectories themselves are ignored
        entirely (neither counted nor descended into). Useful as a quick
        top-level integrity check after a copy/migration step, without the
        cost of a full recursive hash of an entire tree.

    .PARAMETER Path1
        First directory path.

    .PARAMETER Path2
        Second directory path, typically the migration/copy destination.

    .EXAMPLE
        Compare-DirectoryChecksum -Path1 'D:\Source\Finance' -Path2 '\\nas\share\Finance'

    .EXAMPLE
        Compare-DirectoryChecksum -Path1 'D:\Source' -Path2 'D:\Dest' | Select-Object -ExpandProperty MismatchedFiles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path1,

        [Parameter(Mandatory)]
        [string]$Path2
    )

    if (-not (Test-Path -LiteralPath $Path1 -PathType Container)) {
        throw "Directory not found: $Path1"
    }
    if (-not (Test-Path -LiteralPath $Path2 -PathType Container)) {
        throw "Directory not found: $Path2"
    }

    # -File with no -Recurse: only files directly in the folder, subfolders
    # are neither counted nor entered.
    $files1 = Get-ChildItem -LiteralPath $Path1 -File
    $files2 = Get-ChildItem -LiteralPath $Path2 -File

    $countMatch = $files1.Count -eq $files2.Count

    # Build name -> hash lookups so files are matched by name, not by
    # directory listing order (Get-ChildItem order isn't guaranteed identical
    # across two different filesystems/shares).
    $hashes1 = @{}
    foreach ($f in $files1) {
        $hashes1[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm $DefaultHash).Hash
    }
    $hashes2 = @{}
    foreach ($f in $files2) {
        $hashes2[$f.Name] = (Get-FileHash -LiteralPath $f.FullName -Algorithm $DefaultHash).Hash
    }

    $onlyInPath1 = @($hashes1.Keys | Where-Object { -not $hashes2.ContainsKey($_) })
    $onlyInPath2 = @($hashes2.Keys | Where-Object { -not $hashes1.ContainsKey($_) })

    $mismatchedFiles = @(
        foreach ($name in $hashes1.Keys) {
            if ($hashes2.ContainsKey($name) -and $hashes1[$name] -ne $hashes2[$name]) {
                [PSCustomObject]@{
                    FileName = $name
                    Hash1    = $hashes1[$name]
                    Hash2    = $hashes2[$name]
                }
            }
        }
    )

    $isIdentical = $countMatch -and
                   $onlyInPath1.Count -eq 0 -and
                   $onlyInPath2.Count -eq 0 -and
                   $mismatchedFiles.Count -eq 0

    [PSCustomObject]@{
        Path1            = $Path1
        Path2            = $Path2
        FileCount1       = $files1.Count
        FileCount2       = $files2.Count
        CountMatch       = $countMatch
        OnlyInPath1      = $onlyInPath1
        OnlyInPath2      = $onlyInPath2
        MismatchedFiles  = $mismatchedFiles
        IsIdentical      = $isIdentical
    }
}

function Compare-SharePointToFileShare {
    param(
        [Parameter(Mandatory)] [string]$SiteUrl,
        [Parameter(Mandatory)] [string]$LibraryName,
        [Parameter(Mandatory)] [string]$FileSharePath,
        [string]$Algorithm = $DefaultHash
    )
    Connect-PnPOnline -Url $SiteUrl -Interactive
    $spFiles = Get-PnPListItem -List $LibraryName -PageSize 500

    foreach ($item in $spFiles) {
        $fileName = $item.FieldValues.FileLeafRef
        $serverRelativeUrl = $item.FieldValues.FileRef
        $localTemp = Join-Path $env:TEMP $fileName

        Get-PnPFile -Url $serverRelativeUrl -Path $env:TEMP -FileName $fileName -AsFile -Force

        $spHash = (Get-FileHash -Path $localTemp -Algorithm $Algorithm).Hash
        $shareHash = (Get-FileHash -Path (Join-Path $FileSharePath $fileName) -Algorithm $Algorithm).Hash

        [PSCustomObject]@{
            FileName    = $fileName
            SPHash      = $spHash
            ShareHash   = $shareHash
            IsIdentical = $spHash -eq $shareHash
        }

        Remove-Item $localTemp -Force
    }
}

Function Get-Robocopyinfo {
    Write-Host "+========================================================="
    Write-Host "RoboCopy Info:"
    (Get-Item "$env:SystemRoot\System32\Robocopy.exe").VersionInfo.FileVersion
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $type = if ($os.ProductType -eq 1) { "Client" } else { "Server" }
    Write-Host "$type - $($os.Caption) (Build $($os.BuildNumber))"
    Write-Host "+========================================================="
}    

Write-StepSummary -Type 'Info' -ShowTimeStamp $false "Ready for copies from Azure Files to SharePoint/NAS"
Write-StepSummary -Type 'Info' -ShowTimeStamp $false "Functions defined: Invoke-RobocopyMirrorforNAS, Compare-DirectoryChecksum, Compare-SharePointToFileShare, Compare-FileChecksum"
Get-Robocopyinfo

$modulesToImport = @('Az', 'PnP.PowerShell', 'ExchangeOnlineManagement', 'Microsoft.Graph.Authentication', 'Microsoft.Graph.User', 'Microsoft.Graph.Group')
foreach ($module in $modulesToImport) {
    if (Get-Module -ListAvailable -Name $module) {
        Write-StepSummary -Type 'start' -ShowTimeStamp $false "Importing PowerShell module ${module}"
        Import-Module -Name $module *> $null
    }
}

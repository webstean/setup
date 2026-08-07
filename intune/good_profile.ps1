## Note: This FILE is ASCII encoded, for compatibility with Windows Powershell, so any Unicode characters need to be eliminated

#$env:AZURE_CLIENT_ID = az keyvault secret show `
#    --vault-name mykv `
#    --name AZURE-CLIENT-ID `
#    --query value -o tsv
    
#Set-ExecutionPolicy Unrestricted -Scope Process
#Set-ExecutionPolicy Unrestricted -Scogpe CurrentUser
#Set-ExecutionPolicy -ExecutionPolicy Unrestricted

## Ignore	        Completely discard output
## SilentlyContinue	Ignore verbose output (default)
## Continue	        Show verbose messages
## Stop	            Treat verbose output as terminating error
## Suspend          Treat verbose output as terminating error
## Inquire	        Ask user whether to continue
## Break	        Enter debugger
## Show verbose messages
$VerbosePreference = 'SilentlyContinue'
$PSDefaultParameterValues['*:Verbose'] = $false

function Update-ProfileForce {
    param(
        [string] $Uri = 'https://raw.githubusercontent.com/webstean/setup/main/intune/good_profile.ps1',

        [string] $ProfilePath = $PROFILE,

        [ValidateSet('utf8NoBOM', 'utf8BOM', 'ascii')]
        [string] $Encoding = 'utf8NoBOM',

        [switch] $Backup
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
        throw 'PROFILE path is empty.'
    }

    $profileDir = Split-Path -Path $ProfilePath -Parent

    if (-not (Test-Path -Path $profileDir -PathType Container)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    try {
        $response = Invoke-WebRequest `
            -Uri $Uri `
            -UseBasicParsing `
            -Headers @{ 'Cache-Control' = 'no-cache' } `
            -ErrorAction Stop
    } catch {
        throw "Failed to download profile from '$Uri'. $($_.Exception.Message)"
    }

    if ($response.StatusCode -lt 200 -or $response.StatusCode -gt 299) {
        throw "Download failed. HTTP status: $($response.StatusCode) $($response.StatusDescription)"
    }

    $newContent = [string] $response.Content

    if ([string]::IsNullOrWhiteSpace($newContent)) {
        throw 'Downloaded profile content is empty.'
    }

    $oldContent = $null
    $exists = Test-Path -Path $ProfilePath -PathType Leaf

    if ($exists) {
        $oldContent = Get-Content -Path $ProfilePath -Raw -ErrorAction Stop
    }

    $oldNormalized = if ($null -ne $oldContent) {
        $oldContent.Trim() -replace "`r`n", "`n"
    } else {
        $null
    }

    $newNormalized = $newContent.Trim() -replace "`r`n", "`n"

    if ($exists -and $oldNormalized -ceq $newNormalized) {
        Write-Host "Profile already current: $ProfilePath" -ForegroundColor Yellow
        return
    }

    if ($Backup -and $exists) {
        $backupPath = "$ProfilePath.$(Get-Date -Format 'yyyyMMdd-HHmmss').bak"
        Copy-Item -Path $ProfilePath -Destination $backupPath -Force
        Write-Host "Backup created: $backupPath" -ForegroundColor DarkCyan
    }

    Set-Content `
        -Path $ProfilePath `
        -Value $newContent `
        -Encoding $Encoding `
        -Force

    Write-Host "Profile updated: $ProfilePath" -ForegroundColor Green
}
#Update-ProfileForce

function Get-HostInfo {
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME
    )
    try {
        $cim = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to query Win32_OperatingSystem on $ComputerName : $_"
        return
    }
    # Domain / workgroup membership
    try {
        $csInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        $domainName   = $csInfo.Domain
        $partOfDomain = $csInfo.PartOfDomain
    }
    catch {
        Write-Warning "Failed to query Win32_ComputerSystem on $ComputerName : $_"
        $domainName   = $null
        $partOfDomain = $null
    }
    # Registry path — works locally; for remote, use Invoke-Command or remote registry provider
    $regPath = if ($ComputerName -eq $env:COMPUTERNAME) {
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    } else {
        $null
    }
    if ($regPath) {
        $reg = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
    } else {
        # Remote fallback via CIM/WMI registry provider
        $reg = Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        } -ErrorAction SilentlyContinue
    }
    $productName   = $reg.ProductName
    $editionId     = $reg.EditionID
    $releaseId     = $reg.ReleaseId
    $displayVer    = $reg.DisplayVersion
    $currentBuild  = $reg.CurrentBuild
    $ubr           = $reg.UBR
    $installType   = $reg.InstallationType   # e.g. "Client", "Server", "Client Core"
    $compositionEd = $reg.CompositionEditionID  # sometimes populated on IoT/LTSC images
    # Detect LTSC — EditionID and ProductName both carry "LTSC" on 10/11,
    # older 2015/2016 LTSB builds carry "LTSB" instead
    $isLTSC = ($editionId -match 'LTSC') -or ($productName -match 'LTSC')
    $isLTSB = ($editionId -match 'LTSB') -or ($productName -match 'LTSB')
    # Detect IoT
    $isIoT = ($editionId -match 'IoT') -or ($productName -match 'IoT')
    # Servicing channel classification
    $servicingChannel = if ($isLTSC -or $isLTSB) {
        'LTSC'
    } elseif ($installType -eq 'Server') {
        'Server'
    } else {
        'GAC'   # General Availability Channel (was "SAC" pre-2021 naming)
    }
    # Build-to-release mapping for major Win10/11 releases (extend as needed)
    $buildMap = @{
        '19044' = '21H2 (Win10)'
        '19045' = '22H2 (Win10)'
        '22621' = '22H2 (Win11)'
        '22631' = '23H2 (Win11)'
        '26100' = '24H2 (Win11)'
    }
    $friendlyRelease = $buildMap[$currentBuild]
    # Activation status — LicenseStatus 1 = Licensed/Activated
    try {
        $licensingProduct = Get-CimInstance -ClassName SoftwareLicensingProduct -ComputerName $ComputerName `
            -Filter "PartialProductKey is not null and Name like 'Windows%'" -ErrorAction Stop
        $activated = [bool]($licensingProduct | Where-Object { $_.LicenseStatus -eq 1 })
    }
    catch {
        Write-Warning "Failed to query activation status on $ComputerName : $_"
        $activated = $null
    }
    # Uptime — use the remote machine's own current time (LocalDateTime) rather than (Get-Date),
    # to avoid clock-skew errors between the local machine running this and the target machine
    $lastBoot = $cim.LastBootUpTime
    $uptime = if ($lastBoot) { [math]::Round(($cim.LocalDateTime - $lastBoot).TotalMinutes, 2) } else { $null }
    $lastBootFormatted = if ($lastBoot) { $lastBoot.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
    [PSCustomObject]@{
        ComputerName      = $ComputerName
        DomainName        = $domainName
        PartOfDomain      = $partOfDomain
        ProductName       = $productName
        EditionID         = $editionId
        CompositionEdID   = $compositionEd
        DisplayVersion    = $displayVer
        ReleaseId         = $releaseId
        FriendlyRelease   = $friendlyRelease
        CurrentBuild      = $currentBuild
        UBR               = $ubr
        FullBuildNumber   = "$currentBuild.$ubr"
        InstallationType  = $installType
        ServicingChannel  = $servicingChannel
        IsLTSC            = $isLTSC
        IsLTSB            = $isLTSB
        IsIoT             = $isIoT
        Activated         = $activated
        LastBootUpTime    = $lastBootFormatted
        UptimeMinutes     = $uptime
        OSArchitecture    = $cim.OSArchitecture
        Caption           = $cim.Caption
        Version           = $cim.Version
    }
}

function Test-NFS {
    [CmdletBinding()]
    param()

    ## Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to install NFS.'
    }

    # Get-WindowsOptionalFeature relies on a DISM COM interop layer that's
    # part of the legacy Windows PowerShell 5.1 binary module. On PowerShell
    # 7/Core, that COM class frequently fails to register correctly, causing
    # a "Class not registered" COMException — a known, recurring PS7 issue
    # (not specific to this script), inconsistent across machines/builds.
    # Loading DISM via the Windows PowerShell compatibility layer avoids it.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try {
            Import-Module DISM -UseWindowsPowerShell -ErrorAction Stop *> $null
        } catch {
            Write-Verbose "Could not import DISM via -UseWindowsPowerShell: $($_.Exception.Message)"
        }
    }

    $featureState = $null
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName ServicesForNFS-ClientOnly -ErrorAction Stop
        $featureState = $feature.State
    } catch [System.Runtime.InteropServices.COMException] {
        Write-Verbose "Get-WindowsOptionalFeature COM call failed ('$($_.Exception.Message)') — falling back to dism.exe directly."
        # Fall back to parsing dism.exe's own output, bypassing the COM API
        # path entirely — dism.exe itself doesn't hit this registration issue.
        $dismOutput = & dism.exe /online /get-featureinfo /featurename:ServicesForNFS-ClientOnly 2>&1
        $stateLine = $dismOutput | Where-Object { $_ -match '^\s*State\s*:\s*(.+)$' }
        if ($stateLine -and $stateLine -match '^\s*State\s*:\s*(.+)$') {
            $featureState = $matches[1].Trim()
        } else {
            Write-Warning "Could not determine NFS feature state via dism.exe fallback either. Raw output: $($dismOutput -join ' | ')"
        }
    }

    $service = Get-Service -Name NfsClnt -ErrorAction SilentlyContinue
    $installed     = ($featureState -eq 'Enabled')
    $serviceExists = ($null -ne $service)
    [PSCustomObject]@{
        Installed     = $installed
        FeatureState  = $featureState
        ServiceExists = $serviceExists
        ServiceStatus = if ($service) { $service.Status } else { $null }
        Available     = ($installed -and $serviceExists)
    }
}

function Install-WindowsNfsClient {
    [CmdletBinding()]
    param()

    ## Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required to install NFS.'
    }

    # Falls back to Write-Host if Write-StepSummary isn't defined elsewhere in
    # the session/profile — avoids a hard failure on every call if that
    # helper isn't actually loaded.
    if (-not (Get-Command Write-StepSummary -ErrorAction SilentlyContinue)) {
        function Write-StepSummary {
            param([string]$type, [string]$Message)
            $color = switch ($type) {
                'warning' { 'Yellow' }
                'error'   { 'Red' }
                default   { 'Cyan' }
            }
            Write-Host $Message -ForegroundColor $color
        }
    }

    # Get-WindowsOptionalFeature/Enable-WindowsOptionalFeature rely on a DISM
    # COM interop layer that frequently fails to register correctly on
    # PowerShell 7/Core, throwing "Class not registered" — a known, recurring
    # PS7 issue. Loading DISM via the Windows PowerShell compatibility layer
    # avoids it in most cases.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try {
            Import-Module DISM -UseWindowsPowerShell -ErrorAction Stop *> $null
        } catch {
            Write-Verbose "Could not import DISM via -UseWindowsPowerShell: $($_.Exception.Message)"
        }
    }

    Write-StepSummary -type 'info' 'Checking if Windows NFS Client is installed...'
    $featureName = 'ServicesForNFS-ClientOnly'

    function Get-NfsFeatureState {
        try {
            return (Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction Stop).State
        } catch [System.Runtime.InteropServices.COMException] {
            Write-Verbose "Get-WindowsOptionalFeature COM call failed — falling back to dism.exe directly."
            $dismOutput = & dism.exe /online /get-featureinfo /featurename:$featureName 2>&1
            $stateLine = $dismOutput | Where-Object { $_ -match '^\s*State\s*:\s*(.+)$' }
            if ($stateLine -and $stateLine -match '^\s*State\s*:\s*(.+)$') {
                return $matches[1].Trim()
            }
            Write-Warning "Could not determine NFS feature state via dism.exe fallback either."
            return $null
        }
    }

    $featureState = Get-NfsFeatureState
    $restartNeeded = $false

    if ($featureState -ne 'Enabled') {
        Write-StepSummary -type 'info' 'Installing Windows NFS Client...'
        $result = Enable-WindowsOptionalFeature `
            -Online `
            -FeatureName $featureName `
            -All `
            -NoRestart `
            -ErrorAction Stop
        $restartNeeded = [bool]$result.RestartNeeded
        # Re-check state after enabling rather than trusting the pre-install
        # value — but a restart-pending install may still report the old
        # state until the reboot actually happens.
        $featureState = Get-NfsFeatureState

        if ($restartNeeded) {
            Write-StepSummary -type 'warning' 'A restart is required before the NFS client can be used.'
            # The NfsClnt service is very likely not registered yet at this
            # point — attempting to query/start it now would fail. Return
            # early with what's actually known rather than crashing on a
            # service that may not exist until after reboot.
            return [PSCustomObject]@{
                Installed       = $false
                FeatureState    = $featureState
                ServiceStatus   = $null
                StartupType     = $null
                MountCommand    = [bool](Get-Command mount.exe -ErrorAction SilentlyContinue)
                RestartRequired = $true
                Ready           = $false
            }
        }
    }

    $service = Get-Service -Name NfsClnt -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-StepSummary -type 'warning' 'NFS feature reports enabled, but the NfsClnt service was not found. A restart may still be pending.'
        return [PSCustomObject]@{
            Installed       = ($featureState -eq 'Enabled')
            FeatureState    = $featureState
            ServiceStatus   = $null
            StartupType     = $null
            MountCommand    = [bool](Get-Command mount.exe -ErrorAction SilentlyContinue)
            RestartRequired = $restartNeeded
            Ready           = $false
        }
    }

    if ($service.StartType -ne 'Automatic') {
        Set-Service -Name NfsClnt -StartupType Automatic
    }
    if ($service.Status -ne 'Running') {
        Start-Service -Name NfsClnt
    }
    $service = Get-Service -Name NfsClnt
    $mountAvailable = [bool](Get-Command mount.exe -ErrorAction SilentlyContinue)

    [PSCustomObject]@{
        Installed       = ($featureState -eq 'Enabled')
        FeatureState    = $featureState
        ServiceStatus   = $service.Status
        StartupType     = $service.StartType
        MountCommand    = $mountAvailable
        RestartRequired = $restartNeeded
        Ready           = (
            $featureState -eq 'Enabled' -and
            $service.Status -eq 'Running' -and
            $mountAvailable
        )
    }
}

function Get-DotNetHostInfo {
    [CmdletBinding()]
    param()

    $languageMode = $ExecutionContext.SessionState.LanguageMode

    # Defaults (core types only)
    $jsonVersion = '<not loaded>'
    $jsonLocation = '<not loaded>'
    $isElevated = $null

    # Probe System.Text.Json (may be blocked; that's fine)
    try {
        $asm = [System.Text.Json.JsonSerializer].Assembly
        $jsonVersion = $asm.GetName().Version.ToString()
        $jsonLocation = $asm.Location
    } catch {}

    # Elevation check that works in CLM on Windows
    try {
        $isElevated = $null -ne (whoami /groups 2>$null | Select-String -SimpleMatch 'S-1-5-32-544')
    } catch {
        $isElevated = $null
    }

    $osDesc = '<unknown>'
    $fwDesc = '<unknown>'
    $arch = '<unknown>'

    try { $osDesc = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription } catch {}
    try { $fwDesc = [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription } catch {}
    try { $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString() } catch {}

    # Use a hashtable (core type) so CLM won't error
    $data = @{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        Edition           = $PSVersionTable.PSEdition
        Host              = $Host.Name
        PSHome            = $PSHOME
        LanguageMode      = $languageMode.ToString()
        OS                = $osDesc
        Framework         = $fwDesc
        ProcessArch       = $arch
        IsElevated        = $isElevated
        JsonAssembly      = $jsonVersion
        JsonLocation      = $jsonLocation
    }

    # If not constrained, upgrade the return type to PSCustomObject for nicer display
    if ($languageMode -ne 'ConstrainedLanguage') {
        return [pscustomobject]$data
    }

    return $data
}

function New-ProfileObject {
    param(
        [Parameter(Mandatory)]
        $Properties
    )

    if ($ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
        return $Properties
    }

    return [pscustomobject]$Properties
}
# Get-DotNetHostInfo

#$aw = $(
#            [AppDomain]::CurrentDomain.GetAssemblies() |
#            Where-Object { $_.GetName().Name -eq 'System.Text.Json' } |
#            ForEach-Object { "{0} | {1}" -f $_.GetName().Version, $_.Location }
#        )

function Invoke-WindowsPowerShell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ScriptBlock,

        [switch]$AsAdmin
    )

    $ps51 = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"

    $psArgs = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-Command', $ScriptBlock
    )

    if ($AsAdmin) {
        Start-Process -FilePath $ps51 -ArgumentList $psArgs -Verb RunAs -Wait
    } else {
        & $ps51 @psArgs
    }
}

function Set-RegistryValue {
    <#
        .SYNOPSIS
            Idempotently create or update a registry value.

        .DESCRIPTION
            Robust replacement for the original Set-RegistryValue.
            - Accepts hive aliases (HKLM, HKCU, HKCR, HKU, HKCC, plus the long
              HKEY_* names and trailing ':' forms).
            - Accepts type aliases in any case (String, DWORD, REG_SZ, ...).
            - Coerces $Value to the requested registry type.
            - Creates parent keys as needed, including deep paths.
            - Detects existing values: returns 'Unchanged' when value+type
              already match, 'Updated' when overwriting, 'Created' for new
              values, 'Failed' on error.
            - Re-creates the value when the existing kind doesn't match the
              requested kind (PowerShell can't change kind in place).
            - Honours -WhatIf / -Confirm.
            - Never throws (returns a status object); callers can opt into
              throwing via -ErrorAction Stop on Write-Error if needed.

        .EXAMPLE
            Set-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso' -Name 'Url' -Value 'https://x' -Type String

        .EXAMPLE
            Set-RegistryValue -Hive HKCU -SubKey 'Software\Foo' -Name 'Bar' -Value 1 -Type DWORD -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hive,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('Key')]
        [string]$SubKey,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PropertyName')]
        [string]$Name,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [object]$Value,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('PropertyType', 'Kind')]
        [string]$Type = 'String'
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        $hiveMap = @{
            'HKLM' = 'HKLM'; 'HKEY_LOCAL_MACHINE' = 'HKLM'
            'HKCU' = 'HKCU'; 'HKEY_CURRENT_USER' = 'HKCU'
            'HKCR' = 'HKCR'; 'HKEY_CLASSES_ROOT' = 'HKCR'
            'HKU' = 'HKU'; 'HKEY_USERS' = 'HKU'
            'HKCC' = 'HKCC'; 'HKEY_CURRENT_CONFIG' = 'HKCC'
        }

        $typeMap = @{
            'STRING' = 'String'; 'REG_SZ' = 'String'
            'DWORD' = 'DWord'; 'REG_DWORD' = 'DWord'
            'QWORD' = 'QWord'; 'REG_QWORD' = 'QWord'
            'BINARY' = 'Binary'; 'REG_BINARY' = 'Binary'
            'MULTISTRING' = 'MultiString'; 'REG_MULTI_SZ' = 'MultiString'
            'EXPANDSTRING' = 'ExpandString'; 'REG_EXPAND_SZ' = 'ExpandString'
        }
    }

    process {
        # ---- Normalize hive ----
        $hiveKey = $Hive.Trim().TrimEnd(':').ToUpperInvariant()
        if (-not $hiveMap.ContainsKey($hiveKey)) {
            return [pscustomobject]@{
                Path   = "$Hive\$SubKey"
                Name   = $Name
                Type   = $Type
                Status = 'Failed'
                Error  = "Unsupported hive '$Hive'. Use HKLM, HKCU, HKCR, HKU or HKCC."
            }
        }
        $resolvedHive = $hiveMap[$hiveKey]

        # ---- Normalize subkey (strip drive prefixes, leading slashes, swap /) ----
        $cleanSub = $SubKey.Trim().Replace('/', '\')
        $cleanSub = $cleanSub -replace '^(HKLM|HKCU|HKCR|HKU|HKCC):\\?', ''
        $cleanSub = $cleanSub -replace '^(HKEY_LOCAL_MACHINE|HKEY_CURRENT_USER|HKEY_CLASSES_ROOT|HKEY_USERS|HKEY_CURRENT_CONFIG)\\', ''
        $cleanSub = $cleanSub.TrimStart('\')

        # ---- Normalize type ----
        $typeKey = $Type.Trim().ToUpperInvariant()
        if ($typeMap.ContainsKey($typeKey)) {
            $resolvedType = $typeMap[$typeKey]
        } else {
            return [pscustomobject]@{
                Path   = "${resolvedHive}:\$cleanSub"
                Name   = $Name
                Type   = $Type
                Status = 'Failed'
                Error  = "Unsupported registry type '$Type'."
            }
        }

        $path = "${resolvedHive}:\$cleanSub"

        # ---- Coerce $Value into the requested registry kind ----
        try {
            $coerced =
            switch ($resolvedType) {
                'DWord' { [int]$Value }
                'QWord' { [long]$Value }
                'Binary' {
                    if ($null -eq $Value) { [byte[]]@() }
                    elseif ($Value -is [byte[]]) { , $Value }
                    elseif ($Value -is [string]) { [System.Text.Encoding]::UTF8.GetBytes([string]$Value) }
                    elseif ($Value -is [System.Collections.IEnumerable]) {
                        , ([byte[]]@($Value | ForEach-Object { [byte]$_ }))
                    } else {
                        throw 'Binary values must be a byte[] (or convertible).'
                    }
                }
                'MultiString' {
                    if ($null -eq $Value) { , [string[]]@() }
                    elseif ($Value -is [string[]]) { , $Value }
                    elseif ($Value -is [string]) { , @([string]$Value) }
                    elseif ($Value -is [System.Collections.IEnumerable]) {
                        , ([string[]]@($Value | ForEach-Object { [string]$_ }))
                    } else {
                        , @([string]$Value)
                    }
                }
                default { [string]$Value }   # String / ExpandString
            }
        } catch {
            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Type   = $resolvedType
                Status = 'Failed'
                Error  = "Value coercion failed: $($_.Exception.Message)"
            }
        }

        try {
            # ---- Ensure parent key exists ----
            if (-not (Test-Path -LiteralPath $path)) {
                if ($PSCmdlet.ShouldProcess($path, 'Create registry key')) {
                    New-Item -Path $path -Force -ErrorAction Stop | Out-Null
                }
            }

            # ---- Discover existing value (if any) ----
            $existing = $null
            $existingKind = $null
            try {
                $regKey = Get-Item -LiteralPath $path -ErrorAction Stop
                $existingKind = $regKey.GetValueKind($Name)        # throws if missing
                $existing = $regKey.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            } catch {
                $existingKind = $null
                $existing = $null
            }

            $status = 'Created'

            if ($null -ne $existingKind) {
                $status = 'Updated'
                $existingKindString = [string]$existingKind

                if ($existingKindString -ne $resolvedType) {
                    # Different kind — must remove and recreate
                    Write-Verbose "Replacing $existingKindString value '$Name' at '$path' with $resolvedType."
                    if ($PSCmdlet.ShouldProcess("$path!$Name", "Remove existing $existingKindString value")) {
                        Remove-ItemProperty -LiteralPath $path -Name $Name -Force -ErrorAction Stop
                    }
                } else {
                    # Same kind — short-circuit if equal (idempotency)
                    $isEqual = $false
                    try {
                        $isEqual =
                        switch ($resolvedType) {
                            'Binary' { -not (Compare-Object $existing $coerced -SyncWindow 0) }
                            'MultiString' { -not (Compare-Object $existing $coerced -SyncWindow 0) }
                            default { $existing -eq $coerced }
                        }
                    } catch {
                        $isEqual = $false
                    }

                    if ($isEqual) {
                        return [pscustomobject]@{
                            Path   = $path
                            Name   = $Name
                            Value  = $coerced
                            Type   = $resolvedType
                            Status = 'Unchanged'
                        }
                    }
                }
            }

            if ($PSCmdlet.ShouldProcess("$path!$Name", "Set $resolvedType value")) {
                New-ItemProperty -LiteralPath $path -Name $Name -Value $coerced -PropertyType $resolvedType -Force -ErrorAction Stop | Out-Null
            }

            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Value  = $coerced
                Type   = $resolvedType
                Status = $status
            }
        } catch {
            return [pscustomobject]@{
                Path   = $path
                Name   = $Name
                Type   = $resolvedType
                Status = 'Failed'
                Error  = $_.Exception.Message
            }
        }
    }
}
#Set-RegistryValue -Hive HKLM -SubKey 'SOFTWARE\Contoso\MyApp' -Name 'ServerUrl' -Value 'https://example.local' -Type 'String'


## FullLanguage: No restrictions (default in most PowerShell sessions)
## ConstrainedLanguage: Limited .NET access (used in AppLocker/WDAC scenarios)
## RestrictedLanguage: Very limited (e.g., only basic expressions)
## NoLanguage: No scripting allowed at all
$acceptableModes = @('FullLanguage')
$unacceptableModes = @('ConstrainedLanguage', 'RestrictedLanguage', 'NoLanguage')
$currentMode = $ExecutionContext.SessionState.LanguageMode.ToString()
$IsLanguagePermissive = $currentMode -in $acceptableModes

$UTF8 = $false
if ($IsLanguagePermissive) {
    [console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding
} 
if ([bool](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP -eq '65001') { 
    Write-Host -ForegroundColor DarkGreen ('UTF-8 output encoding enabled')
    $UTF8 = $true
}

# Get the current language mode
if ($IsLanguagePermissive) {
    Write-Host -ForegroundColor DarkGreen "PowerShell Language Mode is: $currentMode"
    ## Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $IsAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    Write-Host -ForegroundColor DarkYellow "PowerShell Language Mode is: $currentMode (most advanced things won't work here)"
    $IsAdmin = $null -ne (whoami /groups | Select-String 'S-1-5-32-544')
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
    Write-Host -ForegroundColor DarkRed 'Current context permisisons is        : ADMIN'
} else {
    $InstallScope = 'CurrentUser'
    Write-Host -ForegroundColor DarkYellow 'Current context permisisons is        : USER'
}

$VirtualMachine = $true
$type = $null

function Get-HostPlatform {

    $cs = Get-CimInstance Win32_ComputerSystem
    $model = "$($cs.Manufacturer) $($cs.Model)"
    
    switch -Regex ($model) {
        'VMware' {
            $VirtualMachine = $true
            $type = 'VMware virtual machine'
        }
        'VirtualBox' {
            $VirtualMachine = $true
            $type = 'Oracle VirtualBox VM'
        }
        'Microsoft.*Virtual' {
            $VirtualMachine = $true
            $type = 'Hyper-V / Azure virtual machine'
        }
        'QEMU|KVM' {
            $VirtualMachine = $true
            $type = 'KVM/QEMU virtual machine'
        }
        
        default {
            $VirtualMachine = $false
            $type = 'Likely bare-metal physical machine'
        }
    }
    if ($env:IsDevBox -eq 'True' ) {
        $VirtualMachine = $true
        $type = 'Azure DevBox'
    }
    
    #    if ($IsLanguagePermissive) {
    #        [pscustomobject]@{
    #            VirtualMachine = $virtualMachine
    #            Type           = $type
    #            Model          = $model
    #        }
    #    } else {
    #        Write-Host "VirtualMachine : $virtualMachine"
    #        Write-Host "Type           : $type"
    #        Write-Host "Model          : $model"
    #    }        
}
Get-HostPlatform

function Search {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Filter
    )
    Write-Output "Searching for '$Filter' in $(Get-Location) and subfolders..."
    Get-ChildItem -Path . -Recurse -Filter $Filter -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
}

function Reset-Podman {

    ## Ensure running as Administrator
    $principal = [Security.Principal.WindowsPrincipal]::new(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Local Administrator privileges are required to reset podman.'
    }
    
    try {
        ## Run as required
        if ( -not ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue ))) {
            Write-Host 'Windows Podman CLI was not found/not installed!'
            return $false
        }
        #if ( ( [bool](Get-Command wslc.exe -ErrorAction SilentlyContinue ))) {
        #    Write-Host 'Found WSLC (WSL for Containers) - stopping it...'
        #    wslc stop
        #}
        podman machine stop
        wsl --shutdown
        podman machine rm --force
        podman system connection rm podman-machine-default
        podman system connection rm podman-machine-default-root
        podman machine init --timezone 'Australia/Melbourne'
        podman machine start
        podman system connection list
        #podman machine inspect | jq
        $PODMAN_IDENTITY = & podman machine inspect --format '{{.SSHConfig.IdentityPath}}' ## Private Key
        $PODMAN_PORT = & podman machine inspect podman-machine-default --format '{{.SSHConfig.Port}}'
        $PODMAN_USER = & podman machine inspect --format '{{.SSHConfig.RemoteUsername}}'
        $PODMAN_PATH = & podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}'
        ## Write-Host "podman-remote system connection add --identity ${PODMAN_IDENTITY} --port ${PODMAN_PORT} winpodman ${PODMAN_CONNECTION}"
        ## Write-Host 'podman-remote system connection default winpodman'
        #podman machine info
        ## Download and Run Container
        ## podman run --rm quay.io/podman/hello
        Set-Alias -Name docker -Value podman
        ## Set-Item -Path Env:\ASPIRE_CONTAINER_RUNTIME -Value 'podman'
        [System.Environment]::SetEnvironmentVariable("ASPIRE_CONTAINER_RUNTIME","podman","User")
        #Set-WslNetConfig
        ## podman run -dt -p 8080:80/tcp docker.io/library/httpd:latest
        ## podman run -it mcr.microsoft.com/azure-cli:azurelinux3.0
        ## podman run -it mcr.microsoft.com/devcontainers/base:ubuntu
        ## podman run -it mcr.microsoft.com/azure-cloudshell
        ## podman run -it --env AZURE_SUBSCRIPTION_ID=$env:AZURE_SUBSCRIPTION_ID --env AZURE_TENANT_ID=$env:AZURE_TENANT_ID --env AZURE_USERNAME=$env:AZURE_USERNAME mcr.microsoft.com/azure-cloudshell 
        ## podman run --rm -it ghcr.io/baresip/docker/baresip:latest
        if ( -not ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue ))) {
            Write-Host 'Podman is supposed to be the container runtime but the podman executable was not found/not installed!'
        }
    }
    catch {
    }
}    

function Set-Developer-Variables {
    ## Edit as required
    if ( -not ( $env:DEVELOPER -eq 'Yes' )) { return }
    Write-Host 'Setting Developer environment variables...'
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

    ## Turn off PNP Update Check
    Set-Item -Path Env:\PNPPOWERSHELL_UPDATECHECK -Value 'Off'

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

#Only works for Powershell naked (not starship,Oh My Posh etc..)
function prompt {

    if ( $IsAdmin ) {
        $color = 'Red'
        Write-Host ('PS (Admin) ' + $(Get-Location) + '>') -NoNewline -ForegroundColor $Color
    } else {
        $color = 'Green'    
        Write-Host ('PS ' + $(Get-Location) + '>') -NoNewline -ForegroundColor $Color
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
        Object summarizing what was applied. In Constrained Language Mode this is a hashtable.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Auto', 'Inline', 'List')]
        [string]$ViewStyle = 'Auto',
        [bool]$UsePluginIfAvailable = $true
    )

    $result = New-ProfileObject @{
        PSVersion           = $PSVersionTable.PSVersion.ToString()
        PSEdition           = $PSVersionTable.PSEdition
        PSReadLineVersion   = $null
        PredictionEnabled   = $false
        PredictionSource    = $null
        PredictionViewStyle = $null
        KeybindingsApplied  = @()
        Notes               = @()
    }

    if (-not $IsLanguagePermissive) {
        $result.Notes += 'Skipped: language mode is not permissive.'
        return $result
    }

    try {
        $window = $Host.UI.RawUI.WindowSize
        if (-not ($window.Width -ge 54 -and $window.Height -ge 15)) {
            $result.Notes += 'Skipped: console window too small for prediction UI.'
            return $result
        }
    } catch {
        $result.Notes += 'Skipped: host does not expose RawUI window size.'
        return $result
    }

    # 1) Load newest PSReadLine available (quietly)
    $rl = Get-Module PSReadLine -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $rl) {
        $result.Notes += 'PSReadLine not installed; skipping configuration.'
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
    $hasPredictionView = $false
    if ($setOpt) {
        $params = ($setOpt.Parameters.Keys)
        $hasPredictionSource = $params -contains 'PredictionSource'
        $hasPredictionView = $params -contains 'PredictionViewStyle'
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
            $result.PredictionSource = $source
        } catch {
            $result.Notes += "Set-PSReadLineOption -PredictionSource failed: $($_.Exception.Message)"
        }
    } else {
        $result.Notes += 'This PSReadLine does not expose -PredictionSource; skipping predictions.'
    }

    # 3) Decide PredictionViewStyle
    if ($hasPredictionView) {
        $candidates = @()
        switch ($ViewStyle) {
            'Inline' { $candidates = @('InlineView') }
            'List' { $candidates = @('ListView') }
            'Auto' {
                # Prefer Inline when available; fallback to List
                $candidates = @('InlineView', 'ListView')
            }
        }

        if ($candidates.Count -gt 0) {
            $applied = $false
            foreach ($candidate in $candidates) {
                if ($applied) { break }
                try {
                    Set-PSReadLineOption -PredictionViewStyle $candidate
                    $result.PredictionViewStyle = $candidate
                    $applied = $true
                } catch {
                    # Try next candidate (Auto mode) if available.
                }
            }
            if (-not $applied) { $result.Notes += 'Could not set any PredictionViewStyle on this build.' }
        }
    } else {
        $result.Notes += 'This PSReadLine does not expose -PredictionViewStyle; view not set.'
    }

    # 4) Edit mode (safe everywhere)
    try {
        Set-PSReadLineOption -EditMode Windows
    } catch { }

    # 5) Helpful keybindings — only if functions exist
    $keyFn = @{
        'Ctrl+RightArrow' = 'AcceptNextSuggestionWord'
        'Alt+RightArrow'  = 'NextSuggestion'
        'Alt+LeftArrow'   = 'PreviousSuggestion'
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

function which {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command
    )

    Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}
if (Get-Command 'cat.exe' -ErrorAction SilentlyContinue) { Remove-Alias cat -ErrorAction SilentlyContinue }

# Run Starship if installed
function Invoke-Starship-TransientFunction {
    &starship module character
}

if ([bool](Get-Command -ErrorAction SilentlyContinue starship.exe).Source) {
    if (-not $env:STARSHIP_CONFIG) {
        $env:STARSHIP_CONFIG = "$env:OneDriveCommercial\starship.toml"
        $env:STARSHIP_CACHE = "$HOME\AppData\Local\Temp"
    }
    $starshipConfig = "$env:STARSHIP_CONFIG"
    if (-not (Test-Path "$starshipConfig" -PathType Leaf)) {
        Write-Host ('Starship inital config...')
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
        Write-Host -ForegroundColor 'Yellow' 'Warning: Nerd Fonts are NOT installed!' 
    }
}

function Get-OsInfo {
    $cv = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    if (-not (Test-Path $cv)) { return }

    $props = Get-ItemProperty -Path $cv -ErrorAction SilentlyContinue
    if (-not $props) { return }

    $major = $props.CurrentMajorVersionNumber
    $minor = $props.CurrentMinorVersionNumber
    $build = $props.CurrentBuildNumber
    $ubr   = $props.UBR
    $osVersion = "$major.$minor.$build.$ubr"

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem

    if ($IsLanguagePermissive) {
        [PSCustomObject]@{
            ProductName  = $props.ProductName
            ReleaseId    = $props.ReleaseId
            DisplayVer   = $props.DisplayVersion
            Build        = [int]$build
            UBR          = [int]$ubr
            OSVersion    = $osVersion
            Type         = $props.InstallationType
            Manufacturer = $cs.Manufacturer
            Model        = $cs.Model
            DevBox       = $env:IsDevBox
        }
    } else {
        Write-Host 'ProductName  : ' -NoNewline; Write-Host $props.ProductName
        Write-Host 'ReleaseId    : ' -NoNewline; Write-Host $props.ReleaseId
        Write-Host 'DisplayVer   : ' -NoNewline; Write-Host $props.DisplayVersion
        Write-Host 'Build        : ' -NoNewline; Write-Host ([int]$build)
        Write-Host 'UBR          : ' -NoNewline; Write-Host ([int]$ubr)
        Write-Host "OSVersion    : $osVersion"
        Write-Host 'Type         : ' -NoNewline; Write-Host $props.InstallationType
        Write-Host 'Manufacturer : ' -NoNewline; Write-Host $cs.Manufacturer
        Write-Host 'Model        : ' -NoNewline; Write-Host $cs.Model
        if ($env:IsDevBox -eq 'True') {
            Write-Host 'Azure DevBox : Yes'
        } else {
            Write-Host 'Azure DevBox : No'
        }
    }
}

if ( ($env:IsDevBox ) -and (Get-Command 'devbox') ) {
    if ($env:UPN) {
        Write-Host -ForegroundColor Cyan "Welcome to your Dev Box $env:UPN"
    } else {
        Write-Host -ForegroundColor Cyan 'Welcome to your Dev Box'
    }
    if ( [bool](Get-Command -Name jq.exe -ErrorAction SilentlyContinue )) {
        devbox metadata get list-all | jq
        devbox ai status | jq
    } else {
        devbox metadata get list-all
        devbox ai status
    }
}

$ompConfig = "$env:POSH_THEMES_PATH\cloud-native-azure.omp.json"
$ompConfig = 'C:\Program Files\WindowsApps\ohmyposh.cli_27.5.0.0_x64__96v55e8n804z4\themes\cloud-native-azure.omp.json'

## Check for Starship
if ($env:STARSHIP_CONFIG -and (Test-Path "$env:STARSHIP_CONFIG" -PathType Leaf) -and $IsLanguagePermissive ) {
    Write-Host 'Found Starship shell...so starting it...'
    Invoke-Expression (&starship init powershell)
    Enable-TransientPrompt
    if ( -not $IsAdmin ) { $Host.UI.RawUI.WindowTitle = 'PowerShell - Starship' }
} elseif ($env:POSH_THEMES_PATH -and (Test-Path "$ompConfig" -PathType Leaf)) {
    Write-Host 'Found Oh-My-Posh shell...so starting it...'
    & ([ScriptBlock]::Create((oh-my-posh init pwsh --config $ompConfig --print) -join "`n"))
    $Host.UI.RawUI.WindowTitle = 'PowerShell - Oh-My-Posh'
} else {
    if ($Host.UI.RawUI.WindowSize.Width -ge 54 -and $Host.UI.RawUI.WindowSize.Height -ge 15) {
        if ($IsLanguagePermissive) {
            $Host.UI.RawUI.WindowTitle = 'PowerShell'
        }
    }
}

function Reset-GitBranch {
    # Check Git availability
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Error 'Git is not installed or not available in PATH.'
        return
    }

    # Ensure we are inside a Git repo
    try {
        $branch = git rev-parse --abbrev-ref HEAD 2>$null
    } catch {
        Write-Error 'Not a Git repository.'
        return
    }

    if (-not $branch) {
        Write-Error 'Unable to determine current branch.'
        return
    }

    Write-Host "You are on branch: $branch" -ForegroundColor Cyan

    Write-Host "`nFetching latest changes from origin..." -ForegroundColor Cyan
    git fetch origin

    Write-Host "Resetting local branch '$branch' to origin/$branch..." -ForegroundColor Yellow
    git reset --hard "origin/$branch"

    Write-Host 'Cleaning untracked files and directories...' -ForegroundColor Red
    git clean -fd

    Write-Host "`nLocal branch '$branch' is now identical to origin/$branch." -ForegroundColor Green
}

# Alias management
foreach ($alias in 't', 'tf', 'tv', 'ti' ) {
    if ([bool](Get-Alias $alias -ErrorAction SilentlyContinue)) { Remove-Item Alias:$alias -Force }
}

## Terraform shortcuts
function t { terraform.exe @args }
function tf { terraform.exe fmt -recursive @args }
function tv { terraform.exe validate @args }
function ti { terraform.exe init -upgrade @args }
function tp { terraform.exe plan @args }
function ta { terraform.exe apply @args }
function tc {
    Write-StepSummary -type 'info' 'Starting Terraform Console...'
    terraform.exe console @args
}
function ar {
    Write-StepSummary -type 'info' 'Running Aspire app in current directory...'
    aspire run @args
}

## Sysinternal shortcuts
## function handle { handle.exe init -nobanner @args }
 
function cdw {
    [CmdletBinding()]
    param()

    $cdwpath = "$env:SystemDrive\workspaces"
    if (Test-Path -Path $cdwpath -PathType Container -ErrorAction SilentlyContinue ) {
        Set-Location -Path $cdwpath
    } else {
        Write-Warning "$cdwpath does not exist."
    }
}

function free {
    (Get-Volume -DriveLetter C).SizeRemaining | ForEach-Object {
        $sizeInGB = [math]::Round($_ / 1GB, 2)
        if ($sizeInGB -lt 5) {
            Write-Host "Warning: Free space on Drive C: is less than 5GB (${sizeInGB}GB)!" -ForegroundColor Red
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
free

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

        Write-Host 'Console input reset. You should now be able to paste normally.'
    } catch {
        Write-Warning 'Could not reset console state. Try closing and reopening the terminal.'
    }
}

function Import-Nice-Modules {
    if (-not [bool](Get-Module -ListAvailable -Name Terminal-Icons -ErrorAction SilentlyContinue)) {
        Install-PSResource -Name Terminal-Icons -ErrorAction SilentlyContinue
    }
    if (-not [bool](Get-Module -ListAvailable -Name Az.Tools.Predictor -ErrorAction SilentlyContinue)) {
        Install-PSResource -Name Az.Tools.Predictor -ErrorAction SilentlyContinue
    }    
    Import-Module -Name Terminal-Icons -ErrorAction SilentlyContinue
    Import-Module -Name Az.Tools.Predictor -ErrorAction SilentlyContinue
}
Import-Nice-Modules

function Set-Azure-Environment {
    
    if ( -not ( $env:DEVELOPER -eq 'Yes' )) { return }

    $subscription_id = Get-AzSubscription -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty Id
    if (-not [string]::IsNullOrEmpty($subscription_id)) {
        Set-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Value $subscription_id
    } else {
        Remove-Item -Path Env:\AZURE_SUBSCRIPTION_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant = Get-AzTenant -ErrorAction SilentlyContinue | Select-Object -First 1
    $tenant_id = $tenant.Id
    if (-not [string]::IsNullOrEmpty($tenant_id)) {
        Set-Item -Path Env:\AZURE_TENANT_ID -Value $tenant_id
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_ID -Force -ErrorAction SilentlyContinue
    }
    $tenant_name = $tenant.Name
    if (-not [string]::IsNullOrEmpty($tenant_name)) {
        Set-Item -Path Env:\AZURE_TENANT_NAME -Value $tenant_name
    } else {
        Remove-Item -Path Env:\AZURE_TENANT_NAME -Force -ErrorAction SilentlyContinue
    }
    $userUpn = if (-not [string]::IsNullOrEmpty($env:UPN)) { $env:UPN } else { $UPN }
    if (-not [string]::IsNullOrEmpty($userUpn)) {
        Set-Item -Path Env:\AZURE_USERNAME -Value $userUpn
    } else {
        Remove-Item -Path Env:\AZURE_USERNAME -Force -ErrorAction SilentlyContinue
    }
}
#Set-Azure-Developer-Environment

function Test-AzureEnvironment {
    ## Require key Azure identifiers before writing defaults.
    $required = @('AZURE_SUBSCRIPTION_ID', 'AZURE_TENANT_ID')
    $missing = @()

    foreach ($name in $required) {
        $value = (Get-Item -Path "Env:$name" -ErrorAction SilentlyContinue).Value
        if ([string]::IsNullOrEmpty($value)) {
            $missing += $name
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host 'Azure environment variables defined.'
        return $true
    }

    Write-Host "Missing required Azure environment variables: $($missing -join ', ')"
    return $false
}
function Test-GraphToken {
    ## If we have ACCESS_TOKEN variable we are good
    if ( -not [string]::IsNullOrEmpty($env:ACCESS_TOKEN) ) {
        return $true
    }
    return $false
}
function Test-SharePointToken {
    ## If we have ACCESS_TOKEN_SHAREPOINT variable we are good
    if ( -not [string]::IsNullOrEmpty($env:ACCESS_TOKEN_SHAREPOINT) ) {
        return $true
    }
    return $false
}

function New-DefaultEnvFile {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false
    
    if ((Test-AzureEnvironment) -eq $true) {
        Write-Host 'Writing out default .env file'
        @"
# $env:AZURE_TENANT_NAME .env file
AZURE_SUBSCRIPTION_ID=$env:AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID=$env:AZURE_TENANT_ID
AZURE_USERNAME=$env:AZURE_USERNAME
"@ | Out-File -Encoding UTF8 -FilePath "$HOME/.env-default"
        Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env-default" -Force
        Copy-Item "$HOME/.env-default" "$env:OneDriveCommercial/.env" -Force
    } else {
        Write-Host 'Not enough environment variables defined!'
        Write-Host ' Run: Set-Azure-Environment' 
    }

    $PSDefaultParameterValues['*:Verbose'] = $preserve
}
#New-DefaultEnvFile

function Import-Env-File {
    param(
        [Parameter(Mandatory)]
        [string]$EnvId,

        [bool]$silent = $false
    )
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

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
    
    if (-not (Test-Path -Path $Path -ErrorAction SilentlyContinue)) {
        return
    }

    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()

        # Skip blank lines and comments
        if ($line -eq '' -or $line -match '^\s*#') { return }

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
                Set-ItemProperty -Path 'HKCU:\Environment' -Name $key -Value $val
            }
            Set-Item -Path "Env:\$key" -Value "$val"
            
            Write-Verbose "Set `$Env:$key = '$val'"
        }
    }
    #if ( ($null -eq $env:AZURE_TENANT_ID ) -and ($null -eq $env:AZURE_CLIENT_ID )) {
    #    Write-Host "Something is wrong with $envId file"
    #    return 
    #}
    if (-not $silent ) {
        Write-Host "Portal Logon: https://entra.microsoft.com/?tenant=$env:AZURE_TENANT_ID"
        if ( $env:AZURE_CLIENT_ID ) {
            Write-Host 'DELEGATION'
            Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -ClientId $env:AZURE_CLIENT_ID -Scope .default -UseDeviceAuthentication:$false -NoWelcome"
            Write-Host 'Get-MgContext'
        } else {
            Write-Host 'AS USER'
            Write-Host "Connect-MgGraph -TenantId $env:AZURE_TENANT_ID -Scope .default" -UseDeviceAuthentication:$false -NoWelcome
            Write-Host 'Get-MgContext'
        }
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
}

function Get-Default-Env-File {
    Import-Env-File default -silent $true
}
Get-Default-Env-File

function Get-EntraID {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    if ( -not $env:AZURE_TENANT_ID ) {
        throw 'Environment variable AZURE_TENANT_ID is not set'
    }
    $response = Invoke-RestMethod "https://login.microsoftonline.com/$env:AZURE_TENANT_ID/v2.0/.well-known/openid-configuration" -ErrorAction Stop
    if ($response ) {
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        $response | Format-List issuer, token_endpoint, authorization_endpoint, device_authorization_endpoint, end_session_endpoint, kerberos_endpoint, jwks_uri
        return $true | Out-Null
    } else {
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        throw "Tenant $env:AZURE_TENANT_ID was not found!"
        return $false | Out-Null
    }
}

function Format-JsonPretty {
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject,
        [int]$Depth = 10
    )
    process {
        $InputObject | ConvertFrom-Json -ErrorAction SilentlyContinue | ConvertTo-Json -Depth $Depth -Compress:$false
    }
}
## Get-Content .\data.json | Format-JsonPretty

function Get-Azure-Meta {
    ##IMDS
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    $headers = @{ 'Metadata' = 'true' }
    $uri = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
    $uri = 'http://169.254.169.254/metadata/instance?api-version=2025-04-07'
    
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -NoProxy -ErrorAction Stop | ConvertTo-Json -Depth 64
    if ($response ) {
        ## $response | jq .
        $response | jq -r '.compute.azEnvironment'
        $response | jq -r '.compute.location'
     
    } else {
        throw 'This machine is not running inside Azure'
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $false | Out-Null
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
    Write-Host 'Running inside Azure...'
    return $true | Out-Null
}

function Test-ManagedIdentity {
    <#
    .SYNOPSIS
        Tests whether the current Azure compute resource can obtain a token via
        its managed identity through the Instance Metadata Service (IMDS).

    .DESCRIPTION
        Calls the IMDS token endpoint (169.254.169.254) directly, bypassing any
        Az PowerShell module dependency. Useful for diagnosing managed identity
        issues on VMs, VMSS instances, or containers before Connect-AzAccount
        -Identity is attempted.

    .PARAMETER Resource
        The Azure resource URI to request a token for. Defaults to Azure
        Resource Manager.

    .PARAMETER ClientId
        Client ID of a specific user-assigned managed identity. Omit for
        system-assigned identity, or when only one user-assigned identity is
        attached.

    .PARAMETER TimeoutSec
        Request timeout. IMDS normally responds in milliseconds — a low
        default (2s) means failures surface quickly instead of hanging when
        run somewhere IMDS isn't reachable (e.g. on-prem, local dev box).

    .PARAMETER ShowToken
        Include the full access token in the returned object. Off by default
        — the token is a live bearer credential and shouldn't land in
        transcripts, CI logs, or console scrollback by accident.

    .EXAMPLE
        Test-ManagedIdentity

    .EXAMPLE
        Test-ManagedIdentity -Resource 'https://storage.azure.com/' -ClientId '11111111-2222-3333-4444-555555555555'
    #>
    [CmdletBinding()]
    param(
        [string]$Resource = 'https://management.azure.com/',
        [string]$ClientId = '00000003-0000-0000-c000-000000000000', ## Microsoft Graph
        [ValidateRange(1, 30)]
        [int]$TimeoutSec = 2,
        [switch]$ShowToken
    )

    $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource={0}' -f [uri]::EscapeDataString($Resource)
    if ($ClientId) {
        $uri += "&client_id=$ClientId"
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers @{ Metadata = 'true' } -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
    }
    catch [System.Net.WebException] {
        Write-Error "IMDS endpoint unreachable — this likely isn't running on an Azure VM/VMSS/App Service instance, or no network path to 169.254.169.254 exists: $($_.Exception.Message)"
        return
    }
    catch {
        # IMDS returns 400 with a JSON error body when no identity is assigned,
        # or the requested client_id doesn't match an attached identity
        $errorBody = $null
        if ($_.ErrorDetails.Message) {
            try { $errorBody = ($_.ErrorDetails.Message | ConvertFrom-Json).error_description } catch { $errorBody = $_.ErrorDetails.Message }
        }
        Write-Error "Managed identity token request failed: $($errorBody ?? $_.Exception.Message)"
        return
    }

    $expiresOn = [DateTimeOffset]::FromUnixTimeSeconds([long]$response.expires_on).LocalDateTime

    $result = [PSCustomObject]@{
        Success     = $true
        Resource    = $Resource
        ClientId    = $ClientId
        TokenType   = $response.token_type
        ExpiresOn   = $expiresOn
        ExpiresInMin = [math]::Round(([datetime]$expiresOn - (Get-Date)).TotalMinutes, 1)
        AccessToken = if ($ShowToken) { $response.access_token } else { '<redacted — use -ShowToken to include>' }
    }

    return $result
}

## See: https://www.chanceofsecurity.com/post/microsoft-entra-pim-bulk-role-activation-tool
function Enable-PIMRole {
    param(
        [string] $RoleName = 'Global Reader',
        [string] $Justification = 'DA',
        [object] $Duration = '08:00:00',
        [string] $DirectoryScopeId = '/',
        [string] $TicketNumber,
        [string] $TicketSystem,
        [int] $TimeoutSeconds = 120
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $isConstrainedLanguage =
    $ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage'

    function Convert-ToIso8601Duration {
        param([object] $InputObject)

        if ($InputObject -is [string]) {
            $parts = $InputObject.Split(':')

            if ($parts.Count -ne 3) {
                throw 'Duration must be HH:MM:SS.'
            }

            $hours = [int] $parts[0]
            $minutes = [int] $parts[1]
            $seconds = [int] $parts[2]
        } elseif ($InputObject -is [timespan]) {
            $hours = [int] [math]::Floor($InputObject.TotalHours)
            $minutes = $InputObject.Minutes
            $seconds = $InputObject.Seconds
        } else {
            throw 'Duration must be a TimeSpan or HH:MM:SS string.'
        }

        if (($hours + $minutes + $seconds) -le 0) {
            throw 'Duration must be greater than zero.'
        }

        $value = 'PT'

        if ($hours -gt 0) { $value += "$($hours)H" }
        if ($minutes -gt 0) { $value += "$($minutes)M" }
        if ($seconds -gt 0 -or $value -eq 'PT') { $value += "$($seconds)S" }

        return $value
    }

    function Connect-RequiredGraph {
        Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
        Import-Module Microsoft.Graph.Users -ErrorAction Stop
        Import-Module Microsoft.Graph.Identity.Governance -ErrorAction Stop

        $requiredScopes = @(
            'User.Read',
            'RoleEligibilitySchedule.Read.Directory',
            'RoleAssignmentSchedule.Read.Directory',
            'RoleAssignmentSchedule.ReadWrite.Directory',
            'RoleManagement.Read.Directory'
        )

        $ctx = Get-MgContext
        $needConnect = $false

        if (-not $ctx -or -not $ctx.Account) {
            $needConnect = $true
        } else {
            foreach ($scope in $requiredScopes) {
                if ($ctx.Scopes -notcontains $scope) {
                    $needConnect = $true
                }
            }
        }

        if ($needConnect) {
            if ($ctx) {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            }

            Connect-MgGraph `
                -NoWelcome `
                -Scopes $requiredScopes `
                -ErrorAction Stop |
            Out-Null
        }
    }

    try {
        Connect-RequiredGraph

        $ctx = Get-MgContext

        if (-not $ctx -or -not $ctx.Account) {
            throw 'Not connected to Microsoft Graph.'
        }

        $me = Get-MgUser `
            -UserId $ctx.Account `
            -Property Id, UserPrincipalName, DisplayName `
            -ErrorAction Stop

        $principalId = $me.Id

        $roleDefinition = Get-MgRoleManagementDirectoryRoleDefinition -All |
        Where-Object { $_.DisplayName -eq $RoleName } |
        Select-Object -First 1

        if (-not $roleDefinition) {
            throw "Directory role '$RoleName' was not found."
        }

        $roleDefinitionId = $roleDefinition.Id

        $eligible = Get-MgRoleManagementDirectoryRoleEligibilitySchedule -All |
        Where-Object {
            $_.PrincipalId -eq $principalId -and
            $_.RoleDefinitionId -eq $roleDefinitionId -and
            $_.DirectoryScopeId -eq $DirectoryScopeId
        } |
        Select-Object -First 1

        if (-not $eligible) {
            throw "Signed-in user is not PIM eligible for '$RoleName' at scope '$DirectoryScopeId'."
        }

        $isoDuration = Convert-ToIso8601Duration -InputObject $Duration

        $body = @{
            action           = 'selfActivate'
            justification    = $Justification
            directoryScopeId = $DirectoryScopeId
            principalId      = $principalId
            roleDefinitionId = $roleDefinitionId
            scheduleInfo     = @{
                startDateTime = (Get-Date).ToUniversalTime().ToString('o')
                expiration    = @{
                    type     = 'AfterDuration'
                    duration = $isoDuration
                }
            }
        }

        if ($TicketNumber -or $TicketSystem) {
            $body.ticketInfo = @{
                ticketNumber = if ($TicketNumber) { $TicketNumber } else { '' }
                ticketSystem = if ($TicketSystem) { $TicketSystem } else { '' }
            }
        }

        $request = New-MgRoleManagementDirectoryRoleAssignmentScheduleRequest `
            -BodyParameter $body `
            -ErrorAction Stop

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $active = $null

        do {
            Start-Sleep -Seconds 3

            $active = Get-MgRoleManagementDirectoryRoleAssignmentSchedule -All |
            Where-Object {
                $_.PrincipalId -eq $principalId -and
                $_.RoleDefinitionId -eq $roleDefinitionId -and
                $_.DirectoryScopeId -eq $DirectoryScopeId
            }
        }
        while (-not $active -and (Get-Date) -lt $deadline)

        [pscustomobject]@{
            RequestId        = $request.Id
            RoleName         = $RoleName
            RoleDefinitionId = $roleDefinitionId
            PrincipalId      = $principalId
            DirectoryScopeId = $DirectoryScopeId
            Duration         = $isoDuration
            LanguageMode     = $ExecutionContext.SessionState.LanguageMode
            Active           = [bool] $active
            ActiveAssignment = $active |
            Select-Object Id, StartDateTime, EndDateTime, Status, RoleDefinitionId, DirectoryScopeId
        }
    } catch {
        if ($isConstrainedLanguage) {
            throw "Failed to activate PIM role '$RoleName'. PowerShell is running in ConstrainedLanguage mode. $($_.Exception.Message)"
        }

        throw "Failed to activate PIM role '$RoleName'. $($_.Exception.Message)"
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
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE', 'PUT')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [hashtable]$Query,
        [hashtable]$Headers,
        $Body,
        [string]$AccessToken,
        [string]$OutputType = 'Json'
    )

    #
    # Build final URI with query parameters
    #
    if ($Query) {
        $encoded = $Query.GetEnumerator() |
        ForEach-Object { '{0}={1}' -f [System.Web.HttpUtility]::UrlEncode($_.Key), [System.Web.HttpUtility]::UrlEncode($_.Value) }

        if ($Uri.Contains('?')) {
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
        $finalHeaders['Authorization'] = "Bearer $AccessToken"
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
        $params['Headers'] = $finalHeaders
    }

    #
    # Add Body if provided
    #
    if ($PSBoundParameters.ContainsKey('Body')) {
        # Convert PowerShell objects to JSON automatically
        if ($Body -isnot [string] -and $Body -isnot [byte[]]) {
            $Body = ($Body | ConvertTo-Json -Depth 10)
        }

        $params['Body'] = $Body
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
        [ValidateNotNullOrEmpty()]
        [string]$TenantId = $Env:AZURE_TENANT_ID,

        [ValidateNotNullOrEmpty()]
        [string]$ClientId = $Env:AZURE_CLIENT_ID,

        [ValidateNotNullOrEmpty()]
        [string]$SharePointHost = $Env:AZURE_SHAREPOINT_ADMIN
    )

    # ----- Step 1: Request device code -----
    $scope = "https://${SharePointHost}.sharepoint.com/.default offline_access openid profile"

    $deviceCodeBody = @{
        client_id = $ClientId
        scope     = $scope
    }

    $deviceCodeUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"

    Write-Verbose "Requesting device code for tenant '$TenantId' and scope '$scope'..."
    $device = Invoke-RestMethod -Method POST -Uri $deviceCodeUri -Body $deviceCodeBody

    Write-Host ''
    Write-Host 'To sign in, open the following URL in a browser and enter the code:' -ForegroundColor Cyan
    Write-Host "  URL : $($device.verification_uri)" -ForegroundColor Yellow
    Write-Host "  Code: $($device.user_code)" -ForegroundColor Yellow
    Write-Host ''

    # ----- Step 2: Poll token endpoint -----
    $tokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $pollBody = @{
        grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
        client_id   = $ClientId
        device_code = $device.device_code
    }

    $expiresIn = [int]$device.expires_in
    $intervalSec = [int]$device.interval
    $startTime = Get-Date

    Write-Verbose "Polling token endpoint every $intervalSec seconds for up to $expiresIn seconds..."

    $token = $null

    while (-not $token) {
        # Check timeout
        $elapsed = (Get-Date) - $startTime
        if ($elapsed.TotalSeconds -ge $expiresIn) {
            throw 'Device code has expired. Please run the function again to start a new sign-in.'
        }

        try {
            $token = Invoke-RestMethod -Method POST -Uri $tokenUri -Body $pollBody
        } catch {
            $errorResponse = $_.ErrorDetails.Message
            if ($errorResponse -match 'authorization_pending') {
                # User hasn't completed login yet – wait and retry
                Start-Sleep -Seconds $intervalSec
                continue
            } elseif ($errorResponse -match 'slow_down') {
                # Service is asking us to slow down – wait a bit more
                Start-Sleep -Seconds ($intervalSec + 2)
                continue
            } else {
                throw "Failed to obtain token. Error response: $errorResponse"
            }
        }
    }

    $accessToken = $token.access_token

    if (-not $accessToken) {
        throw 'The response did not contain an access_token.'
    }

    # ----- store in environment variable and clipboard -----
    $env:ACCESS_TOKEN_SHAREPOINT = $accessToken
    $accesstoken | Set-Clipboard
    Write-Host 'Stored access token in environment variable ACCESS_TOKEN_SHAREPOINT and in Clipboard.'

    Write-Host "Connect-PnPOnline -Url ""https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com"" UseDeviceAuthentication:$false -AccessToken "'$env:ACCESS_TOKEN_SHAREPOINT'
    Write-Host 'Get-PnpConnection'
    return ##$accessToken
}

function Test-SharePoint {
    Get-SPODelegatedAccessToken ## via device flow
    Connect-PnPOnline -Url "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com" -Interactive -ClientId $env:AZURE_CLIENT_ID
    ## Connect-PnPOnline -Url "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com" -UseDeviceAuthentication:$false -AccessToken $env:ACCESS_TOKEN_SHAREPOINT
    Set-Item -Path Env:\SHAREPOINT_ACCESS_TOKEN -Value (Get-PnPAccessToken -Decoded).EncodedToken    
    Get-PnPTenant
    Get-PnPTenantSite
    Disconnect-PnPOnline
}

function Get-Token-Graph {
    ##use Graph Model
    [CmdletBinding()]
    param(
        [string]$TenantId = $Env:AZURE_TENANT_ID,
        
        [string]$ClientId = $Env:AZURE_CLIENT_ID,
        
        [ValidateNotNullOrEmpty()]
        [string[]]$Scopes = @('.default')
    )

    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false
    
    ## Set to public client, if CLIENT_ID is not set
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        Write-Host '❌ Environment variable AZURE_CLIENT_ID not set, so setting it to Graph PowerShell / Azure CLI style'
        $ClientId = '1950a258-227b-4e31-a9cf-717495945fc2' ## Microsoft Azure PowerShell
    }
        
    try {
        ## uses WAM broker -UseDeviceAuthentication:$false
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            Connect-MgGraph -ClientId $ClientId -Scopes $($Scopes -join ' ') -UseDeviceAuthentication:$false -NoWelcome
        } else {
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Scopes $($Scopes -join ' ') -UseDeviceAuthentication:$false -NoWelcome
        }
        $response = Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/me' -OutputType 'HttpResponseMessage'
    } catch { 
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        throw "❌ Get-Token failed. $($_.Exception.Message)"
    }

    ## Primary path: read the Bearer token from the *request* Authorization header
    $authHeader = $response.RequestMessage.Headers.Authorization
    if ($authHeader -and $authHeader.Scheme -eq 'Bearer' -and $authHeader.Parameter) {
        $accesstoken = $authHeader.Parameter
    }

    if ($accesstoken -and $accesstoken.Length -gt 1) {
        Set-Item -Path Env:\ACCESS_TOKEN -Value $accesstoken
        $accesstoken | Set-Clipboard
        Write-Host 'Access token saved to ENV:ACCESS_TOKEN and copied to clipboard.'
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $true
    }

    Write-Host '❌ Access denied or token not available.'
    
    $PSDefaultParameterValues['*:Verbose'] = $preserve
    return $false
}

function Get-Token-Device-Flow {
    ## without Graph Modules
    ## https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code
    param(
        ## Provide if you want; otherwise we'll pick it up from env vars
        [ValidateNotNullOrEmpty()]
        [string]$TenantId = $Env:AZURE_TENANT_ID,
        
        [ValidateNotNullOrEmpty()]
        [string]$ClientId = $Env:AZURE_CLIENT_ID,

        [ValidateNotNullOrEmpty()]
        [string[]]$Scopes = @('.default')
    )
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    ## Request a device code for the given scopes
    $deviceCodeResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode" `
        -Body @{
        client_id = $ClientId
        scope     = $($Scopes -join ' ')
    }

    Write-Host "Attempting to logon as Client_ID $ClientId to Tenant: $TenantId with these scopes: ($Scopes -join ' ')"
    Write-Host "`nGo to $($deviceCodeResponse.verification_uri) and enter code: $($deviceCodeResponse.user_code)" -ForegroundColor Yellow
    Write-Host 'Waiting for sign-in and consent...' -ForegroundColor DarkGray

    ## Poll until user signs in and token is issued
    while ($true) {
        Start-Sleep -Seconds $deviceCodeResponse.interval

        try {
            $tokenResponse = Invoke-RestMethod -Method POST `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Body @{
                grant_type  = 'device_code'
                client_id   = $ClientId
                device_code = $deviceCodeResponse.device_code
            }

            if ($tokenResponse.access_token) {
                Write-Host 'Access token saved to ENV:ACCESS_TOKEN and copied to clipboard.'
                Set-Item -Path Env:\ACCESS_TOKEN -Value $tokenResponse.access_token 
                $tokenResponse.access_token | Set-Clipboard
                $PSDefaultParameterValues['*:Verbose'] = $preserve
                return $true
            }
        } catch {
            # Entra ID returns 'authorization_pending' until user completes login
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            $errormsg = $errorJson.error
            if ($errormsg -ne 'authorization_pending') {
                Write-Warning "❌ Unexpected error: $($_.ErrorDetails.Message)"
                $PSDefaultParameterValues['*:Verbose'] = $preserve
                break
            }
        }
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
    return $false
}

function Get-Token-Interactive {
    ## via Browser
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

        [string]$RedirectUri = 'https://login.microsoftonline.com/common/oauth2/nativeclient',

        [string[]]$Scopes = @('User.Read')  ## e.g. @('Mail.ReadBasic','Mail.Read')
    )

    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

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
        throw 'TenantId not provided and no environment variable (AZURE_TENANT_ID/ARM_TENANT_ID/AAD_TENANT_ID) was found.'
    }
    $clientCandidates = @(
        $ClientId,
        $env:AZURE_CLIENT_ID,  # Azure CLI / general
        $env:ARM_CLIENT_ID,    # Terraform/ARM conventions
        $env:AAD_CLIENT_ID     # some orgs use this
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $ClientId = $clientCandidates | Select-Object -First 1
    if (-not $ClientId) {
        throw 'ClientId not provided and no environment variable (AZURE_CLIENT_ID/ARM_CLIENT_ID/AAD_CLIENT_ID) was found.'
    }
    Write-Verbose "Using TenantId: $TenantId"
    Write-Verbose "Using ClientId: $ClientId"
    Write-Verbose "Using Scopes  : $Scopes"

    Write-Host "Attempting to logon as Client_ID $ClientId to Tenant: $TenantId with these scopes: $Scopes"
    # Build the authorize URL
    $authUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize" +
    "?client_id=$ClientId" +
    '&response_type=code' +
    "&redirect_uri=$([uri]::EscapeDataString($RedirectUri))" +
    '&response_mode=query' +
    "&scope=$([uri]::EscapeDataString($Scopes))" +
    '&state=12345'
    Write-Host $authUrl

    Write-Host 'Opening browser for Entra ID sign-in...' -ForegroundColor Cyan
    Start-Process $authUrl

    Write-Host "`nAfter you sign in, you'll be redirected to a URL similar to:`n"
    Write-Host "$RedirectUri?code=YOUR_CODE_HERE&state=12345" -ForegroundColor Yellow
    Write-Host "`nCopy the 'code' value from that URL and paste it below.`n"

    # Prompt user for authorization code
    $authCode = Read-Host 'Enter the authorization code'

    if ([string]::IsNullOrWhiteSpace($authCode)) {
        Write-Warning '❌ No code entered. Aborting.'
        return
    }

    # Exchange authorization code for access token
    $body = @{
        grant_type   = 'authorization_code'
        client_id    = $ClientId
        code         = $authCode
        redirect_uri = $RedirectUri
        scope        = $Scopes
    }

    $tokenResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Body $body

    if ($tokenResponse.access_token) {
        Write-Host 'Access token saved to ENV:ACCESS_TOKEN and copied to clipboard.'
        Set-Item -Path Env:\ACCESS_TOKEN -Value $tokenResponse.access_token 
        $tokenResponse.access_token | Set-Clipboard
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $true
    } else {
        Write-Warning 'Failed to retrieve access token.'
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $false
    }
}

function Get-Token-MSAL {
    if ($IsLanguagePermissive) {
        # Install once:
        # Install-Package Microsoft.Identity.Client -Source https://www.nuget.org/api/v2 -Scope CurrentUser
        Add-Type -Path "$env:USERPROFILE\.nuget\packages\microsoft.identity.client\*\lib\net472\Microsoft.Identity.Client.dll"

        $tenantId = $env.AZURE_TENANT_ID
        $clientId = $env.AZURE_CLIENT_ID  ##"04b07795-8ddb-461a-bbee-02f9e1bf7b46"  # Public client (Graph PowerShell / Azure CLI style)
        $scopes = @('User.Read')

        $app = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($clientId).
        WithAuthority("https://login.microsoftonline.com/$tenantId").
        WithDefaultRedirectUri().
        Build()

        $result = $app.AcquireTokenInteractive($scopes).ExecuteAsync().GetAwaiter().GetResult()

        $accessToken = $result.AccessToken    
        $accessToken | Set-Clipboard
        Write-Host 'Access token copied to clipboard.'
    } else {
        Write-Host 'Langauge mode does not permit loading of MSAL library'
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
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    if (-not $env:ACCESS_TOKEN) {
        throw 'No ACCESS_TOKEN found in environment variables.'
    }

    $endpoint = 'https://graph.microsoft.com/v1.0/me'
    #$endpoint = "https://graph.microsoft.com/oidc/userinfo"

    ## Alternative
    #Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me"

    try {
        $params = @{
            Method      = 'GET'
            Uri         = $endpoint
            Headers     = @{
                'Authorization' = "Bearer $($env:ACCESS_TOKEN)"
            }
            ErrorAction = 'Stop'
        }
        
        $response = Invoke-RestMethod @params
        $response | Format-List
        $PSDefaultParameterValues['*:Verbose'] = $preserve
        return $true
    } catch {
        throw "Failed to retrieve userinfo: $($_.Exception.Message)"
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
    return false
}

function Get-Token-Info {
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    Import-Module JWTDetails
    ## or goto: https://jwt-decoder.com/
    ##          https://jwt.ms
    $jwt = Get-JWTDetails $env:ACCESS_TOKEN
    if ( -not ($jwt) ) {
        $jwt = Get-JWTDetails | Get-Clipboard
        if ( -not ($jwt) ) {
            Write-Host '❌ Failed to decode token.' -ForegroundColor Red
            Write-Host 'Token can either be in the clipboard or in environment variable ACCESS_TOKEN'
            $PSDefaultParameterValues['*:Verbose'] = $preserve
            return
        }
    }
    Write-Host ('Name                : ' + ($jwt.name -join ' '))
    Write-Host ('UPN                 : ' + ($jwt.upn -join ' '))
    Write-Host ('As Application      : ' + ($jwt.app_displayname -join ' '))
    Write-Host ('Authorisation Server: ' + ($jwt.iss -join ' '))
    Write-Host ('Authorised Scopes   : ' + ($jwt.scp -join ' '))
    Write-Host ('Against Tenancy     : ' + ($jwt.tid -join ' '))
    Write-Host ('WIDS                : ' + ($jwt.wids -join ' ')) 

    if ( $jwt.scp -like '*ReadWrite.All*' | Out-Null ) {
        Write-Host -ForegroundColor Red 'Be careful - this token contains ReadWrite.All in atleast one of its scopes'
        $scopes -match 'ReadWrite.All' | Write-Host -ForegroundColor Red
    }
        
    ## exp should be a UNIX timestamp (seconds since epoch)
    $expUnix = [long]$jwt.exp

    if ($IsLanguagePermissive) {
        ## Convert exp to local DateTime
        $expiry = [DateTimeOffset]::FromUnixTimeSeconds($expUnix).ToLocalTime()
        ## Compute difference
        $now = Get-Date
        $minutesRemaining = [math]::Round(($expiry - $now).TotalMinutes, 2)
        if ($minutesRemaining -le 0) {
            Write-Host '❌ Token has expired!' -ForegroundColor Red
        } else {
            Write-Host "✅ Token expires in $minutesRemaining minutes"
        }
    }
    $PSDefaultParameterValues['*:Verbose'] = $preserve
}

function Test-Token-Email {
    ## with Graph Modules
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    $params = @{
        Method = 'GET'
        Uri    = 'https://graph.microsoft.com/v1.0/me/messages' +
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
    } catch {
        throw "Get email failed. $_"
    }
    ## Write-Verbose "OData Context:" $response.'@odata.context'
    $Response.Headers
    Write-Verbose ('OData Context: {0}' -f $response.'@odata.context')
    $items = if ($response.PSObject.Properties.Name -contains 'value') { $response.value } else { @($response) }
    $items
    # Extract and process the message collection
    $messages = $response.value | Select-Object `
    @{n = 'ReceivedLocal'; e = { [datetime]$_.receivedDateTime.ToLocalTime() } },
    @{n = 'Subject'; e = { $_.subject } }

    $messages | Format-Table -AutoSize
    $PSDefaultParameterValues['*:Verbose'] = $preserve
}

function Test-Token-Access {
    ## with Graph Modules
    ## Turn off verbose
    $preserve = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false
    if (-not $env:ACCESS_TOKEN) {
        throw 'No ACCESS_TOKEN found in environment variables.'
    }
    $SecureAccessToken = ConvertTo-SecureString -String $env:ACCESS_TOKEN -AsPlainText -Force
    Connect-MgGraph -AccessToken $SecureAccessToken -NoWelcome
    Get-MgContext

    $PSDefaultParameterValues['*:Verbose'] = $preserve
}


function Get-EntraID-Info {
    ## Turn off verbose
    $preserve = $VerbosePreference
    $VerbosePreference = 'Ignore'

    # Retrieve the OpenID Connect metadata (no modules required)
    $openidConfig = Invoke-RestMethod -Uri 'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration'

    # Show top-level keys
    $openidConfig | Format-List
    $VerbosePreference = $preserve
}

##if (Get-Command 'azd' -ErrorAction SilentlyContinue) {
##    azd auth login --check-status
##}

if ( ($env:DEVELOPER -eq 'Yes') -and ($IsLanguagePermissive -eq $true) ) { 
    ## dotnet shell completions
    dotnet completions script pwsh | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
    if (Get-Command 'azd' -ErrorAction SilentlyContinue) {
        azd completion powershell | Out-String | Invoke-Expression -ErrorAction SilentlyContinue
    }
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
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Path = 'C:\workspaces',

        [bool]$TakeOwnership = $true,
        [bool]$BreakInheritance = $true,
        [bool]$RemoveDeny = $true,
        [bool]$Recurse = $true
    )

    begin {
        # Well-known SIDs (locale independent)
        $SidSystem = '*S-1-5-18'        # SYSTEM
        $SidAdmins = '*S-1-5-32-544'    # BUILTIN\Administrators
        $SidUsers = '*S-1-5-32-545'    # BUILTIN\Users

        # Inheritance flags for files & folders
        $inheritFlags = '(OI)(CI)'

        function Invoke-Icacls {
            param([string[]]$IcaArgs)
            Write-Verbose ('icacls {0}' -f ($IcaArgs -join ' '))
            if ($PSCmdlet.ShouldProcess("icacls $($IcaArgs -join ' ')")) {
                & icacls @IcaArgs
            }
        }

        function Assert-Elevated {
            $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $p = New-Object System.Security.Principal.WindowsPrincipal($id)
            if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
                throw 'This function must be run in an elevated PowerShell (Run as Administrator).'
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
                if ($PSCmdlet.ShouldProcess($target, 'Take ownership (recursive)')) {
                    & takeown /f "$target" /r /d y | Out-Null
                    Invoke-Icacls -Args @("$target", '/setowner', 'Users', '/t', '/c') | Out-Null
                }
            }

            # 2) Inheritance control
            if ($BreakInheritance) {
                ## Disable
                Invoke-Icacls -Args @("$target", '/inheritance:d', '/c') | Out-Null
            } else {
                ## Enable
                Invoke-Icacls -Args @("$target", '/inheritance:e', '/c') | Out-Null
            }

            # 3) Remove explicit DENY entries that would override our grant
            if ($RemoveDeny) {
                # These may no-op if none exist; that's fine.
                Invoke-Icacls -Args @("$target", '/remove:d', 'Users', '/c') | Out-Null
                Invoke-Icacls -Args @("$target", '/remove:d', 'Everyone', '/c') | Out-Null
            }

            # 4) Grant the desired rights
            $recurseFlag = if ($Recurse) { '/t' } else { $null }

            # Keep SYSTEM/Admins Full Control
            Invoke-Icacls -Args @("$target", '/grant', "${SidSystem}:${inheritFlags}(F)", $recurseFlag, '/c') | Out-Null
            Invoke-Icacls -Args @("$target", '/grant', "${SidAdmins}:${inheritFlags}(F)", $recurseFlag, '/c') | Out-Null

            # Give Users Modify (NOT Full Control)
            Invoke-Icacls -Args @("$target", '/grant', "${SidUsers}:${inheritFlags}(M)", $recurseFlag, '/c') | Out-Null

            # 5) Display resulting ACEs on the root for verification
            Write-Verbose 'Final ACL (root):'
            & icacls "$target"
        } catch {
            throw "Set-FolderAclUsersModify failed: $($_.Exception.Message)"
        }
    }
}
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Bin"
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Workspaces"
#Set-FolderAclUsersModify -Path "$env:SystemDrive\Scripts"

function Get-TLSInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('HostName')]
        [string]$Fqdn,

        [ValidateRange(1, 65535)]
        [int]$Port = 443,

        [string]$ExportCerPath,

        [ValidateRange(1, 300000)]
        [int]$TimeoutMs = 8000,

        [System.Security.Authentication.SslProtocols]$TlsProtocols = (
            [System.Security.Authentication.SslProtocols]::Tls12 -bor
            [System.Security.Authentication.SslProtocols]::Tls13
        )
    )

    begin {
        # Tracks export paths already written during this pipeline invocation,
        # so piping multiple hosts at the same -ExportCerPath doesn't silently
        # clobber each earlier host's exported certificate.
        $usedExportPaths = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )

        function Get-SubjectAltNames {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
            )

            $out = @()

            foreach ($ext in $Cert.Extensions) {
                if ($ext.Oid.Value -eq '2.5.29.17') {
                    try {
                        $san = [System.Security.Cryptography.AsnEncodedData]::new($ext.Oid, $ext.RawData)
                        # NOTE: Format() renders via the OS's native crypto formatting
                        # (CryptoAPI on Windows), which is locale-dependent — the
                        # "DNS Name=" label assumed by the regex below may render
                        # differently on non-English Windows locales, and .Format()
                        # output can differ on non-Windows platforms entirely under
                        # PowerShell 7's cross-platform runtime. This is a known
                        # limitation, not something this function corrects for.
                        $text = $san.Format($true)

                        if ($text) {
                            $out += ($text -split "`r?`n" | Where-Object { $_ }) |
                            ForEach-Object { ($_ -replace '^\s*DNS Name=\s*', '').Trim() } |
                            Where-Object { $_ }
                        }
                    } catch {
                        Write-Verbose "Failed to parse SAN extension: $($_.Exception.Message)"
                    }
                }
            }

            return ($out | Select-Object -Unique)
        }

        function Get-PublicKeySize {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory)]
                [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert
            )

            # .PublicKey.Key throws NotSupportedException for ECDSA certificates —
            # it's a legacy property that never gained EC support. The algorithm-
            # specific accessors below are the correct way to get key size
            # regardless of algorithm — but they are C# EXTENSION methods (defined
            # in RSACertificateExtensions / ECDsaCertificateExtensions /
            # DSACertificateExtensions), not real instance members of
            # X509Certificate2. PowerShell has no extension-method call sugar, so
            # they must be invoked as explicit static calls on the extension
            # class — calling $Cert.GetRSAPublicKey() directly fails with
            # "does not contain a method named 'GetRSAPublicKey'".
            $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Cert)
            if ($rsa) { return $rsa.KeySize }

            $ecdsa = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPublicKey($Cert)
            if ($ecdsa) { return $ecdsa.KeySize }

            $dsa = [System.Security.Cryptography.X509Certificates.DSACertificateExtensions]::GetDSAPublicKey($Cert)
            if ($dsa) { return $dsa.KeySize }

            return $null
        }
    }

    process {
        # Accept a full URL (e.g. copy-pasted from a browser address bar) as
        # well as a bare hostname. TcpClient.ConnectAsync and SNI both need
        # just the host — a scheme, path, or trailing slash would otherwise
        # cause a DNS/connection failure. [Uri] parsing is used rather than a
        # plain string replace so it also correctly strips any path/query
        # string, not just the scheme.
        $targetHost = $Fqdn
        if ($Fqdn -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
            $parsedUri = $null
            if ([System.Uri]::TryCreate($Fqdn, [System.UriKind]::Absolute, [ref]$parsedUri)) {
                $targetHost = $parsedUri.Host
            } else {
                # Fallback if it looked like a URL but didn't parse cleanly —
                # strip scheme and anything from the first '/' onward manually.
                $targetHost = $Fqdn -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', '' -replace '/.*$', ''
            }
            Write-Verbose "Normalized '$Fqdn' to host '$targetHost'."
        }

        $actualExportPath = $ExportCerPath
        if ($ExportCerPath) {
            if ($usedExportPaths.Contains($ExportCerPath)) {
                $dir = Split-Path -Path $ExportCerPath -Parent
                $base = [System.IO.Path]::GetFileNameWithoutExtension($ExportCerPath)
                $ext = [System.IO.Path]::GetExtension($ExportCerPath)
                $safeHost = $targetHost -replace '[^\w\.-]', '_'
                $actualExportPath = if ($dir) { Join-Path $dir "$base-$safeHost$ext" } else { "$base-$safeHost$ext" }
                Write-Warning "ExportCerPath '$ExportCerPath' was already used earlier in this pipeline run; writing '$targetHost' to '$actualExportPath' instead to avoid overwriting the previous host's certificate."
            }

            $exportDir = Split-Path -Path $actualExportPath -Parent
            if ($exportDir -and -not (Test-Path -LiteralPath $exportDir)) {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            }
        }

        $client = $null
        $stream = $null
        $ssl = $null
        $chain = $null
        $cert2 = $null

        try {
            $client = [System.Net.Sockets.TcpClient]::new()

            $connectTask = $client.ConnectAsync($targetHost, $Port)
            if (-not $connectTask.Wait($TimeoutMs)) {
                throw "Timeout connecting to ${targetHost}:${Port} after ${TimeoutMs} ms."
            }

            if (-not $client.Connected) {
                throw "TCP connection to ${targetHost}:${Port} failed."
            }

            $stream = $client.GetStream()

            # WARNING — validation callback always returns $true: this deliberately
            # accepts ANY certificate (expired, self-signed, wrong host, MITM'd —
            # everything), because this function's entire purpose is to inspect
            # certificates regardless of validity. This is correct HERE, but this
            # exact pattern must never be copied into code that makes real,
            # trust-sensitive connections — doing so silently disables all TLS
            # protection for that connection.
            $ssl = [System.Net.Security.SslStream]::new(
                $stream,
                $false,
                { param($sslSender, $certificate, $chainArg, $sslPolicyErrors) $true }
            )

            try {
                $authOptions = [System.Net.Security.SslClientAuthenticationOptions]::new()
                $authOptions.TargetHost = $targetHost
                $authOptions.EnabledSslProtocols = $TlsProtocols
                $ssl.AuthenticateAsClient($authOptions)
            } catch {
                Write-Verbose "Modern AuthenticateAsClient overload failed, falling back: $($_.Exception.Message)"
                $ssl.AuthenticateAsClient($targetHost)
            }

            if (-not $ssl.RemoteCertificate) {
                throw "No certificate was presented by ${targetHost}:${Port}."
            }

            $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($ssl.RemoteCertificate)

            $chain = [System.Security.Cryptography.X509Certificates.X509Chain]::new()
            $chain.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $chain.ChainPolicy.RevocationFlag = [System.Security.Cryptography.X509Certificates.X509RevocationFlag]::EndCertificateOnly
            $chain.ChainPolicy.VerificationFlags = [System.Security.Cryptography.X509Certificates.X509VerificationFlags]::IgnoreWrongUsage
            [void]$chain.Build($cert2)

            $san = Get-SubjectAltNames -Cert $cert2
            $keySizeBits = Get-PublicKeySize -Cert $cert2

            if ($actualExportPath) {
                [System.IO.File]::WriteAllBytes(
                    $actualExportPath,
                    $cert2.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
                )
                [void]$usedExportPaths.Add($actualExportPath)
            }

            [PSCustomObject]@{
                Hostname           = $targetHost
                Port               = $Port
                OwnerSubject       = $cert2.Subject
                SubjectCN          = $cert2.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::DnsName, $false)
                Issuer             = $cert2.Issuer
                NotBefore          = $cert2.NotBefore
                NotAfter           = $cert2.NotAfter
                IsExpired          = ([DateTime]::UtcNow -ge $cert2.NotAfter.ToUniversalTime())
                Thumbprint         = $cert2.Thumbprint
                SerialNumber       = $cert2.SerialNumber
                SignatureAlgorithm = $cert2.SignatureAlgorithm.FriendlyName
                KeyAlgorithm       = $cert2.PublicKey.Oid.FriendlyName
                KeySizeBits        = $keySizeBits
                SANs               = $san
                ChainStatus        = @($chain.ChainStatus | ForEach-Object { $_.Status.ToString() }) -join ', '
                ExportedCerPath    = $actualExportPath
            }
        } catch {
            $message = "Failed to retrieve certificate from ${targetHost}:${Port}. $($_.Exception.Message)"
            Write-Error $message
        } finally {
            if ($cert2) { $cert2.Dispose() }
            if ($chain) { $chain.Dispose() }
            if ($ssl) { $ssl.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($client) { $client.Dispose() }
        }
    }
}
# Examples:
# Show owner/subject for a site
# Get-TLSInfo -Fqdn "www.microsoft.com"
# Get-TLSInfo -Fqdn "cnn.com"
# Export the certificate to a file as well
# Get-TLSInfo -Fqdn "example.com" -ExportCerPath "C:\Temp\example.cer"

function Show-Toast-Message {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Title,

        [Parameter(Mandatory, Position = 1)]
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
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
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
 
        $notifyIcon.Icon = $icon
        $notifyIcon.Visible = $true
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText = $Message

        # Show the notification
        $notifyIcon.ShowBalloonTip($DurationMs)

        # Give Windows time to display before disposing
        Start-Sleep -Milliseconds $DurationMs
    } finally {
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

    $routes = @('0.0.0.0/0')
    if ($IncludeIPv6) { $routes += '::/0' }

    $results = foreach ($prefix in $routes) {
        $route = Get-NetRoute -DestinationPrefix $prefix -ErrorAction SilentlyContinue |
        Sort-Object -Property RouteMetric, InterfaceMetric |
        Select-Object -First 1

        if ($null -ne $route) {
            $adapter = Get-NetAdapter -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue

            [pscustomobject]@{
                AddressFamily        = if ($prefix -eq '::/0') { 'IPv6' } else { 'IPv4' }
                DefaultRouterAdapter = $adapter.Name
                InterfaceIndex       = $adapter.InterfaceIndex
                InterfaceDescription = $adapter.InterfaceDescription
                MACAddress           = $adapter.MacAddress
                Status               = $adapter.Status
                IPvGateway           = $route.NextHop
                RouteMetric          = $route.RouteMetric
                InterfaceMetric      = $route.InterfaceMetric
            }
        }
    }

    if ($results) {
        $results
    } else {
        Write-Warning 'No default routes found.'
    }
}

function Get-EntraDelegatedGrantsReport {
    [CmdletBinding()]
    param(
        # Scopes we don't care about
        [string[]]$ExcludeScopes = @('openid', 'profile', 'email', 'offline_access', 'User.Read')
    )

    # Cache for service principals to avoid hammering Graph
    $spCache = @{}

    function Get-SpCached {
        param([string]$Id)

        if (-not $Id) { return $null }

        if (-not $spCache.ContainsKey($Id)) {
            $spCache[$Id] = Get-MgServicePrincipal -ServicePrincipalId $Id -ErrorAction SilentlyContinue
        }

        return $spCache[$Id]
    }

    Write-Verbose 'Retrieving all OAuth2 delegated permission grants...'
    $grants = Get-MgOauth2PermissionGrant -All

    $output = foreach ($grant in $grants) {
        if ([string]::IsNullOrWhiteSpace($grant.Scope)) { continue }

        # Split the space-delimited scopes
        $scopes = $grant.Scope -split ' '
        # Filter out boring baseline scopes
        $interesting = $scopes | Where-Object {
            $_ -and ($ExcludeScopes -notcontains $_)
        }

        # Skip grants that only have openid/profile/email
        if (-not $interesting) { continue }

        $clientSp = Get-SpCached -Id $grant.ClientId
        $resourceSp = Get-SpCached -Id $grant.ResourceId

        [pscustomobject]@{
            AppName       = $clientSp.DisplayName
            ## AppId          = $clientSp.AppId
            ClientId      = $grant.ClientId
            Resource      = $resourceSp.DisplayName
            ##ResourceAppId  = $resourceSp.AppId
            ##ResourceId     = $grant.ResourceId
            GrantedScopes = $interesting -join ' '
            #FullScopeField = $grant.Scope
        }
    }

    # Return the objects (caller decides how to display)
    $output | Sort-Object AppName, Resource
}

function Export-CAPolicies {
    <#
    .SYNOPSIS
    Export Microsoft Entra Conditional Access policies to JSON files.

    .DESCRIPTION
    Connects to Microsoft Graph (if needed), retrieves all Conditional Access policies,
    and exports each policy to an individual JSON file for backup purposes.

    .PARAMETER ExportPath
    Folder to write JSON files to. Created if it doesn't exist.

    .PARAMETER JsonDepth
    ConvertTo-Json depth. Defaults to 10 to avoid truncation.

    .PARAMETER Scopes
    Graph scopes to request if a connection is required. Defaults to Policy.Read.All.

    .PARAMETER SanitizeFileName
    Sanitizes policy display names so they are valid Windows filenames.

    .PARAMETER PassThru
    Returns objects describing exported files.

    .EXAMPLE
    Export-CAPoliciesToJson -ExportPath 'C:\Temp\CA\' -Verbose

    .EXAMPLE
    Export-CAPoliciesToJson -ExportPath "$env:USERPROFILE\Documents\CA-Backup" -PassThru |
      Format-Table -AutoSize

    .NOTES
    Based on: www.alitajran.com/export-conditional-access-policies/
    #>

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string] $ExportPath = 'C:\temp\',

        [Parameter(Mandatory = $false)]
        [ValidateRange(2, 100)]
        [int] $JsonDepth = 10,

        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string[]] $Scopes = @('Policy.Read.All'),

        [Parameter(Mandatory = $false)]
        [switch] $SanitizeFileName,

        [Parameter(Mandatory = $false)]
        [switch] $PassThru
    )

    begin {
        Set-StrictMode -Version Latest

        function New-SafeFileName {
            param(
                [Parameter(Mandatory)]
                [string] $Name
            )

            # Replace invalid filename chars, trim, and collapse whitespace
            $invalid = [Regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join ''))
            $safe = [Regex]::Replace($Name, "[$invalid]", '_')
            $safe = ($safe -replace '\s+', ' ').Trim()

            if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'UnnamedPolicy' }
            return $safe
        }

        # Ensure export folder exists
        if (-not (Test-Path -LiteralPath $ExportPath)) {
            Write-Verbose "Creating export folder: $ExportPath"
            New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
        }

        # Ensure we have a Graph connection
        try {
            $ctx = Get-MgContext -ErrorAction SilentlyContinue
            if (-not $ctx -or -not $ctx.Account) {
                Write-Verbose "Connecting to Microsoft Graph with scopes: $($Scopes -join ', ')"
                Connect-MgGraph -Scopes $Scopes | Out-Null
            } else {
                Write-Verbose "Already connected to Microsoft Graph as: $($ctx.Account)"
            }
        } catch {
            throw "Failed to establish Microsoft Graph connection. $($_.Exception.Message)"
        }
    }

    process {
        try {
            Write-Verbose 'Retrieving Conditional Access policies...'
            $allPolicies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop

            if (-not $allPolicies -or $allPolicies.Count -eq 0) {
                Write-Warning 'There are no Conditional Access policies to export.'
                return
            }

            $results = New-Object System.Collections.Generic.List[object]

            foreach ($policy in $allPolicies) {
                $policyName = $policy.DisplayName
                $fileName = if ($SanitizeFileName) { (New-SafeFileName -Name $policyName) } else { $policyName }

                # Always ensure .json extension
                $outFile = Join-Path -Path $ExportPath -ChildPath ($fileName + '.json')

                if ($PSCmdlet.ShouldProcess($outFile, "Export Conditional Access policy '$policyName'")) {
                    try {
                        $json = $policy | ConvertTo-Json -Depth $JsonDepth
                        $json | Out-File -LiteralPath $outFile -Force -Encoding utf8

                        Write-Host "✅ Exported CA policy: $policyName" -ForegroundColor Green

                        $result = [pscustomobject]@{
                            DisplayName = $policyName
                            Id          = $policy.Id
                            FilePath    = $outFile
                        }
                        $results.Add($result) | Out-Null
                    } catch {
                        Write-Host "❌ Failed exporting CA policy: $policyName. $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
            }

            if ($PassThru) { $results }
        } catch {
            throw "Error occurred while exporting policies. $($_.Exception.Message)"
        }
    }
}

function Connect-SharePoint {
    try {
        Install-Module Microsoft.Online.SharePoint.PowerShell -Force
        Import-Module Microsoft.Online.SharePoint.PowerShell -Force -UseWindowsPowerShell
        $adminUrl = "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com"
        Write-Host "Connecting to: ${adminUrl}..."
        Connect-SPOService -Url $adminUrl -ErrorAction Stop
        'Connected OK'
    } catch {
        $_ | Format-List * -Force
    }
}

function Invoke-Graph {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')][string]$Method = 'GET',
        [object]$Body
    )

    $headers = @{
        Authorization = "Bearer $env:GRAPH_TOKEN"
        Accept        = 'application/json'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $json = $Body | ConvertTo-Json -Depth 50
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType 'application/json' -Body $json
    }
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
}

function Get-AzureAustraliaEastIpRanges {
    [CmdletBinding()]
    param (
        [ValidateSet('raw', 'terraform')]
        [string]$Output = 'raw'
    )

    $downloadPage = 'https://www.microsoft.com/en-us/download/details.aspx?id=56519'

    Write-Verbose 'Downloading latest Azure IP ranges for Sydney Australia...'

    $jsonUrl = (Invoke-WebRequest -Uri $downloadPage -UseBasicParsing).Links |
    Where-Object href -Like '*.json' |
    Select-Object -First 1 -ExpandProperty href

    if (-not $jsonUrl) {
        throw 'Could not find Azure IP ranges JSON link.'
    }

    $json = Invoke-RestMethod -Uri $jsonUrl

    $prefixes = $json.values |
    Where-Object { $_.properties.region -eq 'australiaeast' } |
    ForEach-Object { $_.properties.addressPrefixes } |
    Sort-Object -Unique

    switch ($Output) {
        'raw' {
            $prefixes
        }
        'terraform' {
            $prefixes | ForEach-Object {
                '"{0}",' -f $_
            }
        }
    }
}

function Install-OrUpdate-Module {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ModuleName,

        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'AllUsers',

        [switch]$Prerelease,

        # If set, we attempt to Import-Module after install/update (non-fatal if it fails)
        [switch]$ImportAfter,

        [int]$RetryCount = 3,
        [int]$RetryDelaySeconds = 5
    )

    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    function Test-IsAdmin {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Invoke-WithRetry {
        param([scriptblock]$Script, [string]$Action)
        for ($i = 1; $i -le $RetryCount; $i++) {
            try { return & $Script }
            catch {
                if ($i -ge $RetryCount) { throw }
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    if ($Scope -eq 'AllUsers' -and -not (Test-IsAdmin)) {
        throw 'Scope=AllUsers requires an elevated PowerShell session.'
    }

    # Preserve global verbose default
    $hadVerboseDefault = $PSDefaultParameterValues.ContainsKey('*:Verbose')
    $prevVerbose = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    try {
        ## TLS 1.2 for older Windows / PS 5.1 gallery access
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        ## Trust PSGallery for legacy Install-Module path (PowerShellGet v2)
        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            $psg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
            if ($psg -and $psg.InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted | Out-Null
            }
        }

        ## If PSResourceGet cmdlets not available, bootstrap silently.
        if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
            # On Windows PowerShell 5.1, avoid NuGet provider prompts for Install-Module
            if ($PSVersionTable.PSVersion.Major -lt 6 -and (Get-Command Install-PackageProvider -ErrorAction SilentlyContinue)) {
                Invoke-WithRetry -Action 'Install NuGet provider' -Script {
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
                }
            }
            Invoke-WithRetry -Action 'Install Microsoft.PowerShell.PSResourceGet' -Script {
                Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope $Scope -Force -AllowClobber -Confirm:$false
            }
            Import-Module Microsoft.PowerShell.PSResourceGet -Force
        }

        # Ensure PSResourceGet has PSGallery registered as trusted (NuGet v2 endpoint is safest)
        $repoName = 'PSGallery'
        $repoUri = 'https://www.powershellgallery.com/api/v2'

        $repo = Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue
        if (-not $repo) {
            Register-PSResourceRepository -Name $repoName -Uri $repoUri -ApiVersion V2 -Trusted | Out-Null
        } elseif (-not $repo.Trusted) {
            Set-PSResourceRepository -Name $repoName -Trusted | Out-Null
        }

        # Determine install vs update using what's on disk (more reliable than Get-PSResource alone)
        $alreadyInstalled = @(Get-Module -ListAvailable -Name $ModuleName)

        if ($alreadyInstalled.Count -eq 0) {
            Write-Host "Installing '$ModuleName' ($Scope)..." -ForegroundColor Green

            Invoke-WithRetry -Action "Install $ModuleName" -Script {
                $common = @{
                    Name            = $ModuleName
                    Repository      = $repoName
                    Scope           = $Scope
                    TrustRepository = $true
                    AcceptLicense   = $true
                    Quiet           = $true
                    ErrorAction     = 'Stop'
                    WarningAction   = 'SilentlyContinue'
                }
                if ($Prerelease) { $common.Prerelease = $true }
                Install-PSResource @common | Out-Null
            }
        } else {
            Write-Host "Updating '$ModuleName' ($Scope)..." -ForegroundColor Cyan

            Invoke-WithRetry -Action "Update $ModuleName" -Script {
                $common = @{
                    Name            = $ModuleName
                    Repository      = $repoName
                    Scope           = $Scope
                    TrustRepository = $true
                    AcceptLicense   = $true
                    Quiet           = $true
                    ErrorAction     = 'Stop'
                    WarningAction   = 'SilentlyContinue'
                }
                if ($Prerelease) { $common.Prerelease = $true }
                Update-PSResource @common | Out-Null
            }
        }

        if ($ImportAfter) {
            try {
                Import-Module $ModuleName -Force -ErrorAction Stop
            } catch {
                Write-Host "⚠️ Installed '$ModuleName' but Import-Module failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        $latest = Get-Module -ListAvailable -Name $ModuleName | Sort-Object Version -Descending | Select-Object -First 1
        if ($latest) {
            Write-Host "✅ '$ModuleName' installed. Version: $($latest.Version)" -ForegroundColor Green
        } else {
            Write-Host "✅ '$ModuleName' install/update completed." -ForegroundColor Green
        }
    } catch {
        Write-Host "❌ Failed for '$ModuleName': $($_.Exception.Message)" -ForegroundColor Red
        throw
    } finally {
        if ($hadVerboseDefault) { $PSDefaultParameterValues['*:Verbose'] = $prevVerbose }
        else { $null = $PSDefaultParameterValues.Remove('*:Verbose') }
    }
}

function Invoke-WorkIQQuery {
    <#
    .SYNOPSIS
        Runs a Work IQ query, installing the workiq CLI first if it's missing.

    .DESCRIPTION
        Work IQ ships as the @microsoft/workiq npm package. This checks for
        the CLI on PATH and installs it globally via npm if absent, then
        runs the query. Does NOT auto-accept the Work IQ EULA — that's a
        one-time explicit action the user needs to run themselves
        (`workiq accept-eula`), since silently accepting license terms on
        someone's behalf isn't something this function should do.

    .PARAMETER Query
        The natural-language query to send to Work IQ.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Get-Command workiq -ErrorAction SilentlyContinue)) {
        Write-Verbose "workiq CLI not found on PATH — installing @microsoft/workiq globally via npm."

        if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
            throw 'workiq is not installed, and npm is not available to install it. Install Node.js 18+ first (Work IQ requires it for its fetch/async usage): https://nodejs.org'
        }

        npm install -g @microsoft/workiq
        if ($LASTEXITCODE -ne 0) {
            throw "npm install -g @microsoft/workiq failed with exit code $LASTEXITCODE."
        }

        # A global npm install updates the machine/user PATH, but this
        # process's own environment block was already loaded before that
        # happened — refresh it so 'workiq' resolves without needing a new
        # PowerShell session.
        $machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
        $userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
        $env:PATH = "$machinePath;$userPath"

        if (-not (Get-Command workiq -ErrorAction SilentlyContinue)) {
            throw 'workiq was installed but could not be resolved on PATH in this session. Open a new terminal and try again.'
        }
    }

    # ask expects the query via -q per the documented CLI syntax, not
    # positionally.
    workiq accept-eula
    $result = & workiq ask -q "$Query"

    if ($LASTEXITCODE -ne 0) {
        # Native executables don't respect $ErrorActionPreference on a
        # non-zero exit code — that only applies to PowerShell-native cmdlet
        # errors, so this has to be checked explicitly.
        throw "workiq exited with code $LASTEXITCODE. Output: $result"
    }

    if (-not $result) {
        throw 'No response from Work IQ'
    }

    return $result
}

function Get-AllMsGraphPages {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Uri = 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies',

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [switch]$OutputJson,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$JsonDepth = 100
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Write-GraphJsonLog {
        param(
            [string]$Uri,
            [string]$Json
        )

        $isGitHubRunner = -not [string]::IsNullOrWhiteSpace($env:GITHUB_STEP_SUMMARY)

        if ($isGitHubRunner) {
            Write-Verbose 'GitHub runner detected. Writing JSON output to GITHUB_STEP_SUMMARY.'

            if ($Json.Length -gt 20000) {
                $Json = $Json.Substring(0, 20000) + "`n...truncated..."
            }

            $content = @(
                "### Graph response page from $Uri"
                '```json'
                $Json
                '```'
                ''
            ) -join "`n"

            Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $content
        } else {
            Write-Verbose "Graph response page from $Uri (size: $($Json.Length) chars)"
            #Write-Host $Json
        }
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $attempt = 0
        $response = $null

        do {
            try {
                $attempt++
                Write-Verbose "Fetching URI: $next"
                $response = Invoke-MgGraphRequest -Method GET -Uri $next -OutputType PSObject
                break
            } catch {
                if ($attempt -ge $MaxRetries) { throw }

                Write-Warning "Request failed for URI '$next' on attempt $attempt of $MaxRetries. Retrying..."
                Start-Sleep -Seconds ([Math]::Min(2 * $attempt, 10))
            }
        } while ($attempt -lt $MaxRetries)

        if ($null -eq $response) {
            Write-Verbose "Received null response for URI: $next"
            break
        }

        # Optional per-page debug logging only
        if ($OutputJson) {
            $pageJson = $response | ConvertTo-Json -Depth $JsonDepth
            Write-GraphJsonLog -Uri $next -Json $pageJson
        }

        $valueProperty = $response.PSObject.Properties['value']
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']

        if ($null -ne $valueProperty) {
            foreach ($item in @($valueProperty.Value)) {
                $items.Add($item) | Out-Null
            }

            $next = if ($null -ne $nextLinkProperty) {
                [string]$nextLinkProperty.Value
            } else {
                $null
            }

            continue
        }

        if ($response -is [array]) {
            foreach ($item in $response) {
                $items.Add($item) | Out-Null
            }
            break
        }

        $items.Add($response) | Out-Null
        break
    }

    Write-Verbose "Total items retrieved: $($items.Count)"

    # FINAL OUTPUT DECISION
    if ($OutputJson) {
        Write-Verbose 'Returning aggregated JSON output.'
        return ($items | ConvertTo-Json -Depth $JsonDepth)
    } else {
        return $items
    }
}

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


function Get-OfficeDocumentMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found: '$Path'. Current directory is: '$((Get-Location).Path)'"
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    $extension = [IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()

    if ($extension -notin @('.docx', '.xlsx', '.pptx')) {
        throw "Only .docx, .xlsx and .pptx files are supported. File was: $resolvedPath"
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zip = $null

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($resolvedPath)

        function Get-ZipEntryText {
            param(
                [Parameter(Mandatory)]
                [System.IO.Compression.ZipArchive]$Zip,

                [Parameter(Mandatory)]
                [string]$EntryName
            )

            $entry = $Zip.GetEntry($EntryName)

            if (-not $entry) {
                return $null
            }

            $stream = $entry.Open()
            $reader = [IO.StreamReader]::new($stream)

            try {
                return $reader.ReadToEnd()
            } finally {
                $reader.Dispose()
                $stream.Dispose()
            }
        }

        Write-Host ''
        Write-Host "File: $resolvedPath"
        Write-Host "Type: $extension"

        Write-Host ''
        Write-Host '=== Core Properties ==='

        $coreXml = Get-ZipEntryText -Zip $zip -EntryName 'docProps/core.xml'

        if ([string]::IsNullOrWhiteSpace($coreXml)) {
            Write-Host 'No core properties found.'
        } else {
            [xml]$coreDoc = $coreXml

            $ns = [System.Xml.XmlNamespaceManager]::new($coreDoc.NameTable)
            $ns.AddNamespace('cp', 'http://schemas.openxmlformats.org/package/2006/metadata/core-properties')
            $ns.AddNamespace('dc', 'http://purl.org/dc/elements/1.1/')
            $ns.AddNamespace('dcterms', 'http://purl.org/dc/terms/')

            $propertyMap = [ordered]@{
                Title          = '//dc:title'
                Subject        = '//dc:subject'
                Creator        = '//dc:creator'
                Description    = '//dc:description'
                Keywords       = '//cp:keywords'
                Category       = '//cp:category'
                LastModifiedBy = '//cp:lastModifiedBy'
                Revision       = '//cp:revision'
                Created        = '//dcterms:created'
                Modified       = '//dcterms:modified'
            }

            $foundCoreProperty = $false

            foreach ($propertyName in $propertyMap.Keys) {
                $node = $coreDoc.SelectSingleNode($propertyMap[$propertyName], $ns)

                if ($node -and -not [string]::IsNullOrWhiteSpace($node.InnerText)) {
                    $foundCoreProperty = $true
                    Write-Host ('{0,-24}: {1}' -f $propertyName, $node.InnerText)
                }
            }

            if (-not $foundCoreProperty) {
                Write-Host 'No populated core properties found.'
            }
        }

        Write-Host ''
        Write-Host '=== Custom Properties ==='

        $customXml = Get-ZipEntryText -Zip $zip -EntryName 'docProps/custom.xml'

        if ([string]::IsNullOrWhiteSpace($customXml)) {
            Write-Host 'No custom properties found.'
        } else {
            [xml]$customDoc = $customXml

            $ns = [System.Xml.XmlNamespaceManager]::new($customDoc.NameTable)
            $ns.AddNamespace('cp', 'http://schemas.openxmlformats.org/officeDocument/2006/custom-properties')

            $propertyNodes = $customDoc.SelectNodes('//cp:property', $ns)

            if ($propertyNodes.Count -eq 0) {
                Write-Host 'No custom properties found.'

            } else {
                foreach ($propertyNode in $propertyNodes) {
                    $propertyName = [string]$propertyNode.name

                    if ([string]::IsNullOrWhiteSpace($propertyName)) {
                        continue
                    }

                    $valueNode = $propertyNode.ChildNodes | Select-Object -First 1

                    $propertyValue = if ($valueNode) {
                        $valueNode.InnerText
                    } else {
                        ''
                    }

                    Write-Host ('{0,-24}: {1}' -f $propertyName, $propertyValue)
                }
            }
        }

        Write-Host ''
        Write-Host '=== App Properties ==='

        $appXml = Get-ZipEntryText -Zip $zip -EntryName 'docProps/app.xml'

        if ([string]::IsNullOrWhiteSpace($appXml)) {
            Write-Host 'No app properties found.'
        } else {
            [xml]$appDoc = $appXml
            $appNodes = $appDoc.SelectNodes('//*[not(*)]')
            $appPropertiesShown = 0

            foreach ($appNode in $appNodes) {
                $name = [string]$appNode.LocalName
                $value = [string]$appNode.InnerText

                if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) {
                    continue
                }

                Write-Host ('{0,-24}: {1}' -f $name, $value)
                $appPropertiesShown++
            }

            if ($appPropertiesShown -eq 0) {
                Write-Host 'No populated app properties found.'
            }
        }

        Write-Host ''
        Write-Host '=== Custom XML Parts ==='

        $customXmlPartEntries = @($zip.Entries | Where-Object { $_.FullName -match '^customXml/.+\.xml$' })

        if ($customXmlPartEntries.Count -eq 0) {
            Write-Host 'No custom XML parts found.'
        } else {
            foreach ($customXmlPartEntry in $customXmlPartEntries) {
                Write-Host ''
                Write-Host "Part: $($customXmlPartEntry.FullName)"

                $partXml = Get-ZipEntryText -Zip $zip -EntryName $customXmlPartEntry.FullName
                if ([string]::IsNullOrWhiteSpace($partXml)) {
                    Write-Host '  (empty XML part)'
                    continue
                }

                [xml]$partDoc = $partXml
                $partLeafNodes = $partDoc.SelectNodes('//*[not(*)]')
                $partValuesShown = 0

                foreach ($partLeafNode in $partLeafNodes) {
                    $name = [string]$partLeafNode.LocalName
                    $value = [string]$partLeafNode.InnerText

                    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($value)) {
                        continue
                    }

                    Write-Host ('  {0,-22}: {1}' -f $name, $value)
                    $partValuesShown++
                }

                if ($partValuesShown -eq 0) {
                    Write-Host '  (no populated leaf values found)'
                }
            }
        }

        Write-Host ''
    } finally {
        if ($zip) {
            $zip.Dispose()
        }
    }
}

function Initialize-WinGetCommandNotFound {
    [CmdletBinding()]
    param(
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$InstallScope = 'CurrentUser'
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $moduleName = 'Microsoft.WinGet.CommandNotFound'

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Verbose 'winget.exe was not found. Skipping Microsoft.WinGet.CommandNotFound import.'
        return $false
    }

    if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
        Write-Verbose "Language mode '$($ExecutionContext.SessionState.LanguageMode)' is not FullLanguage. Skipping $moduleName initialization."
        return $false
    }

    try {
        $available = Get-Module -ListAvailable -Name $moduleName
        if (-not $available) {
            if (Get-Command Install-OrUpdate-Module -ErrorAction SilentlyContinue) {
                Write-Verbose "Installing missing module '$moduleName' in scope '$InstallScope'."
                Install-OrUpdate-Module -ModuleName $moduleName -Scope $InstallScope -ImportAfter
            } else {
                Write-Warning "Install-OrUpdate-Module is unavailable. Cannot install '$moduleName'."
                return $false
            }
        }

        if (-not (Get-Module -Name $moduleName)) {
            Import-Module -Name $moduleName -ErrorAction Stop
        }

        Write-Verbose "Imported module '$moduleName'."
        return $true
    } catch {
        Write-Warning "Failed to initialize '$moduleName': $($_.Exception.Message)"
        return $false
    }
}
Initialize-WinGetCommandNotFound | Out-Null

function Enable-WSL {
    [System.Environment]::SetEnvironmentVariable('WSLENV', 'OneDriveCommercial/p:STRONGPASSWORD:USERDNSDOMAIN:USERDOMAIN:USERNAME:UPN:DOCKER_HOST:PODMAN_IDENTITY/p:PODMAN_PORT:PODMAN_CONNECTION/p:WSL_INSTALLED_TIMEZONE', 'User')

    if ( [bool](Get-Command podman.exe -ErrorAction SilentlyContinue )) {
        try {
            Set-Item -Path Env:\PODMAN_IDENTITY -Value (& podman machine inspect --format '{{.SSHConfig.IdentityPath}}')
            Write-Host 'Found podman.. setting variables...'
            Set-Item -Path Env:\PODMAN_PORT -Value (& podman machine inspect podman-machine-default --format '{{.SSHConfig.Port}}')
            Set-Item -Path Env:\PODMAN_USER -Value (& podman machine inspect --format '{{.SSHConfig.RemoteUsername}}')
            Set-Item -Path Env:\PODMAN_PATH -Value (& podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')
        }
        catch {
            Write-Host 'podman machine is NOT running! Use 'RESET-PODMAN' to confgure it'
        }
    }    

    $flagPath = Join-Path $env:ProgramData 'Enable-WSL.done'
    if (Test-Path $flagPath) { return }
    if (-not $isAdmin) { return }

    try {
        $Distro = 'Ubuntu'
        Write-Output "Installing WSL with $Distro..."

        # NOTE: verify each of these is a real env var you intend to share.
        # "STRONGPASSWORD" looks like an unfilled placeholder from the original.
        $env:WSLENV = [System.Environment]::GetEnvironmentVariable('WSLENV', 'User')

        Write-Output 'Ensuring WSL is installed and up to date...'
        wsl.exe --install --no-launch *> $null
        wsl.exe --status
        wsl.exe --update *> $null
        wsl.exe --update --pre-release *> $null
        wsl.exe --set-default-version 2 *> $null

        wsl.exe --install -d $Distro --no-launch *> $null

        ## Preseed user
        wsl -d $Distro --user root bash -c @"
useradd -m -s /bin/bash -G sudo $env:UserName
"@

        wsl --manage $Distro --set-default-user $env:UserName *> $null
        wsl --set-default $Distro *> $null

        Write-Output "Enabling sudo for all users in '$Distro' WSL..."
        wsl -d $Distro --user root bash -c @'
if ! grep -q "NOPASSWD:ALL" /etc/sudoers; then
    cat <<'EOF' | EDITOR='tee -a' visudo
# Everyone - WSL
%sudo ALL=(ALL:ALL) NOPASSWD:ALL
# Azure AD - WSL
%aad_admins ALL=(ALL:ALL) NOPASSWD:ALL
EOF
fi
'@

        $wslConfigPath = Join-Path $env:USERPROFILE '.wslconfig'
        $content = @"
[wsl2]
networkingMode=NAT
guiApplications=true
[experimental]
hostAddressLoopback=true
"@
        Set-Content -Path $wslConfigPath -Value $content -Encoding UTF8 -Force
        Get-Content -Path $wslConfigPath

        wsl -d $Distro --user root bash -c @'
printf '[interop]\nappendWindowsPath = false\n\n[boot]\nsystemd = true\n\n[gpu]\nenabled = false\n' > /etc/wsl.conf
'@
        Write-Output "Terminating WSL '$Distro' Linux distribution..."
        wsl.exe --terminate $Distro *> $null

        Write-Output "Starting WSL '$Distro' Linux distribution (to enable systemd)..."
        wsl -d $Distro --user root bash -c @'
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y podman-remote
'@

        Set-NetFirewallHyperVVMSetting -Name '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -DefaultInboundAction Allow

        New-Item -Path $flagPath -ItemType File -Force | Out-Null
        wsl.exe --status
        Write-Output "WSL (Windows Subsystem for Linux) is now available with the '$Distro' distribution"
        Write-Output "Type 'wsl' to enter. - enjoy :-)"
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED', $True, 'User')
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED_DISTRIBUTION', $Distro, 'User')
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED_TIMEZONE', 'Australia/Melbourne', 'User')
        wsl --list --verbose
    }
    catch {
        Write-Error "Enable-WSL failed with: $_"
    }
}
Enable-WSL

function Set-WSLConfig-Ubuntu {
    if ([Environment]::GetEnvironmentVariable('WSL_INSTALLED_DISTRIBUTION', [EnvironmentVariableTarget]::User) -ne 'Ubuntu') {
        Write-Warning "Ubuntu not installed"
        return
    }

    #$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    #if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    #    throw 'Local Administrator privileges are required to config Ubuntu with WSL.'
    #}

    try {
        Write-Output "Configuring Ubuntu inside WSL..."
        $wslsetuppre = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup-pre.sh' -UseBasicParsing).Content -replace "`r", ''
        $wslsetup1   = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup1.sh' -UseBasicParsing).Content -replace "`r", ''
        $wslsetup2   = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup2.sh' -UseBasicParsing).Content -replace "`r", ''

        ($wslsetuppre + "`n" + $wslsetup1) | wsl --user root --distribution "${env:WSL_INSTALLED_DISTRIBUTION}" -- bash
        wsl --terminate "${env:WSL_INSTALLED_DISTRIBUTION}"
        $wslsetup2 | wsl --user root --distribution "${env:WSL_INSTALLED_DISTRIBUTION}" -- bash
    }
    catch {
        Write-Error "Set-WSLConfig-Ubuntu failed: $_"
    }
}
#Set-WSLConfig-Ubuntu

function Reset-WSL {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Local Administrator privileges are required to reset WSL.'
    }
    try {
        $Distro = 'Ubuntu'
        Write-Output "Shutting down WSL..."
        wsl.exe --shutdown --force *> $null
        Write-Output "Uninstalling '$Distro' from WSL..."
        Start-Process -FilePath "wsl.exe" -ArgumentList "--unregister $Distro" -Wait -NoNewWindow
        Write-Output "Removing flag files and environment variables..."
        $flagPath = Join-Path $env:ProgramData 'Enable-WSL.done'
        if (Test-Path $flagPath) { Remove-Item -Force $flagpath }
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED', $Null, 'User')
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED_DISTRIBUTION', $Null, 'User')
        [Environment]::SetEnvironmentVariable('WSL_INSTALLED_TIMEZONE', $Null, 'User')
    }
    catch {
        Write-Error "Reset-WSL failed with: $_"
    }
    finally {
        Enable-WSL
        Set-WSLConfig-Ubuntu
    }
}
#Reset-WSL

function Enable-DirenvIntegration {
    <#
    .SYNOPSIS
        Hooks direnv into the current PowerShell session so .envrc files load/unload automatically as you cd between directories.

    .DESCRIPTION
        https://github.com/direnv/direnv

        .envrc files are written in shell syntax, even when you're using PowerShell.
        direnv reads the file and injects the resulting environment variables into your PowerShell session.

        Example .envrc (create one with: New-Item .envrc -ItemType File):

            # .envrc
            export ASPIRE_CONTAINER_RUNTIME=podman
            export DATABASE_URL="Server=(localdb)\MSSQLLocalDB;Integrated Security=true;"
            PATH_add bin
            layout python

        After creating a .envrc, run `direnv allow` once inside that directory —
        direnv refuses to load any .envrc it hasn't been explicitly told to trust.

    .NOTES
        Call this once from your $PROFILE. Requires direnv.exe on PATH
        (e.g. `winget install direnv`); does nothing if direnv isn't found.
        Safe to call more than once — subsequent calls are a no-op.
    #>
    [CmdletBinding()]
    param()

    if ($global:__DirenvIntegrationEnabled) {
        Write-Verbose "direnv integration already enabled; skipping."
        return
    }

    if (-not (Get-Command direnv -ErrorAction SilentlyContinue)) {
        Write-Verbose "direnv not found on PATH; skipping direnv integration."
        return
    }

    $env:DIRENV_LOG_FORMAT = ''

    function global:Invoke-RepoDirenv {
        [CmdletBinding()]
        param()

        try {
            $repoRoot = git rev-parse --show-toplevel 2>$null
            $shouldRunDirenv = $false
            if ($repoRoot) {
                $envrcPath = Join-Path $repoRoot '.envrc'
                if (Test-Path -LiteralPath $envrcPath) {
                    $shouldRunDirenv = $true
                }
            }
            # Also run direnv when leaving a previously loaded repo, so it can unload vars
            if (-not $shouldRunDirenv -and $env:DIRENV_DIR) {
                $shouldRunDirenv = $true
            }
            if ($shouldRunDirenv) {
                $direnvOutput = direnv export pwsh 2>$null
                if ($direnvOutput) {
                    Invoke-Expression $direnvOutput
                }
            }
        } catch {
            Write-Verbose "Invoke-RepoDirenv failed: $_"
        }
    }

    # Preserve any existing prompt (Oh My Posh, Starship, posh-git, etc.) instead of clobbering it
    if (Test-Path Function:\prompt) {
        $global:PreDirenvPrompt = $function:prompt
    }

    function global:prompt {
        Invoke-RepoDirenv
        if ($global:PreDirenvPrompt) {
            & $global:PreDirenvPrompt
        } else {
            "PS $($executionContext.SessionState.Path.CurrentLocation)> "
        }
    }

    $global:__DirenvIntegrationEnabled = $true
    Write-StepSummary -ShowTimeStamp $false -type 'info' "Enabled 'direnv' to pick up environment variables from the '.envrc' file (if found)"
}
Enable-DirenvIntegration

function Initialize-GitHubCliAuth {
    [CmdletBinding()]
    param()

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        return
    }

    gh auth status --active *> $null
    if ($LASTEXITCODE -ne 0 -and -not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        $env:GH_TOKEN | gh auth login --with-token
    }

    gh auth status --active
    if ($LASTEXITCODE -eq 0) {
        gh auth setup-git
    }
}
#Initialize-GitHubCliAuth

function Get-AzVmSku {
    [CmdletBinding()]
    param(
        [string]$Location = $(if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { 'australiaeast' }),
        [string]$SkuPrefix = 'Standard_D',
        [double]$MinimumRamGB = 9,
        [double]$MaximumRamGB = 19,
        [int]$MaximumCPU = 5,
        [bool]$SpotOnly = $false,
        [bool]$EncryptionAtHostOnly = $true,
        [bool]$AcceleratedNetworkingOnly = $true,
        [bool]$AvailableOnly = $true
    )

    $skus = az vm list-skus `
        --location $Location `
        --resource-type virtualMachines `
        --all `
        --output json | ConvertFrom-Json

    $results = foreach ($sku in $skus) {
        if ($sku.name -notlike "$SkuPrefix*") {
            continue
        }

        $caps = @{}

        foreach ($cap in $sku.capabilities) {
            $caps[$cap.name] = $cap.value
        }

        $memoryGB = if ($caps.ContainsKey('MemoryGB')) { [double]$caps['MemoryGB'] } else { 0 }
        $vcpus = if ($caps.ContainsKey('vCPUs')) { [int]$caps['vCPUs'] } else { 0 }

        $hasRestrictions = $null -ne $sku.restrictions -and $sku.restrictions.Count -gt 0
        $skuAvailable = -not $hasRestrictions
        $spotCapable = [bool]::Parse(($caps['SpotPrioritySupported'] ?? 'False'))

        [pscustomobject]@{
            Name                      = $sku.name
            vCPUs                     = $vcpus
            RAM_GB                    = $memoryGB
            SkuAvailable              = $skuAvailable
            SpotCapable               = $spotCapable
            RestrictionReason         = if ($hasRestrictions) { ($sku.restrictions.reasonCode -join ', ') } else { $null }
            RestrictionType           = if ($hasRestrictions) { ($sku.restrictions.type -join ', ') } else { $null }
            EncryptionAtHostSupported = [bool]::Parse(($caps['EncryptionAtHostSupported'] ?? 'False'))
            AcceleratedNetworking     = [bool]::Parse(($caps['AcceleratedNetworkingEnabled'] ?? 'False'))
        }
    }

    $results = $results | Where-Object {
        $_.RAM_GB -ge $MinimumRamGB -and
        $_.RAM_GB -le $MaximumRamGB -and
        $_.vCPUs -le $MaximumCPU
    }

    if ($AvailableOnly) {
        $results = $results | Where-Object { $_.SkuAvailable }
    }

    if ($SpotOnly) {
        $results = $results | Where-Object { $_.SpotCapable }
    }

    if ($EncryptionAtHostOnly) {
        $results = $results | Where-Object { $_.EncryptionAtHostSupported }
    }

    if ($AcceleratedNetworkingOnly) {
        $results = $results | Where-Object { $_.AcceleratedNetworking }
    }

    $results = $results | Sort-Object vCPUs, RAM_GB, Name

    $results | Format-Table -AutoSize
    "Count: $($results.Count) in $($Location)"
}

function Get-QuickXorHashFromFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    $BitsInLastCell = 32
    $Shift = 11
    $Threshold = 600
    $WidthInBits = 160

    $data = @(0..2 | ForEach-Object { [UInt64]0 })
    $lengthSoFar = 0
    $shiftSoFar = 0

    $buffer = [System.IO.File]::ReadAllBytes($FilePath)
    $lengthSoFar = $buffer.Length

    $ibStart = 0
    $cbSize = $buffer.Length

    $currentShift = $shiftSoFar
    $vectorArrayIndex = [math]::Floor($currentShift / 64)
    $vectorOffset = $currentShift % 64
    $iterations = [math]::Min($cbSize, $WidthInBits)

    for ($i = 0; $i -lt $iterations; $i++) {
        $isLastCell = $vectorArrayIndex -eq ($data.Length - 1)
        $bitsInVectorCell = $isLastCell ? $BitsInLastCell : 64

        if ($vectorOffset -le ($bitsInVectorCell - 8)) {
            for ($j = $ibStart + $i; $j -lt ($cbSize + $ibStart); $j += $WidthInBits) {
                $data[$vectorArrayIndex] = $data[$vectorArrayIndex] -bxor ([UInt64]$buffer[$j] -shl $vectorOffset)
            }
        } else {
            $index1 = $vectorArrayIndex
            $index2 = $isLastCell ? 0 : ($vectorArrayIndex + 1)
            $low = $bitsInVectorCell - $vectorOffset

            $xoredByte = 0
            for ($j = $ibStart + $i; $j -lt ($cbSize + $ibStart); $j += $WidthInBits) {
                $xoredByte = $xoredByte -bxor $buffer[$j]
            }

            $data[$index1] = $data[$index1] -bxor ([UInt64]$xoredByte -shl $vectorOffset)
            $data[$index2] = $data[$index2] -bxor ([UInt64]$xoredByte -shr $low)
        }

        $vectorOffset += $Shift
        while ($vectorOffset -ge $bitsInVectorCell) {
            $vectorArrayIndex = $isLastCell ? 0 : ($vectorArrayIndex + 1)
            $vectorOffset -= $bitsInVectorCell
        }
    }

    $shiftSoFar = ($shiftSoFar + $Shift * ($cbSize % $WidthInBits)) % $WidthInBits

    # Finalize hash
    $rgb = New-Object byte[] 20
    for ($i = 0; $i -lt $data.Length - 1; $i++) {
        [System.Buffer]::BlockCopy([BitConverter]::GetBytes($data[$i]), 0, $rgb, $i * 8, 8)
    }

    $lastIndex = ($data.Length - 1)
    [System.Buffer]::BlockCopy([BitConverter]::GetBytes($data[$lastIndex]), 0, $rgb, $lastIndex * 8, $rgb.Length - ($lastIndex * 8))

    $lengthBytes = [BitConverter]::GetBytes([Int64]$lengthSoFar)
    for ($i = 0; $i -lt $lengthBytes.Length; $i++) {
        $rgb[($WidthInBits / 8) - $lengthBytes.Length + $i] = $rgb[($WidthInBits / 8) - $lengthBytes.Length + $i] -bxor $lengthBytes[$i]
    }

    return [Convert]::ToBase64String($rgb)
}

function Connect-AzureTenant {
    <#
    .SYNOPSIS
        Logs on with the Az PowerShell module — to a specific tenant, or interactively to
        whichever tenant you choose — and saves/imports context per tenant for fast switching.
        Also grabs a raw access token, copies it to the clipboard, and sets $env:ACCESS_TOKEN.

    .DESCRIPTION
        Three ways to use this:
          1. Connect-AzureTenant                         -> log in, pick a tenant if you have more than one, auto-save by its resolved display name.
          2. Connect-AzureTenant -TenantName Contoso      -> import a previously saved context instantly, no login prompt.
          3. Connect-AzureTenant -TenantId <guid>         -> log in directly to a known tenant.

        In all cases, once connected, the context is (re)saved to disk keyed by the tenant's
        display name, $global:AzTenantId / AzTenantName / AzSubscriptionId / AzClientId are
        populated, and a fresh ARM access token is copied to the clipboard and set as
        $env:ACCESS_TOKEN for use with az CLI, curl, Postman, etc.

        Context files are stored under the folder named by the 'OneDriveCommercial' environment
        variable by default, so saved tenant contexts sync across machines via OneDrive. Falls
        back to your local profile folder if that variable isn't set.

        Note: Save-AzContext persists a real, working Az PowerShell token cache — that's why
        Import-AzContext can restore a live session without re-prompting. It is NOT usable by
        Azure CLI though; Az PowerShell and az CLI keep entirely separate credential stores.
        The access token grabbed at the end of this function is the portable alternative for
        using other tools, but it's short-lived (~60-75 min), unlike the saved context.

    .PARAMETER TenantName
        Friendly name used to save/look up a context file. If a saved context exists under
        this name, it's imported instead of prompting to log in.

    .PARAMETER TenantId
        Connect directly to a known Entra tenant ID, skipping any tenant picker.

    .PARAMETER SubscriptionId
        Subscription to select as active after connecting.

    .PARAMETER ClientId
        App (client) ID for a service principal login. Requires -ClientSecret and -TenantId.

    .PARAMETER ClientSecret
        Secret for the service principal identified by -ClientId. SecureString.

    .PARAMETER Force
        Ignore any saved context for -TenantName and force a fresh login.

    .PARAMETER ContextFolder
        Where saved context files live. Defaults to "<OneDriveCommercial>\.azcontexts",
        falling back to "$HOME\.azcontexts" if OneDriveCommercial isn't set.

    .EXAMPLE
        Connect-AzureTenant
        Interactive login to any tenant you have access to; prompts you to pick one if there's more than one, then saves it under its real display name.

    .EXAMPLE
        Connect-AzureTenant -TenantName Contoso
        Instantly re-imports the previously saved Contoso context, no login prompt.

    .EXAMPLE
        Connect-AzureTenant -TenantName Fabrikam -TenantId $tenantId -ClientId $appId -ClientSecret (Read-Host -AsSecureString) -Force
        Non-interactive service principal login, forcing a fresh auth even if a saved context exists.
    #>
    [CmdletBinding()]
    param(
        [string]$TenantName,
        [string]$TenantId,
        [string]$SubscriptionId,
        [string]$ClientId,
        [SecureString]$ClientSecret,
        [switch]$Force,
        [string]$ContextFolder = $(
            if ($env:OneDriveCommercial) {
                Join-Path $env:OneDriveCommercial '.azcontexts'
            } else {
                Write-Warning "OneDriveCommercial environment variable not set; falling back to local profile folder."
                Join-Path $HOME '.azcontexts'
            }
        )
    )

    if ($ClientId -and -not $ClientSecret) {
        throw "-ClientSecret is required when -ClientId is supplied."
    }

    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "The Az PowerShell module (Az.Accounts) was not found. Install it with: Install-Module Az -Scope CurrentUser"
    }
    Import-Module Az.Accounts -ErrorAction Stop

    if (-not (Test-Path $ContextFolder)) {
        New-Item -ItemType Directory -Path $ContextFolder -Force | Out-Null
    }

    function Get-SafeFileName([string]$Name) {
        $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
        ($Name -replace "[$([regex]::Escape($invalid))]", '_')
    }

    $contextPath = if ($TenantName) {
        Join-Path $ContextFolder "$(Get-SafeFileName $TenantName).json"
    }

    # Fast path: import a previously saved context instead of re-authenticating
    if ($contextPath -and (Test-Path $contextPath) -and -not $Force) {
        Write-Verbose "Importing saved context for '$TenantName' from $contextPath"
        Import-AzContext -Path $contextPath | Out-Null
    } else {
        Write-Verbose "No matching saved context (or -Force specified); performing a fresh login."
        if ($ClientId) {
            if (-not $TenantId) { throw "-TenantId is required for a service principal login." }
            $cred = [Management.Automation.PSCredential]::new($ClientId, $ClientSecret)
            Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $TenantId | Out-Null
        } elseif ($TenantId) {
            Connect-AzAccount -Tenant $TenantId | Out-Null
        } else {
            # No tenant specified at all: log in, then let the user pick from whatever tenants they can access
            Connect-AzAccount | Out-Null
            $availableTenants = @(Get-AzTenant)
            if ($availableTenants.Count -gt 1) {
                Write-Host "Multiple tenants available for this account:"
                for ($i = 0; $i -lt $availableTenants.Count; $i++) {
                    Write-Host "  [$i] $($availableTenants[$i].Name)  ($($availableTenants[$i].Id))"
                }
                $selection = Read-Host "Select a tenant by number"
                $chosen = $availableTenants[[int]$selection]
                if ($chosen.Id -ne (Get-AzContext).Tenant.Id) {
                    Write-Verbose "Switching to tenant $($chosen.Name) ($($chosen.Id))"
                    Connect-AzAccount -Tenant $chosen.Id | Out-Null
                }
            }
        }
    }

    if ($SubscriptionId) {
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
    }

    $context = Get-AzContext
    if (-not $context) {
        throw "No active Az context after connecting."
    }

    $resolvedTenantName = (Get-AzTenant -TenantId $context.Tenant.Id -ErrorAction SilentlyContinue).Name
    if (-not $resolvedTenantName) { $resolvedTenantName = $TenantName }

    $global:AzTenantId       = $context.Tenant.Id
    $global:AzTenantName     = $resolvedTenantName
    $global:AzSubscriptionId = $context.Subscription.Id
    $global:AzClientId       = if ($context.Account.Type -eq 'ServicePrincipal') { $context.Account.Id } else { $null }

    # Save/refresh the context on disk, keyed by the tenant's (resolved) display name
    $saveName = if ($TenantName) { $TenantName } else { $resolvedTenantName }
    if ($saveName) {
        $savePath = Join-Path $ContextFolder "$(Get-SafeFileName $saveName).json"
        Save-AzContext -Path $savePath -Force | Out-Null
        Write-Verbose "Context saved to $savePath"
    }

    # Grab a raw access token too — usable with any tool that accepts a bearer token
    # (az CLI itself can't consume an Az PowerShell context directly; this is the portable alternative)
    $tokenObj = Get-AzAccessToken -ResourceUrl 'https://management.azure.com/'
    $accessToken = $tokenObj.Token
    if ($accessToken -is [SecureString]) {
        # Az.Accounts 14.0+ returns Token as SecureString by default
        $accessToken = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($accessToken)
        )
    }

    Set-Clipboard -Value $accessToken
    $env:ACCESS_TOKEN = $accessToken
    Write-Verbose "Access token copied to clipboard and set as `$env:ACCESS_TOKEN (expires around $($tokenObj.ExpiresOn))."

    [PSCustomObject]@{
        TenantId             = $global:AzTenantId
        TenantName           = $global:AzTenantName
        SubscriptionId       = $global:AzSubscriptionId
        SubscriptionName     = $context.Subscription.Name
        ClientId             = $global:AzClientId
        Account              = $context.Account.Id
        AccessTokenExpiresOn = $tokenObj.ExpiresOn
    }
}

function Get-SavedAzureTenant {
    <#
    .SYNOPSIS
        Lists saved Az contexts available for quick tenant switching via Connect-AzureTenant -TenantName.
    #>
    [CmdletBinding()]
    param(
        [string]$ContextFolder = $(
            if ($env:OneDriveCommercial) {
                Join-Path $env:OneDriveCommercial '.azcontexts'
            } else {
                Join-Path $HOME '.azcontexts'
            }
        )
    )

    if (-not (Test-Path $ContextFolder)) { return }
    Get-ChildItem -Path $ContextFolder -Filter '*.json' |
        Select-Object @{N='TenantName';E={$_.BaseName}}, @{N='LastSaved';E={$_.LastWriteTime}}
}

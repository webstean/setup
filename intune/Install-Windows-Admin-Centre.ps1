#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AzureVmTags {
    [CmdletBinding()]
    param()

    $tagsUrl  = 'http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01'
    $headers  = @{ Metadata = 'true' }

    try {
        $tags = Invoke-RestMethod -Uri $tagsUrl -Method GET -Headers $headers -NoProxy -TimeoutSec 3
        if (-not $tags) { return @() }

        # Return structured objects (better than Write-Host)
        return $tags | ForEach-Object {
            [pscustomobject]@{ Name = $_.name; Value = $_.value }
        }
    }
    catch {
        Write-Warning "Failed to query Azure IMDS tags: $($_.Exception.Message)"
        return @()
    }
}

function Test-IsRunningInAzure {
    [CmdletBinding()]
    param()

    $instanceUrl = 'http://169.254.169.254/metadata/instance?api-version=2021-02-01'
    $headers     = @{ Metadata = 'true' }

    try {
        $r = Invoke-RestMethod -Uri $instanceUrl -Method GET -Headers $headers -NoProxy -TimeoutSec 3
        return [bool]$r.compute.azEnvironment
    }
    catch {
        return $false
    }
}

function Install-WindowsAdminCenter {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateRange(1,65535)]
        [int]$WacPort = 8443,

        [Parameter()]
        [string]$DownloadUrl = 'https://aka.ms/WACDownload'
    )

    # Ensure TLS 1.2 for older Windows PowerShell environments (harmless in PS7)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $destinationFolder = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath 'WAC'
    $installerPath     = Join-Path -Path $destinationFolder -ChildPath 'WindowsAdminCenter.exe'
    $logPath           = Join-Path -Path $destinationFolder -ChildPath 'WindowsAdminCenter.log'
    $infPath           = Join-Path -Path $destinationFolder -ChildPath 'WindowsAdminCenter.inf'

    if (-not (Test-Path -Path $destinationFolder -PathType Container)) {
        New-Item -Path $destinationFolder -ItemType Directory | Out-Null
    }

    Write-Host "Downloading Windows Admin Center installer to $installerPath..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $installerPath

    Write-Host "Creating self-signed certificate for HTTPS..."
    $certSubject = 'CN=WindowsAdminCenter'
    $cert = New-SelfSignedCertificate -DnsName @('localhost') `
        -Subject $certSubject `
        -CertStoreLocation 'Cert:\LocalMachine\My' `
        -FriendlyName 'WAC Self-Signed'

    $thumbprint = $cert.Thumbprint

    # Trust it locally (so browser doesn't scream on the local machine)
    Write-Host "Adding certificate to Trusted Root Certification Authorities..."
    $rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root','LocalMachine')
    $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $rootStore.Add($cert)
    $rootStore.Close()

    Write-Host "Installing Windows Admin Center..."
    $args = @(
        "/log=$logPath",
        "/verysilent",
        "/NOICONS",
        "/NOCANCEL",
        "/NORESTART",
        "/SAVEINF=$infPath",
        "/SSL_CERTIFICATE_HASH=$thumbprint",
        "SME_PORT=$WacPort"
    )

    $process = Start-Process -FilePath $installerPath -ArgumentList $args -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "WAC installer failed with exit code $($process.ExitCode). See log: $logPath"
    }

    Write-Host "✅ Windows Admin Center installed on https://localhost:$WacPort"

    # Configure if module exists
    $configModule = 'C:\Program Files\WindowsAdminCenter\PowerShellModules\Microsoft.WindowsAdminCenter.Configuration'
    if (Test-Path $configModule) {
        Import-Module $configModule -Force

        # Configure WAC
        Set-WACWinRmTrustedHosts -TrustAll
        Set-WACHttpsPorts -WacPort $WacPort -ServicePortRangeStart 6601 -ServicePortRangeEnd 6610
        Set-WACSoftwareUpdateMode -Mode Automatic
        Register-WACFirewallRule -Port $WacPort
        Restart-WACService

        Write-Host "✅ Windows Admin Center configured successfully."
    }
    else {
        Write-Warning "WAC configuration module not found at expected path: $configModule"
    }

    return [pscustomobject]@{
        Installed     = $true
        Url           = "https://localhost:$WacPort"
        LogPath       = $logPath
        InfPath       = $infPath
        CertThumbprint= $thumbprint
    }
}

# --- Main ---

if (Test-IsRunningInAzure) {
    Write-Warning "⚠️ This computer is running inside Azure - skipping Windows Admin Center install (use the Azure extension instead)."

    $tags = Get-AzureVmTags
    if ($tags.Count -gt 0) {
        Write-Host "✅ Azure Tags assigned to this VM:"
        $tags | Format-Table -AutoSize
    } else {
        Write-Host "No Azure VM tags returned."
    }

    return $true
}

# Install WAC locally (non-Azure)
Install-WindowsAdminCenter -WacPort 8443


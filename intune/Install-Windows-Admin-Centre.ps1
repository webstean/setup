#Requires -RunAsAdministrator

function Get-AzureVMTags {
    # Azure IMDS endpoint
    $metadataUrl = "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01"

    # Set required header
    $headers = @{ "Metadata" = "true" }

    # Query the metadata service
    $response = Invoke-RestMethod -Uri $metadataUrl -Method GET -Headers $headers -NoProxy

    # Output tags
    if ($response) {
        Write-Host "✅ Azure Tags assigned to this VM are:`n"
        foreach ($tag in $response) {
            Write-Host ("{0,-20}: {1}" -f $tag.name, $tag.value) | Format-Table
        }
    }
    else {
        Write-Warning "⚠️ No tags found or failed to query metadata service."
    }
}

# Check if we are inside Azure, and exit if we are
$metadataUrl = "http://169.254.169.254/metadata/instance?api-version=2021-02-01"
$response = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method GET -Uri $metadataUrl -ErrorAction Ignore | ConvertTo-Json -Depth 64
if ($response | ConvertFrom-Json -ErrorAction SilentlyContinue | Select-Object -ExpandProperty compute -ErrorAction SilentlyContinue | Get-Member -Name azEnvironment -MemberType NoteProperty -ErrorAction SilentlyContinue) {
    Write-Warning "⚠️ This computer is running inside Azure - so skipping Windows Admin Center install (use an Azure extension instead)"
    Get-AzureVMTags
    return $true
}

$downloadUrl = "https://aka.ms/WACDownload"
$destinationFolder = [IO.Path]::GetTempPath() + "WAC"
## Check if the destination folder exists, create it if it doesn't
if (-not (Test-Path -Path $destinationFolder -PathType Container)) {
    New-Item -Path $destinationFolder -ItemType Directory | Out-Null
}
$installerPath = "$destinationFolder\WindowsAdminCenter.exe"
$certSubject = "CN=WindowsAdminCenter"
$wacPort = 8443  # You can change this (e.g., 6516 or 6600)

## Manage firewall here

# 1. Download WAC installer
Write-Host "Downloading Windows Admin Center installer to $installerPath..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# 2. Create a self-signed certificate

$moduleFiles = Get-ChildItem -Include @("*.psm1", "*.psd1") -Recurse -Path `
("C:\Users\ANDREW~1\AppData\Local\Temp\is-0EO0O.tmp" `
+ "\{app}\PowerShellModules")
$tempPath = [System.IO.Path]::GetTempFileName()
foreach ($moduleFile in $moduleFiles) {
  $signature = Get-AuthenticodeSignature -FilePath $moduleFile.FullName
  if ($signature.Status -ne "Valid") { continue }
  $signer = $signature.SignerCertificate
  $chain = New-Object -TypeName `
  "System.Security.Cryptography.X509Certificates.X509Chain"
  $chain.Build($signer)
  $signerCA = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
  $signerCA | Export-Certificate -FilePath $tempPath -Type CERT
  Import-Certificate -FilePath $tempPath -CertStoreLocation `
  "Cert:\LocalMachine\Root"
  $signer | Export-Certificate -FilePath $tempPath -Type CERT
  Import-Certificate -FilePath $tempPath -CertStoreLocation `
  "Cert:\LocalMachine\TrustedPublisher"
}
Remove-Item -Path $tempPath -Force


Write-Host "Creating self-signed certificate for HTTPS..."
$cert = New-SelfSignedCertificate -DnsName "localhost" -Subject $certSubject -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "WAC Self-Signed"

# 3. Get certificate thumbprint
$thumbprint = $cert.Thumbprint

# 3a. Add certificate to Trusted Root Certification Authorities so the machine trusts it
Write-Host "Adding certificate to Trusted Root Certification Authorities..."
$rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root","LocalMachine")
$rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
$rootStore.Add($cert)
$rootStore.Close()

# 4. Install Windows Admin Center silently
        # Import module and signer CA certificates for WAC PowerShell modules before install (if present)
        $wacModulePath = "C:\Program Files\WindowsAdminCenter\PowerShellModules"
        if (Test-Path $wacModulePath) {
            $moduleFiles = Get-ChildItem -Include @("*.psm1", "*.psd1") -Recurse -Path $wacModulePath
            $tempPath = [System.IO.Path]::GetTempFileName()
            foreach ($moduleFile in $moduleFiles) {
                $signature = Get-AuthenticodeSignature -FilePath $moduleFile.FullName
                if ($signature.Status -ne "Valid") { continue }
                $signer = $signature.SignerCertificate
                $chain = New-Object -TypeName "System.Security.Cryptography.X509Certificates.X509Chain"
                $chain.Build($signer) | Out-Null
                $signerCA = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
                $signerCA | Export-Certificate -FilePath $tempPath -Type CERT
                Import-Certificate -FilePath $tempPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
                $signer | Export-Certificate -FilePath $tempPath -Type CERT
                Import-Certificate -FilePath $tempPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
            }
            Remove-Item -Path $tempPath -Force
        }
        Write-Host "Installing Windows Admin Center..."
try {
    $process = Start-Process $installerPath -Wait -PassThru -ArgumentList @(
        "/log=$destinationFolder\WindowsAdminCenter.log",
        "/SSL_CERTIFICATE_HASH=$thumbprint",
        "/verysilent",
        "/SAVEINF=$destinationFolder\WindowsAdminCenter.inf",
        "/NOICONS",
        "/NOCANCEL",
        "/NORESTART"
    ) -ErrorAction Stop
    if ($process.ExitCode -eq 0) {
        Write-Host "`n✅ Windows Admin Center installed on https://localhost:$wacPort"

        if (Test-Path 'C:\Program Files\WindowsAdminCenter\PowerShellModules\Microsoft.WindowsAdminCenter.Configuration') {
            Import-Module 'C:\Program Files\WindowsAdminCenter\PowerShellModules\Microsoft.WindowsAdminCenter.Configuration'
            Set-WACWinRmTrustedHosts -TrustAll
            Set-WACHttpsPorts -WacPort $wacPort -ServicePortRangeStart 6601 -ServicePortRangeEnd 6610
            Set-WACSoftwareUpdateMode -Mode "Automatic"
            ## New-WACSelfSignedCertificate -Trust
            ## Set-WACLoginMode -Mode "AadSso"
            Register-WACFirewallRule -Port $wacPort
            Restart-WACService
            Write-Host "✅ Windows Admin Center configured successfully."

            # Import module and signer CA certificates for WAC PowerShell modules
            $moduleFiles = Get-ChildItem -Include @("*.psm1", "*.psd1") -Recurse -Path ("C:\Program Files\WindowsAdminCenter\PowerShellModules")
            $tempPath = [System.IO.Path]::GetTempFileName()
            foreach ($moduleFile in $moduleFiles) {
                $signature = Get-AuthenticodeSignature -FilePath $moduleFile.FullName
                if ($signature.Status -ne "Valid") { continue }
                $signer = $signature.SignerCertificate
                $chain = New-Object -TypeName "System.Security.Cryptography.X509Certificates.X509Chain"
                $chain.Build($signer) | Out-Null
                $signerCA = $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
                $signerCA | Export-Certificate -FilePath $tempPath -Type CERT
                Import-Certificate -FilePath $tempPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
                $signer | Export-Certificate -FilePath $tempPath -Type CERT
                Import-Certificate -FilePath $tempPath -CertStoreLocation "Cert:\LocalMachine\TrustedPublisher" | Out-Null
            }
            Remove-Item -Path $tempPath -Force
        }
    } else {
        Write-Host "❌ Installation failed with exit code $($process.ExitCode). See log at $destinationFolder\WindowsAdminCenter.log."
    }
} catch {
    Write-Host "❌ Failed to start installation process: $_"
}
#    "SME_PORT=$wacPort",

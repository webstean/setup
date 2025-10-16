#Requires -RunAsAdministrator

function Get-AzureVMTags {
    # Azure IMDS endpoint
    $metadataUrl = "http://169.254.169.254/metadata/instance/compute/tagsList?api-version=2021-02-01"

    # Set required header
    $headers = @{ "Metadata" = "true" }

    # Query the metadata service
    $response = Invoke-RestMethod -Uri $metadataUrl -Method GET -Headers $headers

    # Output tags
    if ($response) {
        Write-Host "✅ Azure Tags assigned to this VM:`n"
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
$response = Invoke-RestMethod -Headers @{"Metadata" = "true" } -Method GET -Uri $metadataUrl | ConvertTo-Json -Depth 64
if ($response | ConvertFrom-Json | Select-Object -ExpandProperty compute -ErrorAction SilentlyContinue | Get-Member -Name azEnvironment -MemberType NoteProperty -ErrorAction SilentlyContinue) {
    Write-Warning "⚠️ This computer is running inside Azure, so skipping Windows Admin Center install (use an Azure extension insteand)"
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
$wacPort = 443  # You can change this (e.g., 6516 or 6600)

# 1. Download WAC installer
Write-Host "Downloading Windows Admin Center installer to $installerPath..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

# 2. Create a self-signed certificate
Write-Host "Creating self-signed certificate for HTTPS..."
$cert = New-SelfSignedCertificate -DnsName "localhost" -Subject $certSubject -CertStoreLocation "Cert:\LocalMachine\My" -FriendlyName "WAC Self-Signed"

# 3. Get certificate thumbprint
$thumbprint = $cert.Thumbprint

# 4. Install Windows Admin Center silently
Write-Host "Installing Windows Admin Center..."
Start-Process $installerPath -Wait -ArgumentList @(
    "/log=$destinationFolder\WindowsAdminCenter.log",
    "/verysilent",
    "/SAVEINF=$destinationFolder\WindowsAdminCenter.inf",
    "/NOICONS",
    "/NOCANCEL",
    "/NORESTART"
)
#    "SME_PORT=$wacPort",
#    "SSL_CERTIFICATE_HASH=$thumbprint"

## Write-Host "`n✅ Windows Admin Center installed on https://localhost:$wacPort"

if (Test-Path 'C:\Program Files\WindowsAdminCenter\PowerShellModules\Microsoft.WindowsAdminCenter.Configuration') {
    Import-Module 'C:\Program Files\WindowsAdminCenter\PowerShellModules\Microsoft.WindowsAdminCenter.Configuration'
    Set-WACWinRmTrustedHosts -TrustAll
    Set-WACHttpsPorts -WacPort $wacPort -ServicePortRangeStart 6601 -ServicePortRangeEnd 6610
    Set-WACSoftwareUpdateMode -Mode "Automatic"
    ## New-WACSelfSignedCertificate -Trust
    ## Set-WACLoginMode -Mode "AadSso"
    Register-WACFirewallRule -Port $wacPort
    Restart-WACService
}

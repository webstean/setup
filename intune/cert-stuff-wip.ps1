function New-CodeSigningCertificate {
    <#
    .SYNOPSIS
        Creates (or reuses) a self-signed code signing certificate, ensures the PFX/CER files exist
        and, by default, that the certificate is trusted. Safe to run repeatedly.
    .EXAMPLE
        $cert = New-CodeSigningCertificate -CertName 'MyCodeSigningCert'
        Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert `
            -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
    .NOTES
        Self-signed: only trusted on machines where the CER is installed (-Trust does this locally).
        The PFX contains the private key. Do not leave it in a synced folder such as OneDrive
        unless that is a deliberate choice.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [ValidateNotNullOrEmpty()]
        [string]$CertName = 'MyCodeSigningCert',

        # Falls back to $env:STRONGPASSWORD, then to an interactive prompt. Only needed when a PFX is written.
        [System.Security.SecureString]$PfxPassword,

        # $env:OneDriveCommercial can be unset, which breaks Join-Path, so fall back to Documents.
        [string]$OutputPath = $(
            if ($env:OneDriveCommercial) { $env:OneDriveCommercial }
            else { [Environment]::GetFolderPath('MyDocuments') }
        ),

        [ValidateRange(1, 10)]
        [int]$CertYears = 2,

        # LocalMachine requires an elevated session.
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope = 'CurrentUser',

        # Ensure the certificate is trusted (Root + TrustedPublisher) in the chosen scope.
        # Only missing entries are imported. Default $true; use -Trust $false to skip.
        [bool]$Trust = $true,

        # Create a new certificate even if a valid one already exists.
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    if ($Scope -eq 'LocalMachine') {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
            IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) { throw "Scope 'LocalMachine' requires an elevated session." }
    }

    $subject = "CN=$CertName"
    $myStore = "Cert:\$Scope\My"
    $pfxPath = Join-Path $OutputPath "$CertName.pfx"
    $cerPath = Join-Path $OutputPath "$CertName.cer"

    # Exact subject match (the old -like "*CN=Name*" also matched CN=Name2), valid, code signing only.
    $existing = Get-ChildItem -Path $myStore -CodeSigningCert |
        Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date) } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1

    $reuse = ($null -ne $existing) -and -not $Force

    if (-not (Test-Path -Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    # A PFX is written for a new certificate, or when reusing one whose PFX is missing.
    # Resolve the password up front so a failed prompt can't leave a certificate without a backup.
    $needPfx = (-not $reuse) -or -not (Test-Path -Path $pfxPath)
    if ($needPfx -and -not $PfxPassword) {
        if ($env:STRONGPASSWORD) {
            $PfxPassword = ConvertTo-SecureString -String $env:STRONGPASSWORD -AsPlainText -Force
        }
        else {
            $PfxPassword = Read-Host -Prompt 'PFX password' -AsSecureString
        }
    }

    if ($reuse) {
        $cert = $existing
        Write-Verbose "Certificate '$subject' already exists ($($cert.Thumbprint)); reusing."
    }
    else {
        # Splatting avoids the line-continuation traps (a trailing space or comment after a backtick
        # silently ends the continuation).
        $certParams = @{
            Subject           = $subject
            Type              = 'CodeSigningCert'
            KeyAlgorithm      = 'RSA'
            KeyLength         = 3072
            KeySpec           = 'Signature'
            KeyUsage          = 'DigitalSignature'
            HashAlgorithm     = 'SHA256'
            KeyExportPolicy   = 'Exportable'
            CertStoreLocation = $myStore
            NotBefore         = (Get-Date).AddHours(-1)
            NotAfter          = (Get-Date).AddYears($CertYears)
        }

        Write-Verbose 'Creating self-signed code signing certificate...'
        $cert = New-SelfSignedCertificate @certParams
        Write-Verbose "Created certificate, thumbprint $($cert.Thumbprint)"
    }

    # PFX (private key): only when new or missing. A reused certificate may have a non-exportable key.
    if ($needPfx) {
        try {
            Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $PfxPassword -ChainOption EndEntityCertOnly | Out-Null
            Write-Verbose "PFX: $pfxPath"
        }
        catch {
            if (-not $reuse) { throw }
            Write-Warning "Could not export a PFX for the existing certificate (private key may be non-exportable): $($_.Exception.Message)"
        }
    }

    # CER (public key only): always refreshed so it matches the certificate in use.
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null
    Write-Verbose "CER: $cerPath"

    # Trust: import only what is missing. Root makes the chain valid; TrustedPublisher is what
    # AllSigned/RemoteSigned policies check. CurrentUser\Root shows a Windows confirmation prompt.
    if ($Trust) {
        foreach ($storeName in 'Root', 'TrustedPublisher') {
            $storePath = "Cert:\$Scope\$storeName"
            if (Test-Path -Path "$storePath\$($cert.Thumbprint)") {
                Write-Verbose "Already trusted in $storePath"
                continue
            }
            Import-Certificate -FilePath $cerPath -CertStoreLocation $storePath | Out-Null
            Write-Verbose "Imported into $storePath"
        }
    }

    # Actual trust state, not just the requested one.
    $trusted = $true
    foreach ($storeName in 'Root', 'TrustedPublisher') {
        if (-not (Test-Path -Path "Cert:\$Scope\$storeName\$($cert.Thumbprint)")) { $trusted = $false }
    }
    $status = if ($reuse) { 'Reused existing' } else { 'Created new' }

    # Display details straight to the host (Out-Host bypasses the pipeline), then still return the
    # certificate object so callers can use it: $cert = New-CodeSigningCertificate
    $cert |
        Format-List -Property @(
            @{ Name = 'Status'; Expression = { $status } }
            'Subject'
            'Issuer'
            'Thumbprint'
            'SerialNumber'
            'NotBefore'
            'NotAfter'
            @{ Name = 'ValidDays'; Expression = { [int]($_.NotAfter - (Get-Date)).TotalDays } }
            @{ Name = 'Key'; Expression = {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($_)
                    "RSA $($rsa.KeySize), $($_.SignatureAlgorithm.FriendlyName)"
                } }
            @{ Name = 'Usage'; Expression = { ($_.EnhancedKeyUsageList.FriendlyName) -join ', ' } }
            'HasPrivateKey'
            @{ Name = 'Store'; Expression = { $myStore } }
            @{ Name = 'Trusted'; Expression = { $trusted } }
            @{ Name = 'PfxPath'; Expression = { if (Test-Path -Path $pfxPath) { $pfxPath } else { '(not written)' } } }
            @{ Name = 'CerPath'; Expression = { $cerPath } }
        ) |
        Out-Host

    $cert
}

# Signing (use a timestamp so the signature stays valid after the certificate expires):
# $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -eq 'CN=MyCodeSigningCert'
# Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
# (Get-AuthenticodeSignature .\script.ps1).Status

# Signing (use a timestamp so the signature stays valid after the certificate expires):
# $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -eq 'CN=MyCodeSigningCert'
# Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
# (Get-AuthenticodeSignature .\script.ps1).Status# New-CodeSigningCertificate

# Signing (use a timestamp so the signature stays valid after the certificate expires):
# $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object Subject -eq 'CN=MyCodeSigningCert'
# Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
# (Get-AuthenticodeSignature .\script.ps1).Status

function Set-CodeSigningCertificate {
    ## List of Code Signing Certificates
    $NumberCodeSigningCertificates = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert | Measure-Object).Count
    Write-Output "Looking for code signing certificates..." 

    if ($NumberCodeSigningCertificates -eq 0) {
        Write-Output "Did not find any!"
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

# Types: CodeSigningCert, DocumentEncryptionCert, SSLServerAuthentication
#        -FriendlyName = "$certName" `

## Create Certifciate
$certName = 'Developer Code Signing'
$certLocation = 'Cert:\CurrentUser\My' ## 'Cert:\CurrentUser\Root'
$cscert = New-SelfSignedCertificate `
        -FriendlyName 'DeveloperCodeSigning' `
        -Subject "CN=$certName" `
        -Type CodeSigningCert `
        -CertStoreLocation "$CertLocation" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyLength 2048 `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears($CertYears) `
        -Verbose
$cscert | Select-Object Subject, Thumbprint, NotAfter, @{
        Name = 'EKU'
        Expression = {
            $_.EnhancedKeyUsageList.FriendlyName -join ', '
        }
    }
Export-Certificate -Cert $cscert -FilePath "$env:TEMP\codesign.cer"
Import-Certificate -FilePath "$env:TEMP\codesign.cer" -CertStoreLocation 'Cert:\CurrentUser\TrustedPublisher'
Import-Certificate -FilePath "$env:TEMP\codesign.cer" -CertStoreLocation 'Cert:\CurrentUser\Root'
#$result = Set-AuthenticodeSignature -FilePath $file -Certificate $cscert -HashAlgorithm SHA256

$certName = 'Developer TLS'
$certLocation = 'Cert:\CurrentUser\My' ## 'Cert:\CurrentUser\Root'
$tlscert = New-SelfSignedCertificate `
        -FriendlyName 'DeveloperTLS' `
        -Subject "CN=$certName" `
        -Type SSLServerAuthentication `
        -DnsName 'localhost, *.dev.localhost, *.dev.internal, host.docker.internal, host.containers.internal, 127.0.0.1, 0000:0000:0000:0000:0000:0000:0000:0001' `
        -CertStoreLocation "$CertLocation" `
        -KeyExportPolicy Exportable `
        -KeySpec Signature `
        -KeyLength 2048 `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears($CertYears) `
        -Verbose
$tlscert | Select-Object Subject, Thumbprint, NotAfter, @{
        Name = 'EKU'
        Expression = {
            $_.EnhancedKeyUsageList.FriendlyName -join ', '
        }
    }

##$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($pfxPath, $passCert, [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable)



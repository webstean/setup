function New-LocalSelfSignedCertificate {
    <#
    .SYNOPSIS
        Creates (or reuses) a self-signed certificate of a chosen type, ensures the PFX/CER files exist
        and, by default, that the certificate is trusted. Safe to run repeatedly.
    .DESCRIPTION
        -Type CodeSigningCert          Code Signing EKU. Trusted in Root + TrustedPublisher.
        -Type SSLServerAuthentication  Server Authentication EKU with SAN (-DnsName). Trusted in Root.
    .EXAMPLE
        $cert = New-LocalSelfSignedCertificate -Type CodeSigningCert
        Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert `
            -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
    .EXAMPLE
        New-LocalSelfSignedCertificate -Type SSLServerAuthentication -CertName 'aca-dev' -DnsName 'aca-dev.local', 'localhost'
    .NOTES
        Self-signed: only trusted on machines where the CER is installed (-Trust does this locally).
        The PFX contains the private key. Do not leave it in a synced folder such as OneDrive
        unless that is a deliberate choice.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        # No default on purpose: the caller must choose.
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('CodeSigningCert', 'SSLServerAuthentication')]
        [string]$Type,

        # Default when omitted: MyCodeSigningCert or MyServerCert, depending on -Type.
        [ValidateNotNullOrEmpty()]
        [string]$CertName,

        # SSLServerAuthentication only: Subject Alternative Names (DNS names and/or IP addresses).
        # Default: localhost, *.dev.localhost, *.dev.internal, host.docker.internal,
        # host.containers.internal, 127.0.0.1, ::1 and this computer's hostname.
        [string[]]$DnsName,

        # Falls back to $env:STRONGPASSWORD, then to an interactive prompt. Only needed when a PFX is written.
        [System.Security.SecureString]$PfxPassword,

        # $env:OneDriveCommercial can be unset, which breaks Join-Path, so fall back to Documents.
        [string]$OutputPath = $(
            if ($env:OneDriveCommercial) { $env:OneDriveCommercial }
            else { [Environment]::GetFolderPath('MyDocuments') }
        ),

        [ValidateRange(1, 10)]
        [int]$CertYears = 2,

        # Default when omitted: LocalMachine if the session is elevated, otherwise CurrentUser.
        # An explicit -Scope always wins. LocalMachine requires an elevated session.
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$Scope,

        # Ensure the certificate is trusted in the chosen scope. Only missing entries are imported.
        # Default $true; use -Trust $false to skip.
        [bool]$Trust = $true,

        # Create a new certificate even if a valid one already exists.
        [switch]$Force
    )

    $ErrorActionPreference = 'Stop'

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).
        IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $PSBoundParameters.ContainsKey('Scope')) {
        $Scope = if ($isAdmin) { 'LocalMachine' } else { 'CurrentUser' }
        Write-Verbose "Scope not specified; using $Scope (elevated: $isAdmin)."
    }

    if ($Scope -eq 'LocalMachine' -and -not $isAdmin) {
        throw "Scope 'LocalMachine' requires an elevated session."
    }

    # Per-type settings.
    switch ($Type) {
        'CodeSigningCert' {
            if (-not $CertName) { $CertName = 'MyCodeSigningCert' }
            if ($DnsName) { Write-Warning '-DnsName is ignored for CodeSigningCert.' }
            $ekuOid      = '1.3.6.1.5.5.7.3.3'
            $keyUsage    = @('DigitalSignature')
            $keySpec     = 'Signature'
            $trustStores = @('Root', 'TrustedPublisher')
        }
        'SSLServerAuthentication' {
            if (-not $CertName) { $CertName = 'MyServerCert' }
            if (-not $DnsName) {
                $DnsName = @(
                    'localhost'
                    '*.dev.localhost'
                    '*.dev.internal'
                    'host.docker.internal'
                    'host.containers.internal'
                    '127.0.0.1'
                    '0000:0000:0000:0000:0000:0000:0000:0001'
                    [System.Net.Dns]::GetHostName()
                )
            }

            # IP addresses need a real iPAddress SAN entry. Passing them via -DnsName stores them as
            # DNS names, which TLS clients do not match against an IP. De-duplicate, and normalise IPv6
            # (0000:...:0001 becomes ::1).
            $sanDns = [System.Collections.Generic.List[string]]::new()
            $sanIp  = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $DnsName) {
                $ip = $null
                if ([System.Net.IPAddress]::TryParse($entry, [ref]$ip)) {
                    if (-not $sanIp.Contains($ip.ToString())) { $sanIp.Add($ip.ToString()) }
                }
                elseif (-not ($sanDns | Where-Object { $_ -ieq $entry })) {
                    $sanDns.Add($entry)
                }
            }
            $sanParts = @($sanDns | ForEach-Object { "DNS=$_" }) + @($sanIp | ForEach-Object { "IPAddress=$_" })
            $sanText  = '2.5.29.17={text}' + ($sanParts -join '&')

            $ekuOid      = '1.3.6.1.5.5.7.3.1'
            $keyUsage    = @('DigitalSignature', 'KeyEncipherment')
            $keySpec     = 'KeyExchange'
            $trustStores = @('Root')
        }
    }

    $subject = "CN=$CertName"
    $myStore = "Cert:\$Scope\My"
    $pfxPath = Join-Path $OutputPath "$CertName.pfx"
    $cerPath = Join-Path $OutputPath "$CertName.cer"

    # Exact subject match (-like "*CN=Name*" would also match CN=Name2), still valid, correct EKU.
    $existing = Get-ChildItem -Path $myStore |
        Where-Object {
            $_.Subject -eq $subject -and
            $_.NotAfter -gt (Get-Date) -and
            ($_.EnhancedKeyUsageList.ObjectId -contains $ekuOid)
        } |
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
        Write-Verbose "Certificate '$subject' ($Type) already exists ($($cert.Thumbprint)); reusing."
    }
    else {
        # Splatting avoids the line-continuation traps (a trailing space or comment after a backtick
        # silently ends the continuation).
        $certParams = @{
            Subject           = $subject
            Type              = $Type
            KeyAlgorithm      = 'RSA'
            KeyLength         = 3072
            KeySpec           = $keySpec
            KeyUsage          = $keyUsage
            HashAlgorithm     = 'SHA256'
            KeyExportPolicy   = 'Exportable'
            CertStoreLocation = $myStore
            NotBefore         = (Get-Date).AddHours(-1)
            NotAfter          = (Get-Date).AddYears($CertYears)
        }
        if ($Type -eq 'SSLServerAuthentication') { $certParams['TextExtension'] = @($sanText) }

        Write-Verbose "Creating self-signed $Type certificate..."
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

    # Trust: import only what is missing. Root makes the chain valid; TrustedPublisher (code signing
    # only) is what AllSigned/RemoteSigned policies check. CurrentUser\Root shows a Windows prompt.
    if ($Trust) {
        foreach ($storeName in $trustStores) {
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
    foreach ($storeName in $trustStores) {
        if (-not (Test-Path -Path "Cert:\$Scope\$storeName\$($cert.Thumbprint)")) { $trusted = $false }
    }
    $status = if ($reuse) { 'Reused existing' } else { 'Created new' }

    # Display details straight to the host (Out-Host bypasses the pipeline), then still return the
    # certificate object so callers can use it: $cert = New-LocalSelfSignedCertificate -Type ...
    $cert |
        Format-List -Property @(
            @{ Name = 'Status'; Expression = { $status } }
            @{ Name = 'Type'; Expression = { $Type } }
            'Subject'
            @{ Name = 'SAN'; Expression = {
                    $san = $_.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.17' }
                    if ($san) { $san.Format($false) } else { '(none)' }
                } }
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
#New-LocalSelfSignedCertificate -Type CodeSigningCert
#New-LocalSelfSignedCertificate -Type SSLServerAuthentication

# Signing with a CodeSigningCert (use a timestamp so the signature outlives the certificate):
# $cert = Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert | Where-Object Subject -eq 'CN=MyCodeSigningCert'
# Set-AuthenticodeSignature -FilePath .\script.ps1 -Certificate $cert -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com'
# (Get-AuthenticodeSignature .\script.ps1).Status


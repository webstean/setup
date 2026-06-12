function New-CodeSigningCertificate {
    param (
        [string]$CertName = "MyCodeSigningCert",
        [Parameter()]
        [System.Security.SecureString]$PfxPassword = (ConvertTo-SecureString -String (Get-Item Env:STRONGPASSWORD).Value -AsPlainText -Force),
        [string]$OutputPath = "$env:OneDriveCommercial"
    )

    try { 

        $subject = "CN=$CertName"

        if ( Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$subject*" } ) { return } ## already exists
        
        ## Delete
        # $cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -like "*$subject*" }
        # Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"
        
        # Ensure output path exists
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $pfxPath = Join-Path $OutputPath "$CertName.pfx"
        $cerPath = Join-Path $OutputPath "$CertName.cer"
        $securePass = ConvertTo-SecureString -String $PfxPassword -Force -AsPlainText

        Write-Host "==> Creating self-signed code signing certificate..."
        $cert = New-SelfSignedCertificate `
            -Subject "$subject" `
            -KeyExportPolicy Exportable `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -NotAfter (Get-Date).AddYears(2) `
            -Type CodeSigningCert `
            -KeySpec Signature `
            -KeyLength 2048 `
            -HashAlgorithm SHA256

        Write-Host "Created code signing certificate with Thumbprint:" $cert.Thumbprint

        Write-Host "==> Exporting certificate..."
        Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePass | Out-Null
        Export-Certificate    -Cert $cert -FilePath $cerPath | Out-Null
        Write-Host "PFX exported to $pfxPath"
        Write-Host "CER exported to $cerPath"

        ## Add to Trusted Root store
        Write-Host "==> Importing certificate into Trusted Root..."
        ## Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\CurrentUser\Root | Out-Null ## This User
        Import-Certificate -FilePath $cerPath -CertStoreLocation Cert:\Localmachine\Root | Out-Null ## All Users

        ## How to sign something
        #$cert = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert)[0]
        #Set-AuthenticodeSignature -Certificate $cert -FilePath .\aw.ps1  ## -TimestampServer "https://timestamp.fabrikam.com/scripts/timstamper.dll"
        #Set-AuthenticodeSignature -Certificate $cert -FilePath .\aw.ps1 -HashAlgorithm "SHA256" -TimestampServer 'http://timestamp.verisign.com/scripts/timstamp.dll'

        #(Get-AuthenticodeSignature .\aw.ps1).StatusMessage

    }

    catch {
        Write-Output "An exception occurred: $_" 
        Write-Output "Exception Type: $($_.Exception.GetType().FullName)" 
        Write-Output "Exception Message: $($_.Exception.Message)" 
        Write-Output "Stack Trace: $($_.Exception.StackTrace)" 
    }
}
function Set-CodeSigningCertificate {
    ## List of Code Signing Certificates
    $NumberCodeSigningCertificates = (Get-ChildItem -Path Cert:\* -Recurse -CodeSigningCert | Measure-Object).Count
    Write-Output "Looking for code signing certificates..." 

    if ($NumberCodeSigningCertificates -eq 0) {
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



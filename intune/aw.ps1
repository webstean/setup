#Requires -RunAsAdministrator

function Test-DeveloperMode {
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
    $regName = 'AllowDevelopmentWithoutDevLicense'

    if (-not (Test-Path $regPath)) {
        return $false
    }

    $val = (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue).$regName
    return ($val -eq 1)
}

function Enable-DeveloperDevicePortal {
    ## Device Discovery requires Windows SDK (1803 or later)
    ## 
    
    [CmdletBinding(SupportsShouldProcess)]
    param ()

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
        Write-Error "❌ This function must be run as Administrator."
        return
    }

    Write-Verbose "Checking if Developer Mode is enabled..."
    if (-not (Test-DeveloperMode)) {
        Write-Warning "❌ Developer Mode is not enabled. Enable it in Settings > For Developers or via registry."
        return $false
    }

   # if ( -not (Install-LatestWindowsSDK)) {
   #     Write-Warning "❌ WindowsSDK installation has failed (or wasn't found)"
   #     return $false
   # }
   # return
        
    Write-Host "📦 Installing required Windows capabilities..."
    $capabilities = @(
        "DeviceDiscovery",
        "WindowsDeveloperMode",
        "DevicePortal"
    )

    foreach ($capability in $capabilities) {
        Write-Host "→ Installing $capability..."
        try {
            Add-WindowsCapability -Online -Name "${capability}~~~~0.0.1.0" -ErrorAction Stop
        }
        catch {
            Write-Warning "⚠️ Could not install ${capability}: $_"
        }
    }

    Write-Host "🔐 Enabling Device Portal via registry..."
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DevicePortal"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "EnableDevPortal" -Value 1 -Force

    Write-Host "🔄 Restarting services..."
    Try {
        Restart-Service -Name dmwappushservice -ErrorAction SilentlyContinue
    }
    catch {
        Write-Warning "⚠️ Could not restart dmwappushservice: $_"
    }
    if (Get-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -Value 1
    }
    else {
        New-ItemProperty -Path $DevicePortalKeyPath -Name "EnableDevicePortal" -PropertyType DWORD -Value 1
    }

    ## Enable authentication (optional but recommended)
    if (Get-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -Value 1
    }
    else {
        New-ItemProperty -Path $DevicePortalKeyPath -Name "Authentication" -PropertyType DWORD -Value 1
    }

    if (! (Test-Path -Path $WebMgrKeyPath)) {
        New-Item -Path $WebMgrKeyPath -ItemType Directory -Force
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -Value 0x0000c50b
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name HttpsPort -PropertyType DWORD -Value 0x0000c50b
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -Value 1
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name RequireDevUnlock -PropertyType DWORD -Value 1
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -Value 0
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name UseDefaultAuthorizer -PropertyType DWORD -Value 0
    }
    if (Get-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -ErrorAction SilentlyContinue) {
        Set-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -Value 0
    }
    else {
        New-ItemProperty -Path $WebMgrKeyPath -Name UseDynamicPorts -PropertyType DWORD -Value 0
    }
    Get-Item -Path $WebMgrKeyPath
    # Open firewall port for Device Portal (usually 50080 for HTTP and 50443 for HTTPS)
    New-NetFirewallRule -DisplayName "Developer Device Portal HTTP" -Direction Inbound -LocalPort 50080 -Protocol TCP -Action Allow
    New-NetFirewallRule -DisplayName "Developer Device Portal HTTPS" -Direction Inbound -LocalPort 50443 -Protocol TCP -Action Allow
    Write-Host "🔄 Restarting Web Management Service..."
    Set-Service -Name webmanagement -StartupType Automatic
    Restart-Service -Name webmanagement -ErrorAction SilentlyContinue

    Write-Host "`n✅ Device Portal is enabled."
    Write-Host "   🔗 Open: https://localhost:50080"
}
Enable-DeveloperDevicePortal


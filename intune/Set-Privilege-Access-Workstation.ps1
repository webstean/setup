#Requires -RunAsAdministrator

## Based upon: https://raw.githubusercontent.com/Azure/securedworkstation/refs/heads/master/ENT/Scripts/ENT-DeviceConfig.ps1

        
#region Configure additional Defender for Endpoint security recommendations that cannot be set in Configuration Profiles
#Handle registry changes
       
Write-Host "Configuring additional Defender for Endpoint security recommendations that cannot be set in Configuration Profiles"
# Require users to elevate when setting a network's location - prevent changing from Public to Private firewall profile
New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Network Connections" -Name NC_StdDomainUserSetLocation -Value 1 -PropertyType DWORD -Force
Write-Host "Require users to elevate when setting a network's location - prevent changing from Public to Private firewall profile registry update successfully applied"
# Prevent saving of network credentials 
New-ItemProperty -Path HKLM:\SYSTEM\CurrentControlSet\Control\Lsa -Name DisableDomainCreds -Value 1 -PropertyType DWORD -Force
Write-Host "Prevent saving of network credentials registry update successfully applied"
# Prevent changing proxy config
                
#region Disable Network Location Wizard - prevents users from setting network location as Private and therefore increasing the attack surface exposed in Windows Firewall
#region Disable Network Location Wizard
#Handle registry changes
$registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Network"
$regProperties = @{
    Name        = "NewNetworkWindowOff"
    ErrorAction = "Stop"
}

Try {
    $Null = New-ItemProperty -Path $registryPath @regProperties -Force
}
Catch [System.Management.Automation.ItemNotFoundException] {
    Write-Host "Error: $registryPath path not found, attempting to create..."
    $Null = New-Item -Path $registryPath -Force
    $Null = New-ItemProperty -Path $registryPath @regProperties -Force
}
Catch {
    Write-Host "Error changing registry: $($_.Exception.message)"
    Write-Warning "Error: $($_.Exception.message)"        
    Exit
}
Finally {
    Write-Host "Finished Disable Network Location Wizard in registry"
}
#endregion Disable Network Location Wizard


#region Remove Powershell 2.0 / Windows Powershell - will break stuff, typically DISM
try {
    #Enable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop
    Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop
    Write-Host "Removed Powershell v2.0"
}
catch {
    Write-Host "Error occurred trying to remove Powershell v2.0: $($_.Exception.message)"
}

try {
    Disable-WindowsOptionalFeature -Online -FeatureName WorkFolders-Client -ErrorAction Stop
    Write-Host "Removed WorkFolders"
}
catch {
    Write-Host "Failed to remove WorkFolders"
    Write-Host "Error occurred trying to remove Powershell v2.0: $($_.Exception.message)"
}
#endregion Remove WorkFolders-Client

#region Remove XPS Printing
try {
    Disable-WindowsOptionalFeature -Online -FeatureName Printing-XPSServices-Features -ErrorAction Stop
    Write-Host "Removed XPS Printing"
}
catch {
    Write-Host "Error occurred trying to remove XPS Printing: $($_.Exception.message)"
}
#endregion Remove XPS Printing

#region Remove WindowsMediaPlayer
try {
    Disable-WindowsOptionalFeature -Online -FeatureName WindowsMediaPlayer -ErrorAction Stop
    Write-Host "Removed Windows Media Player"
}
catch {
    Write-Host "Error occurred trying to remove Windows Media Player: $($_.Exception.message)"
}
#endregion Remove WindowsMediaPlayer

Write-Host "🔐 Configuring Windows Firewall..."

# 1. Reset to default (optional)
Write-Host "🧹 Resetting firewall to default settings..."
(New-Object -ComObject HNetCfg.FwPolicy2).RestoreLocalFirewallDefaults()

# 2. Set default profile behavior
Write-Host "🔒 Setting default to block inbound and outbound traffic..."
Set-NetFirewallProfile -Profile Domain,Public,Private `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Block

# 3. Allow outbound ICMP
Write-Host "✅ Allowing outbound ICMP..."
New-NetFirewallRule -DisplayName "Allow Outbound ICMPv4" -Protocol ICMPv4 -Direction Outbound -Action Allow -Profile Domain,Private,Public
New-NetFirewallRule -DisplayName "Allow Outbound ICMPv6" -Protocol ICMPv6 -Direction Outbound -Action Allow -Profile Domain,Private,Public

# 4. Allow outbound HTTP (TCP 80)
Write-Host "✅ Allowing outbound HTTP..."
New-NetFirewallRule -DisplayName "Allow Outbound HTTP" -Direction Outbound -Protocol TCP -RemotePort 80 -Action Allow -Profile Domain,Private,Public

# 5. Allow outbound HTTPS (TCP 443)
Write-Host "✅ Allowing outbound HTTPS..."
New-NetFirewallRule -DisplayName "Allow Outbound HTTPS" -Direction Outbound -Protocol TCP -RemotePort 443 -Action Allow -Profile Domain,Private,Public

# 6. Allow outbound DNS (UDP 53 + TCP 53)
Write-Host "✅ Allowing outbound DNS..."
New-NetFirewallRule -DisplayName "Allow Outbound DNS (UDP)" -Direction Outbound -Protocol UDP -RemotePort 53 -Action Allow -Profile Domain,Private,Public
New-NetFirewallRule -DisplayName "Allow Outbound DNS (TCP)" -Direction Outbound -Protocol TCP -RemotePort 53 -Action Allow -Profile Domain,Private,Public

# 7. Allow outbound RDP (TCP 3389)
Write-Host "✅ Allowing outbound RDP..."
New-NetFirewallRule -DisplayName "Allow Outbound RDP" -Direction Outbound -Protocol TCP -RemotePort 3389 -Action Allow -Profile Domain,Private,Public

# 8. Allow outbound SSH (TCP 22)
Write-Host "✅ Allowing outbound SSH..."
New-NetFirewallRule -DisplayName "Allow Outbound SSH" -Direction Outbound -Protocol TCP -RemotePort 22 -Action Allow -Profile Domain,Private,Public

# 9. Explicitly block all inbound traffic (default covers this already)
Write-Host "⛔ Ensuring all inbound traffic is blocked..."
New-NetFirewallRule -DisplayName "Block All Inbound" -Direction Inbound -Action Block -Profile Domain,Private,Public

Write-Host "`n✅ Firewall locked down successfully:"
Write-Host "   → Allowed Outbound: ICMP, HTTP, HTTPS, DNS, RDP, SSH"
Write-Host "   → All Inbound Traffic Blocked"

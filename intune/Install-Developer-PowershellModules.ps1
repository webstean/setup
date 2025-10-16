#Requires -RunAsAdministrator

## Installing developer orientated PowerShell modules

$installscope = "CurrentUser"

winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.9
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')
${INSTALLED_DOTNET_VERSION} = dotnet --version
Write-Host "Installed .NET SDK version: ${INSTALLED_DOTNET_VERSION}"
## dotnet new globaljson --sdk-version ${INSTALLED_VERSION} --force --roll-forward "latestPatch, latestFeature"
## curl -sSL https://dot.net/v1/dotnet-install.sh | bash -- --version $(jq -r '.sdk.version' global.json)
#winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.10
winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.Preview

## Provider: PSGallery
Write-Output "Enable PSGallery..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$srcV2 = 'https://www.powershellgallery.com/api/v2'
$srcV3 = 'https://www.powershellgallery.com/api/v3'
Register-PSRepository -Name PSGallery -SourceLocation $srcV3 -PackageSourceLocation $srcV3 
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -PackageSourceLocation $src -Force
}


# ------------------------------------------------------------
# Ensure-PSGalleryTrusted.ps1
# - Repairs repo state
# - Registers PSGallery (PSGet v2 or v3)
# - Sets installation policy to Trusted
# ------------------------------------------------------------

# 0) Session prep: TLS 1.2 + optional proxy (uncomment if needed)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# [System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

function Write-Info($msg){ Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Warning $msg }
function Write-Err ($msg){ Write-Host "[ERROR] $msg" -ForegroundColor Red }

$ApiV2 = 'https://www.powershellgallery.com/api/v2'
$ApiV3 = 'https://www.powershellgallery.com/api/v3'

# 1) Make sure PackageManagement + PowerShellGet are loadable (v1/v2 path)
try {
    Import-Module PackageManagement -ErrorAction Stop
} catch {
    Write-Warn "PackageManagement module could not be imported. Continuing; v3 path may succeed."
}
try {
    Import-Module PowerShellGet -ErrorAction SilentlyContinue
} catch {
    Write-Warn "PowerShellGet module could not be imported. We'll try v3 cmdlets or repair."
}

# 2) If PowerShellGet v1/v2 appears available, try to repair/re-register PSGallery (api v2)
$hasV2Cmds = Get-Command -Name Register-PSRepository -ErrorAction SilentlyContinue
$repairedV2 = $false

if ($hasV2Cmds) {
    Write-Info "PowerShellGet v1/v2 cmdlets detected."

    # (a) If PSRepository definitions are corrupt/empty, remove per-user file so defaults can be restored
    $repoFile = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\PowerShell\PowerShellGet\PSRepositories.xml'
    try {
        # Detect obviously broken state: Get-PSRepository throws or shows blank SourceLocation
        $broken = $false
        try {
            $repos = Get-PSRepository -ErrorAction Stop
            foreach ($r in $repos) {
                if ([string]::IsNullOrWhiteSpace($r.SourceLocation)) { $broken = $true }
            }
        } catch { $broken = $true }

        if ($broken -and (Test-Path $repoFile)) {
            Write-Warn "Detected broken PSRepository state. Removing: $repoFile"
            Remove-Item $repoFile -Force
        }
    } catch {
        Write-Warn "Could not check/remove PSRepositories.xml: $_"
    }

    # (b) Recreate or repair PSGallery (api v2)
    try {
        $psg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $psg) {
            Write-Info "Registering PSGallery (api v2)…"
            Register-PSRepository -Name PSGallery `
                -SourceLocation $ApiV2 `
                -ScriptSourceLocation $ApiV2 `
                -PackageSourceLocation $ApiV2 `
                -InstallationPolicy Trusted
        } else {
            # Fix empty URLs or untrusted policy
            $needsReset = [string]::IsNullOrWhiteSpace($psg.SourceLocation) -or
                          [string]::IsNullOrWhiteSpace($psg.ScriptSourceLocation) -or
                          [string]::IsNullOrWhiteSpace($psg.PackageSourceLocation)
            if ($needsReset) {
                Write-Warn "PSGallery URLs are missing/invalid. Re-registering…"
                Unregister-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
                Register-PSRepository -Name PSGallery `
                    -SourceLocation $ApiV2 `
                    -ScriptSourceLocation $ApiV2 `
                    -PackageSourceLocation $ApiV2 `
                    -InstallationPolicy Trusted
            } else {
                if ($psg.InstallationPolicy -ne 'Trusted') {
                    Write-Info "Setting PSGallery to Trusted…"
                    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
                }
            }
        }
        $repairedV2 = $true
    } catch {
        Write-Warn "v2 Register/Set-PSRepository flow failed: $($_.Exception.Message)"
    }
}

# 3) If v2 path failed or not present, try PowerShellGet v3 repo cmdlets (api v3)
$hasV3Cmds = Get-Command -Name Register-PSResourceRepository -ErrorAction SilentlyContinue
if (-not $repairedV2 -and $hasV3Cmds) {
    Write-Info "PowerShellGet v3 cmdlets detected."

    try {
        $repo = Get-PSResourceRepository -Name PSGallery -ErrorAction SilentlyContinue
        if (-not $repo) {
            Write-Info "Registering PSGallery (api v3)…"
            Register-PSResourceRepository -Name PSGallery -Url $ApiV3 -Trusted
        } else {
            if (-not $repo.Trusted) {
                Write-Info "Marking PSGallery as Trusted (v3)…"
                Set-PSResourceRepository -Name PSGallery -Trusted
            }
            # Ensure URL is correct
            if ($repo.Url -ne $ApiV3) {
                Write-Info "Updating PSGallery URL to api v3…"
                Unregister-PSResourceRepository -Name PSGallery -ErrorAction SilentlyContinue
                Register-PSResourceRepository -Name PSGallery -Url $ApiV3 -Trusted
            }
        }
        $repairedV2 = $true
    } catch {
        Write-Err "v3 repository registration failed: $($_.Exception.Message)"
    }
}

# 4) As a last resort on Windows PowerShell 5.1, try default registration
if (-not $repairedV2 -and $hasV2Cmds) {
    try {
        Write-Info "Attempting Register-PSRepository -Default…"
        Register-PSRepository -Default -ErrorAction Stop
        # Ensure trusted
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        $repairedV2 = $true
    } catch {
        Write-Warn "Default registration failed: $($_.Exception.Message)"
    }
}

# 5) Verify & show final state
Write-Host ""
Write-Info "Final repository state:"
if ($hasV2Cmds) {
    try {
        Get-PSRepository | Format-Table Name, SourceLocation, InstallationPolicy -AutoSize
    } catch {
        Write-Warn "Get-PSRepository failed: $($_.Exception.Message)"
    }
}
if ($hasV3Cmds) {
    try {
        Get-PSResourceRepository | Format-Table Name, Url, Trusted -AutoSize
    } catch {
        Write-Warn "Get-PSResourceRepository failed: $($_.Exception.Message)"
    }
}

# 6) Optional: ensure NuGet provider is present for v2 clients (helps Install-Module)
try {
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Write-Info "Bootstrapping NuGet provider…"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Warn "NuGet provider bootstrap failed (may be fine on v3-only systems): $($_.Exception.Message)"
}

Write-Host ""
Write-Info "PSGallery should now be registered and trusted."




Install-Module PowerShellGet -Force
Register-PSRepository -Default -ErrorAction SilentlyContinue
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
}
Get-PSRepository -Verbose
Find-PackageProvider -ForceBootstrap

## Provider: nuget
Write-Output "Enable nuget..."
Set-PackageSource -Name "nuget.org" -Trusted -ErrorAction SilentlyContinue
Get-PackageProvider 
#Find-PackageProvider -Name NuGet | Install-PackageProvider -Force -ErrorAction SilentlyContinue
#Register-PackageSource -Name nuget.org -Location https://www.nuget.org/api/v2 -ProviderName NuGet -ErrorAction SilentlyContinue

## Setup PSReadline
Write-Output "Setting up PSReadline..."
Import-Module PowerShellGet
if ( -not (Get-Module -Name Terminal-Icons -ListAvailable)) {
    Install-Module Terminal-Icons -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Update-Module Terminal-Icons -Force -Scope $installscope -ErrorAction SilentlyContinue
}
if ( -not (Get-Module -Name PSReadline -ListAvailable)) {
    Install-Module PSReadline -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
}
Set-PSReadLineOption -Colors @{
    Command            = 'White'
    Number             = 'DarkGray'
    Member             = 'DarkGray'
    Operator           = 'DarkGray'
    Type               = 'DarkGray'
    Variable           = 'DarkGreen'
    Parameter          = 'DarkGreen'
    ContinuationPrompt = 'DarkGray'
    Default            = 'DarkGray'
}
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -PredictionSource History
## This parameter was added in PSReadLine 2.2.0
Set-PSReadLineOption -PredictionViewStyle ListView

# Active Directory (AD) Modules
# Install AZ Modules - Az PowerShell module is the recommended PowerShell module for managing Azure resources on all platforms.
if ( -not (Get-Module -Name Az -ListAvailable)) {
    Write-Output ("Installing AZ (Azure) Powershell module...")
    Install-Module -Name Az -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Updating AZ (Azure) Powershell module...")
    Update-Module -Name Az -Scope $installscope -Force -ErrorAction SilentlyContinue 
}

## Get rid of depreciated modules
if (Get-Module -Name AzureAD -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD -Force -ErrorAction SilentlyContinue
}
if (Get-Module -Name AzureAD.Standard.Preview -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD.Standard.Preview -Force -ErrorAction SilentlyContinue
}

## Install Winget Configuration
if (-not (Get-Module -Name Microsoft.WinGet.Configuration -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Update-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -Force -ErrorAction SilentlyContinue
}
## $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
## get-WinGetConfiguration -file .\.configurations\vside.dsc.yaml | Invoke-WinGetConfiguration -AcceptConfigurationAgreements

## Example
## 'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object {Install-Module -Name $_ -AllowPrerelease}

## Microsoft Graph Modules
if ( -not (Get-Module -Name Microsoft.Graph -ListAvailable)) {
    Write-Output ("Installing Microsoft Graph Powershell modules...")
    Install-Module Microsoft.Graph -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Updating Microsoft Graph Powershell modules...")
    Update-Module Microsoft.Graph -Force -Scope $installscope -ErrorAction SilentlyContinue
} 

## Install Teams Modules
if ( -not (Get-Module -Name MicrosoftTeams -ListAvailable)) {
    Write-Output ("Installing Microsoft Teams Powershell modules...")
    Install-Module MicrosoftTeams -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Updating Microsoft Teams Powershell modules...")
    Update-Module MicrosoftTeams -Force -Scope $installscope -ErrorAction SilentlyContinue
} 

## Install PowerApps Modules
if ( -not (Get-Module -Name Microsoft.PowerApps.Administration.PowerShell -ListAvailable)) {
    Write-Output ("Installing Microsoft Power Apps modules...")
    Install-Module Microsoft.PowerApps.Administration.PowerShell -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Updating Microsoft Power Apps modules...")
    Update-Module Microsoft.PowerApps.Administration.PowerShell -Force -Scope $installscope -ErrorAction SilentlyContinue
} 
## Add-PowerAppsAccount -Endpoint prod
$jsonObject= @" 
{ 
 "PostProvisioningPackages": 
 [ 
 { 
     "applicationUniqueName": "msdyn_FinanceAndOperationsProvisioningAppAnchor", 
    "parameters": "DevToolsEnabled=true|DemoDataEnabled=true" 
 } 
 ] 
} 
"@ | ConvertFrom-Json
# To kick off new PowerApp environment
# IMPORTANT - This has to be a single line, after the copy & paste the command
# New-AdminPowerAppEnvironment -DisplayName "MyUniqueNameHere" -EnvironmentSku Sandbox -Templates "D365_FinOps_Finance" -TemplateMetadata $jsonObject -LocationName "Australia" -ProvisionDatabase

## Install Vmware PowerCLI (its too big)
#if ( -not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
#    Install-Module -Name VMware.PowerCLI  -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
#} else {
#    Update-Module VMware.PowerCLI -Force -Scope $installscope -ErrorAction SilentlyContinue
#} 
#Get-InstalledModule -Name VMware.PowerCLI

## Install Azure Tools Predictor
if ( -not (Get-Module -Name Az.Tools.Predictor -ListAvailable)) {
    Install-Module Az.Tools.Predictor -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Update-Module Az.Tools.Predictor -Force -Scope $installscope -ErrorAction SilentlyContinue
}    
Import-Module Az.Tools.Predictor
Enable-AzPredictor -AllSession ## will update $profile
(Get-PSReadLineOption).PredictionSource
Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
# Set-PSReadLineOption -PredictionViewStyle InlineView

## Install Help for all installed modules
if (-not (Get-Help -Name Get-Command -ErrorAction SilentlyContinue | Where-Object { $_.Category -eq "HelpFile" })) {
    Update-Help -UICulture en-AU -Force -ErrorAction SilentlyContinue | Out-Null
}

## Clear-AzConfig
Export-AzConfig -Force -Path $HOME\AzConfig.json

Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
Update-AzConfig -DisplaySurveyMessage $false | Out-Null
Update-AzConfig -EnableLoginByWam $true | Out-Null
## Update-AzConfig -DefaultSubscriptionForLogin $env:AZURE_SUBSCRIPTION_ID
Update-AzConfig -CheckForUpgrade $false | Out-Null
Update-AzConfig -DisplayRegionIdentified $true | Out-Null
Update-AzConfig -DisplaySecretsWarning $false | Out-Null
Update-AzConfig -EnableDataCollection $false | Out-Null

## Connect-AzAccount -Identity -AccountId <user-assigned-identity-clientId-or-resourceId>
## Connect-AzAccount
## Get-AzSubscription -SubscriptionId "<your-subscription-id>" | Format-List

## $resourceCount = (Get-AzResource -ErrorAction SilentlyContinue).Count
## Write-Output "Number of Azure are resources in subscription ($env:AZURE_SUBSCRIPTION_ID) : $resourceCount"



﻿#Requires -RunAsAdministrator

## Installing developer orientated PowerShell modules

$IsLanguagePermissive = $ExecutionContext.SessionState.LanguageMode -ne 'ConstrainedLanguage'
if ($IsLanguagePermissive) {
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} else {
    # Check language mode — must not be ConstrainedLanguage for method invocation
    $IsAdmin = (whoami /groups | Select-String "S-1-5-32-544") -ne $null
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
} else {
    $InstallScope = 'CurrentUser'
}

Write-Host "InstallScope = $InstallScope"

#winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.NuGet
winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.9
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path','User')
${INSTALLED_DOTNET_VERSION} = dotnet --version
Write-Host "Installed .NET SDK version: ${INSTALLED_DOTNET_VERSION}"
## dotnet new globaljson --sdk-version ${INSTALLED_VERSION} --force --roll-forward "latestPatch, latestFeature"
## curl -sSL https://dot.net/v1/dotnet-install.sh | bash -- --version $(jq -r '.sdk.version' global.json)
#winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.10
winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.Preview

## Provider: nuget
Write-Output "Enabling nuget..."
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$true | Out-Null
}
Find-PackageProvider -ForceBootstrap
Set-PackageSource -Name "nuget.org" -Trusted -ErrorAction SilentlyContinue

## Provider: PSGallery
Write-Output "Enabling and trusting PSGallery..."
Register-PSRepository -Default -ErrorAction SilentlyContinue
if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
    Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
}
if ((Get-PSResourceRepository -Name PSGallery).Trusted -ne $true) {
    Set-PSResourceRepository -Name 'PSGallery' -Trusted -ErrorAction SilentlyContinue
}
if ((Get-PSResourceRepository -Name PSGallery).IsAllowedByPolicy -ne $true) {
    Set-PSResourceRepository -Name 'PSGallery' -IsAllowedByPolicy $true -ErrorAction SilentlyContinue
}

### Container Registry - BTW: PSResourceGet expects a NuGet v2 or v3 feed, not a pure OCI registry.
#Register-PSResourceRepository -Name ACR -Uri https://mycompanyregistry.azurecr.io/nuget/v2 -Trusted -ApiVersion ContainerRegistry

Find-PSResource -Repository PSGallery -name PackageManagement

## Cleanup User Scope
## Get-PSResource -Scope 'CurrentUser' | Uninstall-PSResource -SkipDependencyCheck

## Delete everything and start again
## Get-PSResource -Scope 'AllUsers' | Uninstall-PSResource -SkipDependencyCheck



function Install-OrUpdateModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [switch]$Prerelease          # Optional: install prerelease versions
    )

    # Check if PSResourceGet is available
    if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
        Write-Host "PSResourceGet not found. Installing it first..." -ForegroundColor Yellow
        Install-Module -Name Microsoft.PowerShell.PSResourceGet -Scope $InstallScope -Force
        Import-Module Microsoft.PowerShell.PSResourceGet
    }

    # Check if module is already installed
    $installed = Get-PSResource -Name $ModuleName -ErrorAction SilentlyContinue -Scope $Installscope

    try {
        if ($null -eq $installed) {
            Write-Host "Module '$ModuleName' not found. Installing (${InstallScope})..." -ForegroundColor Green
            if ($prerelease) {
                Install-PSResource -Name $ModuleName -Prerelease $true -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            } else {
                ## Install-PSResource -Name PackageManagement -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
                Install-PSResource -Name $ModuleName -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            }
        }
        else {
            Write-Host "Module '$ModuleName' found. Updating (${InstallScope})..." -ForegroundColor Cyan
            ## Update-PSResource -Name PackageManagement -AcceptLicense $true -Confirm $false -ErrorAction Stop -WarningAction SilentlyContinue
            if ($prerelease) {
                Update-PSResource -Name $ModuleName -Prerelease $true -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            } else {
                Update-PSResource -Name $ModuleName -AcceptLicense -ErrorAction Stop -WarningAction SilentlyContinue -Scope $Installscope
            }
        }
        # Optional: import after install/update
        Import-Module $ModuleName -Force
        Write-Host "✅ '$ModuleName' is installed (and up to date.)" -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Failed to install or update '$ModuleName': $_" -ForegroundColor Red
    }
}

## Get rid of depreciated modules
if (Get-Module -Name AzureAD -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD -Force -ErrorAction SilentlyContinue
}
if (Get-Module -Name AzureAD.Standard.Preview -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD.Standard.Preview -Force -ErrorAction SilentlyContinue
}

Install-OrUpdateModule PSWindowsUpdate
Install-OrUpdateModule PackageManagement
Install-OrUpdateModule ModernWorkplaceClientCenter
Install-OrUpdateModule Terminal-Icons
Install-OrUpdateModule Az
Install-OrUpdateModule Microsoft.WinGet.Client
Install-OrUpdateModule Microsoft.WinGet.Configuration
Install-OrUpdateModule Microsoft.Graph
Install-OrUpdateModule MicrosoftTeams
#Install-OrUpdateModule VMware.PowerCLI ## VMware PowerCLI (its too big - as no longer used much)
Install-OrUpdateModule Microsoft.PowerApps.Administration.PowerShell
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

## Setup PSReadLine
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

## Install Azure Tools Predictor
Install-OrUpdateModule Az.Tools.Predictor
Import-Module Az.Tools.Predictor
#Enable-AzPredictor -AllSession ## will update $profile (which include this in the default)
(Get-PSReadLineOption).PredictionSource
Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
# Set-PSReadLineOption -PredictionViewStyle InlineView

## Install (and Update) PowerShell Help
if (-not (Get-Help -Name Get-Command -ErrorAction SilentlyContinue | Where-Object { $_.Category -eq "HelpFile" })) {
    Update-Help -UICulture en-AU -Force -ErrorAction SilentlyContinue | Out-Null
}

## Upgrade all the installed modules - needs to run as a job
#Get-InstalledModule | ForEach-Object {
#    Write-Host "Updating $($_.Name) ..."
#    Update-Module -Name $_.Name -Force -ErrorAction Continue
#}

## Clear-AzConfig
if ( -not (Test-Path $HOME\AzConfig.json)) {
    Export-AzConfig -Path $HOME\AzConfig.json -Force
}
Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
Update-AzConfig -DisplaySurveyMessage $false | Out-Null
Update-AzConfig -EnableLoginByWam $true | Out-Null
Update-AzConfig -EnableErrorRecordsPersistence $false | Out-Null ## When enabled, error records will be written to ~/.Azure/ErrorRecords.
        
if (Test-Path env:AZURE_SUBSCRIPTION_ID) {
    Update-AzConfig -DefaultSubscriptionForLogin $env:AZURE_SUBSCRIPTION_ID
    azd config set defaults.subscription $env:AZURE_SUBSCRIPTION_ID
}
if (Test-Path env:AZURE_LOCATION) {
    azd config set defaults.location $env:AZURE_LOCATION
} else {
    azd config set defaults.location australiaeast
    ## Set Azure Location to australiaeast
    [System.Environment]::SetEnvironmentVariable(
        "AZURE_LOCATION",
        "australiaeast",
        [System.EnvironmentVariableTarget]::Machine
    )
}
[System.Environment]::SetEnvironmentVariable(
    "AZURE_ENV_NAME",
    "devtest",
    [System.EnvironmentVariableTarget]::Machine
)

if ($env:USERNAME) {
    [System.Environment]::SetEnvironmentVariable(
        "AZURE_ENV_NAME",
        "devtest-${env:USERNAME}",
        [System.EnvironmentVariableTarget]::User
    )
}
# Use DevCenter for deployments
azd config set platform.type devcenter

Update-AzConfig -CheckForUpgrade $false | Out-Null
Update-AzConfig -DisplayRegionIdentified $true | Out-Null
Update-AzConfig -DisplaySecretsWarning $false | Out-Null
Update-AzConfig -EnableDataCollection $false | Out-Null
Get-AzConfig

## Connect machine outside of Azure to Azure
## Connect-AzConnectedMachine -ResourceGroupName "rg-hybrid" -SubscriptionId "00000000-0000-0000-0000-000000000000" -Location "australiaeast"

## Automatically connect, if this machine has a Managed Identity (System or User Assigned)
## Can only work if Machine is running inside Azure
## Connect-AzAccount -Identity -ErrorAction Stop

function Connect-AzAccountSilentAuto {
    <#
    .SYNOPSIS
        Silent Azure login using current Windows user (cached context) or Managed Identity.
        Returns an object with TenantId, SubscriptionId, AccountId on success; $false on failure.
    .NOTES
        - Never opens a browser or device code prompt.
        - Does NOT attempt interactive user login.
        - Requires Az.Accounts module.
    #>
    [CmdletBinding()]
    param(
        [switch]$PreferManagedIdentity = $true  # MI first by default
    )

    # Make WAM preferred in this process so cached Windows SSO can be reused (still no UI).
    try { Update-AzConfig -EnableLoginByWam $true -Scope Process | Out-Null } catch {}

    $ctx = $null

    # Helper: return projection
    function _out($c) {
        if (-not $c) { return $false }
        [pscustomobject]@{
            TenantId       = $c.Tenant.Id
            SubscriptionId = $c.Subscription.Id
            AccountId      = $c.Account.Id
            ContextName    = $c.Name
        }
    }

    # Optionally try Managed Identity first (always silent)
    if ($PreferManagedIdentity) {
        try {
            Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
            $ctx = Get-AzContext -ErrorAction Stop
            if ($ctx) { return _out $ctx }
        } catch { }
    }

    # 1) Use an existing cached context if present (silent)
    try { $ctx = Get-AzContext -ErrorAction SilentlyContinue } catch {}
    if (-not $ctx) {
        # If no "current" context, search all cached contexts (still silent)
        try {
            $all = Get-AzContext -ListAvailable -ErrorAction SilentlyContinue
            # Prefer a context that already has a subscription bound
            $ctx = $all | Where-Object { $_.Subscription -and $_.Tenant -and $_.Account } | Select-Object -First 1
            if ($ctx) {
                Set-AzContext -Context $ctx -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }

    if ($ctx) {
        # Validate we can actually get a token without interaction
        try {
            Get-AzAccessToken -ErrorAction Stop | Out-Null
            return _out $ctx
        } catch { }
    }

    # 2) If no cached context worked, try Managed Identity (silent and safe)
    try {
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        $ctx = Get-AzContext -ErrorAction Stop
        if ($ctx) {
            # Note: AccountId will be MSI identity (e.g., appId/objectId), which is expected.
            return _out $ctx
        }
    } catch { }

    # Nothing worked without prompting
    Write-Verbose "No cached user context and no Managed Identity available. Not attempting interactive login."
    return $false
}

## Connect-AzAccount
## Get-AzSubscription -SubscriptionId "<your-subscription-id>" | Format-List

## $resourceCount = (Get-AzResource -ErrorAction SilentlyContinue).Count
## Write-Output "Number of Azure are resources in subscription ($env:AZURE_SUBSCRIPTION_ID) : $resourceCount"



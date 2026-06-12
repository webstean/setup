#Requires -RunAsAdministrator

## Installing developer orientated PowerShell modules

$LanguageMode = $ExecutionContext.SessionState.LanguageMode
switch ($LanguageMode) {
    'ConstrainedLanguage' {
        Write-Host 'Powershell (Constrained): WDAC (Windows Defender Application Control) is actively enforcing CLM (Constrained Language Mode)'
        $IsAdmin = $null -ne (whoami /groups | Select-String "S-1-5-32-544")
        if ($IsAdmin) {
            throw 'This script cannot run, with PowerShell in Constrained Language Mode'
        }
    }
    'FullLanguage' {
        Write-Host 'PowerShell (Full): Either no policy exists OR CLM (Constrained Language Mode) policy is in audit mode'
        $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
}

# Set install scope variable based on elevation
## if ($IsAdmin -and $IsLanguagePermissive) {
if ($IsAdmin) {
    $InstallScope = 'AllUsers'
} else {
    $InstallScope = 'CurrentUser'
}
Write-Host "InstallScope = $InstallScope"

# winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.NuGet
Write-Host "Installing .NET SDK 10..."
try {
    winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.10
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ .NET SDK 10 installed successfully" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to install .NET SDK 9: $($_.Exception.Message)"
}

$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')
try {
    ${INSTALLED_DOTNET_VERSION} = dotnet --version
    if ($?) {
        Write-Host "Installed .NET SDK version: ${INSTALLED_DOTNET_VERSION}" -ForegroundColor Green
    }
}
catch {
    Write-Warning "Failed to get .NET SDK version: $($_.Exception.Message)"
}

## dotnet new globaljson --sdk-version ${INSTALLED_VERSION} --force --roll-forward "latestPatch, latestFeature"
## curl -sSL https://dot.net/v1/dotnet-install.sh | bash -- --version $(jq -r '.sdk.version' global.json)
# winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.10

#Write-Host "Installing .NET SDK Preview..."
#try {
#    winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.Preview
#    if ($LASTEXITCODE -eq 0) {
#        Write-Host "✅ .NET SDK Preview installed successfully" -ForegroundColor Green
#    }
#}
#catch {
#    Write-Warning "Failed to install .NET SDK Preview: $($_.Exception.Message)"
#}

function Install-PSResourceGetSilently {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string] $Scope = 'AllUsers',

        [string] $PowerShellGetVersion = 'Latest',
        [string] $PackageManagementVersion = 'Latest',
        [string] $PSResourceGetVersion = 'Latest',

        [int] $RetryCount = 3,
        [int] $RetryDelaySeconds = 5
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    $names = @(
        'PowerShellGet',
        'PackageManagement',
        'Microsoft.PowerShell.PSResourceGet'
    )

    function Test-IsAdmin {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = [Security.Principal.WindowsPrincipal]::new($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Test-VersionOrLatest {
        param(
            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string] $Value
        )

        if ($Value -ieq 'Latest') {
            return
        }

        $parsedVersion = $null
        if (-not [System.Version]::TryParse($Value, [ref] $parsedVersion)) {
            throw "Parameter '$Name' must be 'Latest' or a valid version number. Value: '$Value'"
        }
    }

    function Install-ModuleVersion {
        param(
            [Parameter(Mandatory)]
            [string] $Name,

            [Parameter(Mandatory)]
            [string] $Version,

            [Parameter(Mandatory)]
            [string] $Scope
        )

        $params = @{
            Name         = $Name
            Scope        = $Scope
            Force        = $true
            AllowClobber = $true
            Confirm      = $false
            ErrorAction  = 'Stop'
        }

        if ($Version -ine 'Latest') {
            $params.RequiredVersion = $Version
        }

        Install-Module @params
    }

    function Invoke-WithRetry {
        param(
            [Parameter(Mandatory)]
            [scriptblock] $Script,

            [Parameter(Mandatory)]
            [string] $Action
        )

        for ($i = 1; $i -le $RetryCount; $i++) {
            try {
                return & $Script
            }
            catch {
                if ($i -ge $RetryCount) {
                    throw "Failed action '$Action'. $($_.Exception.Message)"
                }

                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    Test-VersionOrLatest -Name 'PowerShellGetVersion' -Value $PowerShellGetVersion
    Test-VersionOrLatest -Name 'PackageManagementVersion' -Value $PackageManagementVersion
    Test-VersionOrLatest -Name 'PSResourceGetVersion' -Value $PSResourceGetVersion

    if ($Scope -eq 'AllUsers' -and -not (Test-IsAdmin)) {
        throw 'Scope AllUsers requires an elevated PowerShell session.'
    }

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor
        [Net.SecurityProtocolType]::Tls12

    try {
        Invoke-WebRequest `
            -Uri 'https://www.powershellgallery.com' `
            -UseBasicParsing `
            -ErrorAction Stop |
            Out-Null
    }
    catch {
        throw 'No Internet, proxy, or firewall is blocking access to PowerShell Gallery.'
    }

    if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
        Register-PSRepository -Default
    }

    Set-PSRepository `
        -Name PSGallery `
        -InstallationPolicy Trusted `
        -ErrorAction Stop

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Invoke-WithRetry -Action 'Install NuGet provider' -Script {
                Install-PackageProvider `
                    -Name NuGet `
                    -MinimumVersion 2.8.5.201 `
                    -Force `
                    -Confirm:$false |
                    Out-Null
            }
        }

        Invoke-WithRetry -Action 'Install PackageManagement' -Script {
            Install-ModuleVersion `
                -Name 'PackageManagement' `
                -Version $PackageManagementVersion `
                -Scope $Scope
        }

        Invoke-WithRetry -Action 'Install PowerShellGet' -Script {
            Install-ModuleVersion `
                -Name 'PowerShellGet' `
                -Version $PowerShellGetVersion `
                -Scope $Scope
        }

        Remove-Module PackageManagement -Force -ErrorAction SilentlyContinue
        Remove-Module PowerShellGet -Force -ErrorAction SilentlyContinue

        Import-Module PackageManagement -Force
        Import-Module PowerShellGet -Force
    }

    Invoke-WithRetry -Action 'Install Microsoft.PowerShell.PSResourceGet' -Script {
        Install-ModuleVersion `
            -Name 'Microsoft.PowerShell.PSResourceGet' `
            -Version $PSResourceGetVersion `
            -Scope $Scope
    }

    Remove-Module Microsoft.PowerShell.PSResourceGet -Force -ErrorAction SilentlyContinue
    Import-Module Microsoft.PowerShell.PSResourceGet -Force

    if (Get-Command Get-PSResourceRepository -ErrorAction SilentlyContinue) {
        $repo = Get-PSResourceRepository -Name PSGallery -ErrorAction SilentlyContinue

        if (-not $repo) {
            Register-PSResourceRepository `
                -Name PSGallery `
                -Uri 'https://www.powershellgallery.com/api/v2' `
                -Trusted
        }
        elseif (-not $repo.Trusted) {
            Set-PSResourceRepository `
                -Name PSGallery `
                -Trusted
        }
    }

    Get-Module -Name $names -ListAvailable |
        Sort-Object Name, Version -Descending |
        Select-Object Name, Version, ModuleBase
}
Install-PSResourceGetSilently

### powershell -NoProfile -Command "Install-Module PSReadLine -AllowClobber -Force; Pause"
## New options
#Set-PSReadLineOption -PredictionSource History
#Set-PSReadLineOption -PredictionViewStyle InlineView

### Container Registry - BTW: PSResourceGet expects a NuGet v2 or v3 feed, not a pure OCI registry.
#Register-PSResourceRepository -Name ACR -Uri https://mycompanyregistry.azurecr.io/nuget/v2 -Trusted -ApiVersion ContainerRegistry

## Cleanup User Scope
## Get-PSResource -Scope 'CurrentUser' | Uninstall-PSResource -SkipDependencyCheck

## Delete everything and start again
## Get-PSResource -Scope 'AllUsers' | Uninstall-PSResource -SkipDependencyCheck

function Install-OrUpdate-Module {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ModuleName,

        [ValidateSet('CurrentUser', 'AllUsers')]
        [string] $Scope = 'AllUsers',

        [bool] $Prerelease = $true,

        [bool] $NoUpgrade = $true,

        [bool] $ImportAfter = $true,

        [int] $RetryCount = 3,

        [int] $RetryDelaySeconds = 5
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    function Test-IsAdmin {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p  = [Security.Principal.WindowsPrincipal]::new($id)

        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }

    function Invoke-WithRetry {
        param(
            [Parameter(Mandatory)]
            [scriptblock] $Script,

            [Parameter(Mandatory)]
            [string] $Action
        )

        for ($i = 1; $i -le $RetryCount; $i++) {
            try {
                return & $Script
            }
            catch {
                if ($i -ge $RetryCount) {
                    throw "Failed action '$Action'. $($_.Exception.Message)"
                }

                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    if ($Scope -eq 'AllUsers' -and -not (Test-IsAdmin)) {
        throw 'Scope=AllUsers requires an elevated PowerShell session.'
    }

    $hadVerboseDefault = $PSDefaultParameterValues.ContainsKey('*:Verbose')
    $prevVerbose = $PSDefaultParameterValues['*:Verbose']
    $PSDefaultParameterValues['*:Verbose'] = $false

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor
            [Net.SecurityProtocolType]::Tls12

        if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
            $psg = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue

            if ($psg -and $psg.InstallationPolicy -ne 'Trusted') {
                Set-PSRepository -Name PSGallery -InstallationPolicy Trusted | Out-Null
            }
        }

        if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
            if (
                $PSVersionTable.PSVersion.Major -lt 6 -and
                (Get-Command Install-PackageProvider -ErrorAction SilentlyContinue) -and
                -not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)
            ) {
                Invoke-WithRetry -Action 'Install NuGet provider' -Script {
                    Install-PackageProvider `
                        -Name NuGet `
                        -MinimumVersion 2.8.5.201 `
                        -Force `
                        -Confirm:$false |
                        Out-Null
                }
            }

            Invoke-WithRetry -Action 'Install Microsoft.PowerShell.PSResourceGet' -Script {
                Install-Module `
                    -Name Microsoft.PowerShell.PSResourceGet `
                    -Scope $Scope `
                    -Force `
                    -AllowClobber `
                    -Confirm:$false
            }

            Import-Module Microsoft.PowerShell.PSResourceGet -Force
        }

        $repoName = 'PSGallery'
        $repoUri  = 'https://www.powershellgallery.com/api/v2'

        $repo = Get-PSResourceRepository -Name $repoName -ErrorAction SilentlyContinue

        if (-not $repo) {
            Register-PSResourceRepository `
                -Name $repoName `
                -Uri $repoUri `
                -ApiVersion V2 `
                -Trusted |
                Out-Null
        }
        elseif (-not $repo.Trusted) {
            Set-PSResourceRepository -Name $repoName -Trusted | Out-Null
        }

        $alreadyInstalled = @(Get-Module -ListAvailable -Name $ModuleName)

        $resourceParams = @{
            Name            = $ModuleName
            Repository      = $repoName
            Scope           = $Scope
            TrustRepository = $true
            AcceptLicense   = $true
            Quiet           = $true
            ErrorAction     = 'Stop'
            WarningAction   = 'SilentlyContinue'
        }

        if ($Prerelease) {
            $resourceParams.Prerelease = $true
        }

        if ($alreadyInstalled.Count -eq 0) {
            Write-Host "Installing '$ModuleName' ($Scope)..." -ForegroundColor Green

            Invoke-WithRetry -Action "Install $ModuleName" -Script {
                Install-PSResource @resourceParams | Out-Null
            }
        }
        elseif ($NoUpgrade) {
            $latestInstalled = $alreadyInstalled |
                Sort-Object Version -Descending |
                Select-Object -First 1

            Write-Host "Skipping upgrade for '$ModuleName'. Already installed. Version: $($latestInstalled.Version)" -ForegroundColor Yellow
        }
        else {
            Write-Host "Updating '$ModuleName' ($Scope)..." -ForegroundColor Cyan

            Invoke-WithRetry -Action "Update $ModuleName" -Script {
                Update-PSResource @resourceParams | Out-Null
            }
        }

        if ($ImportAfter) {
            try {
                Import-Module $ModuleName -Force -ErrorAction Stop
            }
            catch {
                Write-Host "Installed '$ModuleName' but Import-Module failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        $latest = Get-Module -ListAvailable -Name $ModuleName |
            Sort-Object Version -Descending |
            Select-Object -First 1

        if ($latest) {
            Write-Host "'$ModuleName' available. Version: $($latest.Version)" -ForegroundColor Green
            return $latest
        }

        Write-Host "'$ModuleName' install/update completed." -ForegroundColor Green
    }
    catch {
        Write-Host "Failed for '$ModuleName': $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
    finally {
        if ($hadVerboseDefault) {
            $PSDefaultParameterValues['*:Verbose'] = $prevVerbose
        }
        else {
            $null = $PSDefaultParameterValues.Remove('*:Verbose')
        }
    }
}
## Get rid of deprecated modules, in case they are still here
if (Get-Module -Name AzureAD -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD -Force -ErrorAction SilentlyContinue
}
if (Get-Module -Name AzureAD.Standard.Preview -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD.Standard.Preview -Force -ErrorAction SilentlyContinue
}

Install-OrUpdate-Module PSWindowsUpdate
Install-OrUpdate-Module Terminal-Icons
Install-OrUpdate-Module Az.Tools.Migration
Install-OrUpdate-Module Az.Accounts
Install-OrUpdate-Module Az.Storage
Install-OrUpdate-Module Az.Compute
Install-OrUpdate-Module Az.Resources
Install-OrUpdate-Module Az.Keyvault
Install-OrUpdate-Module Az.Network
Install-OrUpdate-Module Az.Functions
Install-OrUpdate-Module Az.ContainerRegistry
Install-OrUpdate-Module Microsoft.WinGet.Client
Install-OrUpdate-Module Microsoft.WinGet.Configuration
Install-OrUpdate-Module Microsoft.Graph ## big, but installing bits of it, causes problems later, due to different versions
Install-OrUpdate-Module MicrosoftTeams
#Install-OrUpdate-Module VMware.PowerCLI ## VMware PowerCLI (is too big - and no very useful, post-Broadcom)
Install-OrUpdate-Module Microsoft.PowerApps.Administration.PowerShell
Install-OrUpdate-Module Microsoft.PowerPlatform.EnterprisePolicies
Install-OrUpdate-Module JWTDetails
Install-OrUpdate-Module PnP.PowerShell

## Connect-PnPOnline -url
## Sites.ReadWrite.All     – read/write to all site collections the user can access.
## Sites.Manage.All        - lets you manage site permissions via Graph.         –
#if ( $env:SHAREPOINT_ADMIN ) {
#    Connect-PnPOnline -Url "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com" -Interactive
#    Set-Item -Path Env:\SHAREPOINT_ACCESS_TOKEN -Value (Get-PnPAccessToken -decoded).EncodedToken
#    Get-PnPAccessToken -Decoded
#    (Get-PnPAccessToken -decoded).EncodedToken
#    Connect-PnPOnline -Url "https://${env:AZURE_SHAREPOINT_ADMIN}.sharepoint.com" -AccessToken $env:SHAREPOINT_ACCESS_TOKEN
#    Get-PnpConnection
#    Get-PnPAuthenticationRealm
#    Get-PnPTenant
#    Get-PnPTenantSite
#    Get-PnPTenantAppCatalogUrl
#    Get-PnPTenantSyncClientRestriction
#    Get-PnPTenantCdnEnabled
#    Get-PnPTenantCdnOrigins
#    Get-PnPTenantAllowBlockList
#    Get-PnPTenantSiteClassification
#    Get-PnPOrgNewsSite
#    Get-PnPSiteDesign
#    Disconnect-PnpOnline
#}

## Add-PowerAppsAccount -Endpoint prod

# Example PowerApp environment creation (commented out):
# $jsonObject = @" 
# { 
#  "PostProvisioningPackages": 
#  [ 
#  { 
#     "applicationUniqueName": "msdyn_FinanceAndOperationsProvisioningAppAnchor", 
#     "parameters": "DevToolsEnabled=true|DemoDataEnabled=true" 
#  } 
#  ] 
# } 
# "@ | ConvertFrom-Json
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
Install-OrUpdate-Module Az.Tools.Predictor
Import-Module Az.Tools.Predictor

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
# azd config set platform.type devcenter
# azd config unset platform.type devcenter
azd extension install azure.coding-agent
azd extension install azure.ai.agents
# then: azd coding-agent config   - in each repo

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
        [switch]$PreferManagedIdentity  # MI first by default
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

    # Try Managed Identity first if preferred (always silent)
    if ($PreferManagedIdentity.IsPresent) {
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



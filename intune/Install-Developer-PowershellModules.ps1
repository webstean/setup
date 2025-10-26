#Requires -RunAsAdministrator

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
    $installed = Get-PSResource -Name $ModuleName -ErrorAction SilentlyContinue

    # Common params
    $commonParams = @{
        Name = $ModuleName
        ErrorAction = 'Stop'
    }
    if ($ScopeCurrentUser) { $commonParams['Scope'] = 'CurrentUser' }
    if ($Prerelease) { $commonParams['Prerelease'] = $true }

    try {
        if ($null -eq $installed) {
            Write-Host "Module '$ModuleName' not found. Installing..." -ForegroundColor Green
            Install-PSResource @commonParams
        }
        else {
            Write-Host "Module '$ModuleName' found. Updating..." -ForegroundColor Cyan
            Update-PSResource @commonParams
        }

        # Optional: import after install/update
        Import-Module $ModuleName -Force
        Write-Host "✅ '$ModuleName' is installed and up to date." -ForegroundColor Green
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

## Install Vmware PowerCLI (its too big)
#if ( -not (Get-Module -Name VMware.PowerCLI -ListAvailable)) {
#    Install-Module -Name VMware.PowerCLI  -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
#} else {
#    Update-Module VMware.PowerCLI -Force -Scope $installscope -ErrorAction SilentlyContinue
#} 
#Get-InstalledModule -Name VMware.PowerCLI

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
if ( -not (Get-Module -Name Az.Tools.Predictor -ListAvailable -ErrorAction SilentlyContinue)) {
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
Update-AzConfig -CheckForUpgrade $false | Out-Null
Update-AzConfig -DisplayRegionIdentified $true | Out-Null
Update-AzConfig -DisplaySecretsWarning $false | Out-Null
Update-AzConfig -EnableDataCollection $false | Out-Null

## Connect-AzAccount -Identity -AccountId <user-assigned-identity-clientId-or-resourceId>
## Connect-AzAccount
## Get-AzSubscription -SubscriptionId "<your-subscription-id>" | Format-List

## $resourceCount = (Get-AzResource -ErrorAction SilentlyContinue).Count
## Write-Output "Number of Azure are resources in subscription ($env:AZURE_SUBSCRIPTION_ID) : $resourceCount"



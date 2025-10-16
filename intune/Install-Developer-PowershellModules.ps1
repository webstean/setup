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
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Register-PSRepository -Default -ErrorAction SilentlyContinue
Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted -ErrorAction SilentlyContinue
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



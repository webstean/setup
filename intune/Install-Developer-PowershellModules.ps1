#Requires -RunAsAdministrator

$installscope = "CurrentUser"

winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.9
${INSTALLED_DOTNET_VERSION} = dotnet --version
Write-Host "Installed .NET SDK version: ${INSTALLED_DOTNET_VERSION}"
## dotnet new globaljson --sdk-version ${INSTALLED_VERSION} --force --roll-forward "latestPatch, latestFeature"
## curl -sSL https://dot.net/v1/dotnet-install.sh | bash -- --version $(jq -r '.sdk.version' global.json)
#winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.10
winget install --silent --accept-source-agreements --accept-package-agreements --exact --id=Microsoft.DotNet.SDK.Preview

## Provider: PSGallery
Write-Output "Enable PSGallery..."
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
Install-Module -Name Terminal-Icons -Repository PSGallery -scope CurrentUser
Install-Module -Name PSReadline -Force -scope CurrentUser
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
if (!(Get-Module -Name Az -ListAvailable)) {
    Write-Output ("Installing AZ (Azure) Powershell module...")
    Install-Module Az -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    # Display AZ Modules
    Get-InstalledModule -Name Az
    Write-Output ("Updating AZ (Azure) Powershell module...")
    Update-Module Az -Force -Scope $installscope -ErrorAction SilentlyContinue
}

## Get rid of depreciated modules
if (Get-Module -Name AzureAD -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD -Force -ErrorAction SilentlyContinue
}
if (Get-Module -Name AzureAD.Standard.Preview -ListAvailable -ErrorAction SilentlyContinue) {
    Uninstall-Module AzureAD.Standard.Preview -Force -ErrorAction SilentlyContinue
}

if (-not (Get-Module -Name Microsoft.WinGet.Configuration -ListAvailable -ErrorAction SilentlyContinue)) {
    Install-Module -Name Microsoft.WinGet.Configuration -AllowPrerelease -AcceptLicense -Force
}
## $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
## get-WinGetConfiguration -file .\.configurations\vside.dsc.yaml | Invoke-WinGetConfiguration -AcceptConfigurationAgreements



## Example
## 'Az.ImageBuilder', 'Az.ManagedServiceIdentity' | ForEach-Object {Install-Module -Name $_ -AllowPrerelease}

## Microsoft Graph Modules
if (!(Get-Module -Name Microsoft.Graph -ListAvailable)) {
    Write-Output ("Installing Microsoft Graph Powershell modules...")
    Install-Module Microsoft.Graph -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Updateing Microsoft Graph Powershell modules...")
    Update-Module Microsoft.Graph -Force -Scope $installscope -ErrorAction SilentlyContinue
} 
Get-InstalledModule -Name Microsoft.Graph

## Install Teams Modules
if (!(Get-Module -Name MicrosoftTeams -ListAvailable)) {
    Write-Output ("Installing Microsoft Teams Powershell modules...")
    Install-Module MicrosoftTeams -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Write-Output ("Upgrading Microsoft Teams Powershell modules...")
    Update-Module MicrosoftTeams -Force -Scope $installscope -ErrorAction SilentlyContinue
} 
Get-InstalledModule -Name MicrosoftTeams

## Install Vmware PowerCLI
if (!(Get-Module -Name VMware.PowerCLI -ListAvailable)) {
    Install-Module -Name VMware.PowerCLI  -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
} else {
    Update-Module VMware.PowerCLI -Force -Scope $installscope -ErrorAction SilentlyContinue
} 
Get-InstalledModule -Name VMware.PowerCLI

## Install AZ Predictor
if (!(Get-Module -Name PSReadline -ListAvailable)) {
    Install-Module PSReadline -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
}
if (!(Get-Module -Name Az.Accounts -ListAvailable)) {
    Install-Module Az.Accounts -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
}
if (!(Get-Module -Name Az.Tools.Predictor -ListAvailable)) {
    Install-Module Az.Tools.Predictor -Force -Scope $installscope -AllowClobber -Repository PSGallery -ErrorAction SilentlyContinue
}
Import-Module Az.Tools.Predictor
Enable-AzPredictor -AllSession
Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
# Set-PSReadLineOption -PredictionViewStyle InlineView

## Install Help for all installed modules
## Start-Process -Wait -Verb RunAs pwsh.exe -ArgumentList "-Command {Update-Help -UICulture en-AU -Force}" -RedirectStandardOutput "aw.txt"
## Start-Process -Wait pwsh.exe -ArgumentList "-Command {Update-Help -UICulture en-AU -Force}"
if (-not (Get-Help -Name Get-Command -ErrorAction SilentlyContinue | Where-Object { $_.Category -eq "HelpFile" })) {
    Update-Help -UICulture en-AU -Force -ErrorAction SilentlyContinue | Out-Null
}

## Connect-AzAccount -Identity -AccountId <user-assigned-identity-clientId-or-resourceId>
## Connect-AzAccount
## $resourceCount = (Get-AzResource -ErrorAction SilentlyContinue).Count
## Write-Output "Number of Azure resources: $resourceCount"

Update-AzConfig -DisplayBreakingChangeWarning $false | Out-Null
Update-AzConfig -DisplaySurveyMessage $false | Out-Null
Update-AzConfig -EnableLoginByWam $true | Out-Null
## Update-AzConfig -DefaultSubscriptionForLogin $env:AZURE_SUBSCRIPTION_ID
Update-AzConfig -CheckForUpgrade $false | Out-Null
Update-AzConfig -DisplayRegionIdentified $true | Out-Null
Update-AzConfig -DisplaySecretsWarning $false | Out-Null
Update-AzConfig -EnableDataCollection $false | Out-Null

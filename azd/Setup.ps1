param(
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentName
)

$ErrorActionPreference = "Stop"

# Assume repo layout:
# repo/
#   scripts/sync-azd-config-to-tfvars.ps1
#   .azure/<env>/config.json
$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$configPath = Join-Path $repoRoot ".azure/$EnvironmentName/config.json"
$envPath    = Join-Path $repoRoot ".azure/$EnvironmentName/.env"

if (-not (Test-Path $configPath)) {
    throw "Config file not found: $configPath"
}

$configJson = Get-Content $configPath -Raw | ConvertFrom-Json

# Pull values we care about
$azureLocation      = $configJson.AZURE_LOCATION
$resourceGroup      = $configJson.AZURE_RESOURCE_GROUP
$environmentNameVal = $configJson.ENVIRONMENT_NAME
$acaEnvName         = $configJson.ACA_ENV_NAME

if (-not $azureLocation -or -not $environmentNameVal) {
    throw "config.json must contain AZURE_LOCATION and ENVIRONMENT_NAME."
}

# Parse existing .env into a hashtable (if it exists)
$envMap = @{}

if (Test-Path $envPath) {
    Get-Content $envPath | ForEach-Object {
        $line = $_.Trim()
        if (-not $line || $line.StartsWith("#")) { return }

        $parts = $line -split "=", 2
        if ($parts.Count -eq 2) {
            $key = $parts[0].Trim()
            $val = $parts[1]
            $envMap[$key] = $val
        }
    }
}

# Inject / overwrite keys from config.json
$envMap["ENVIRONMENT_NAME"]       = $environmentNameVal
$envMap["AZURE_LOCATION"]         = $azureLocation
if ($resourceGroup) { $envMap["AZURE_RESOURCE_GROUP"] = $resourceGroup }
if ($acaEnvName)    { $envMap["ACA_ENV_NAME"]        = $acaEnvName  }

# Terraform variables – this is what Terraform actually sees
$envMap["TF_VAR_location"]         = $azureLocation
$envMap["TF_VAR_environment_name"] = $environmentNameVal

# Write back sorted .env
$envDir = Split-Path $envPath
if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Force -Path $envDir | Out-Null
}

$lines =
    $envMap.GetEnumerator() |
    Sort-Object Name |
    ForEach-Object { "$($_.Name)=$($_.Value)" }

$lines | Set-Content -Encoding UTF8 $envPath

Write-Host "Updated $envPath"

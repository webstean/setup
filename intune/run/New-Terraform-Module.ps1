# Placeholder file templates for Terraform module scaffold
$script:TemplateVersionsTf = @'
terraform {
  required_version = ">= 1.9.0, < 2.0"

  required_providers {
    azurerm = {
      ## Azure resource manager
      source  = "hashicorp/azurerm"
      version = "~>4.0, < 5.0"
    }
    azuread = {
      ## Azure AD (Entra ID)
      source  = "hashicorp/azuread"
      version = "~>3.0, < 4.0"
    }
    msgraph = {
      ## Microsoft Graph - replacement for azuread *future*
      version = "~> 0.0, < 1.0"
      source  = "microsoft/msgraph"
    }
    azapi = {
      ## use for Azure resources that are not directly support by azurerm or azuread providers
      source  = "azure/azapi"
      version = "~>2.0, < 3.0"
    }
    random = {
      ## Random
      source  = "hashicorp/random"
      version = "~>3.0, < 4.0"
    }
  }
}

provider "azurerm" {
  ## "extended" is chosen over "automatic" to ensure all recommended and custom resource providers are registered, as required by Azure Landing Zones and advanced scenarios.
  resource_provider_registrations = "extended"
  ## These are recommendations from the Azure Landing Zone, plus some others :-)
  resource_providers_to_register = [
    "Microsoft.Advisor",
    "Microsoft.AlertsManagement",
    "Microsoft.App",
    "Microsoft.ApiCenter",
    "Microsoft.ApiManagement",
    "Microsoft.Automation",
    "Microsoft.AzureTerraform",
    "Microsoft.Cache",
    "Microsoft.Capacity",
    "Microsoft.CodeSigning",
    "Microsoft.Communication",
    "Microsoft.Compute",
    "Microsoft.Compute/EncryptionAtHost",
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.DataBoxEdge",
    "Microsoft.Dashboard",
    "Microsoft.DevCenter",
    "Microsoft.DeviceUpdate",
    "Microsoft.DevOpsInfrastructure",
    "Microsoft.DevTestLab",
    "Microsoft.EdgeZones",
    "Microsoft.EventGrid",
    "Microsoft.ExtendedLocation",
    "Microsoft.GuestConfiguration",
    "Microsoft.HorizonDB",
    "Microsoft.Insights",
    "Microsoft.IoTSecurity",
    "Microsoft.IoTOperations",
    "Microsoft.KeyVault",
    "Microsoft.Monitor",
    "Microsoft.ManagedIdentity",
    "Microsoft.ManagedOps",
    "Microsoft.ManagedServices",
    "Microsoft.Management",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
    "Microsoft.Purview",
    "Microsoft.RecoveryServices",
    "Microsoft.ResourceHealth",
    "Microsoft.Security",
    "Microsoft.SecurityInsights",
    "Microsoft.ServiceLinker",
    "Microsoft.StandbyPool",
    "Microsoft.Storage",
    "Microsoft.Sql",
    "Microsoft.VerifiedId",
    "NGINX.NGINXPLUS",
  ]
  features {
    enhanced_validation {
      preflight_enabled = true
    }
    app_configuration {
      purge_soft_delete_on_destroy = false
      recover_soft_deleted         = true
    }
    api_management {
      purge_soft_delete_on_destroy = false # Keep soft-deleted API Management resources for recovery.
      recover_soft_deleted         = true  # Automatically recover soft-deleted API Management resources.
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false # Allow deletion of resource groups even if they contain resources.
    }
    key_vault {
      purge_soft_delete_on_destroy    = false # Retain soft-deleted Key Vaults for potential recovery.
      recover_soft_deleted_key_vaults = true  # Automatically recover soft-deleted Key Vaults.
    }
    log_analytics_workspace {
      permanently_delete_on_destroy = true # Ensure Log Analytics Workspaces are permanently deleted on destroy.
    }
    machine_learning {
      purge_soft_deleted_workspace_on_destroy = true # Permanently delete soft-deleted ML workspaces on destroy.
    }
    virtual_machine {
      delete_os_disk_on_deletion = true # Automatically delete OS disks when deleting VMs.
    }
    template_deployment {
      delete_nested_items_during_deletion = false # Do not delete nested items during template deployment deletion.
    }
  }
  storage_use_azuread = true
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "msgraph" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "azuread" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
}

provider "azapi" {
  ## Authentication strategy: Prefer OIDC and Azure CLI for authentication;
  ## Managed Identity and AKS Workload Identity are disabled for explicit control and compatibility.
  use_oidc                  = true
  use_aks_workload_identity = false
  use_msi                   = false
  use_cli                   = true
  enable_preflight          = true
}

resource "azurerm_resource_provider_feature_registration" "encryption_at_host" {
  provider_name = "Microsoft.Compute"
  name          = "EncryptionAtHost"
}
'@

$script:TemplateExampleVersionsTf = @'
terraform {
  required_version = ">= 1.3.0"
}
'@

$script:TemplateExampleMainTf = @'
module "example" {
  source = "../../"
}
'@

$script:TemplateTerraformDocsYml = @'
formatter: "markdown table"

output:
  file: README.md
  mode: inject
  template: |-
    <!-- BEGIN_TF_DOCS -->
    {{ .Content }}
    <!-- END_TF_DOCS -->

sections:
  show:
    - requirements
    - providers
    - modules
    - resources
    - inputs
    - outputs
'@

$script:TemplateGitignore = @'
.terraform/
.terraform.lock.hcl
*.tfstate
*.tfstate.backup
*.tfvars
!example*.tfvars
override.tf
override.tf.json
*_override.tf
*_override.tf.json
crash.log
crash.*.log
'@

$script:TemplateCiWorkflow = @'
name: Terraform-Modules-Docs

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}

on:
  workflow_dispatch:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write
  contents: write

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        continue-on-error: true

      - uses: hashicorp/setup-terraform@v4

      - name: terraform fmt
        run: terraform fmt -check -recursive

      - name: terraform init
        run: terraform init -backend=false

      - name: terraform validate
        run: terraform validate

  docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.ref }}

      - uses: terraform-docs/gh-actions@v1
        with:
          working-dir: .
          output-file: README.md
          output-method: inject
          git-push: "true"
'@

function New-TerraformModuleRepo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, HelpMessage = 'Name of the Terraform module')]
    [string]$ModuleName,

    [string]$Provider = 'azurerm',

    [Parameter(Mandatory = $true, HelpMessage = 'Description of the module for the GitHub repository')]
    [string]$Description,

    [string]$Owner = 'webstean'
  )

  $repoName = "terraform-$Provider-$ModuleName"
  Write-Host "Creating Terraform module repository: '$repoName'"

  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) not found. Install via: winget install GitHub.cli'
  }

  if (-not (gh auth status 2>&1 | Select-String 'Logged in')) {
    throw 'Not authenticated. Run: gh auth login'
  }

  if (-not $Owner) {
    $Owner = (gh api user | ConvertFrom-Json).login
  }
  Write-Host "Repository owner is: '$Owner'"

  Write-Host "Checking (with view)....'${owner}/$repoName'"
  if (gh repo view ${owner}/${repoName} 2>$null) {
    Write-Host "'gh repo delete $Owner/$repoName --yes'"
    Write-Host "'gh auth refresh -s delete_repo'"
    throw 'Repository directory already exists.'
  }
  $desc = if ($Description) { $Description } else { "Terraform module for $ModuleName with provider $Provider" }
  if (-not (gh repo create $Owner/$repoName --description "$Description" --public )) {
    throw 'Failed to create repository.'
  }

  $repoPath = Join-Path (Get-Location) $repoName
  if (Test-Path $repoPath) { 
    throw "Repository path '$repoPath' already exists."
  }
  New-Item -ItemType Directory -Path $repoPath -Force -ErrorAction SilentlyContinue | Out-Null
  Write-Host "Repository path is: '$repoPath'"
  if (-not (Test-Path $repoPath)) { 
    throw "Repository path '$repoPath' does not exist."
  }
  Push-Location $repoPath -ErrorAction SilentlyContinue

  try {
    $dirs = @(
      'modules',
      'examples/complete',
      'examples/basic',
      'tests'
    )
    foreach ($dir in $dirs) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $script:TemplateVersionsTf | Set-Content 'versions.tf'
    '# Input variables' | Set-Content 'variables.tf'
    '# Resources' | Set-Content 'main.tf'
    '# Outputs' | Set-Content 'outputs.tf'

    $script:TemplateExampleMainTf | Set-Content 'examples/basic/main.tf'
    $script:TemplateExampleVersionsTf | Set-Content 'examples/basic/versions.tf'

    '' | Set-Content 'examples/basic/variables.tf'
    '' | Set-Content 'examples/basic/outputs.tf'

    Copy-Item 'examples/basic/main.tf' 'examples/complete/main.tf'
    Copy-Item 'examples/basic/versions.tf' 'examples/complete/versions.tf'
    Copy-Item 'examples/basic/variables.tf' 'examples/complete/variables.tf'
    Copy-Item 'examples/basic/outputs.tf' 'examples/complete/outputs.tf'

    '# go test -v -timeout 30m' | Set-Content 'tests/main_test.go'

    $script:TemplateTerraformDocsYml | Set-Content '.terraform-docs.yml'

    $script:TemplateGitignore | Set-Content '.gitignore'

    @"
# terraform-$Provider-$ModuleName

$desc

## Usage

``````hcl
module "$ModuleName" {
  source  = "$Owner/$ModuleName/$Provider"
  version = "~> 1.0"
}
``````

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->

## Examples

- [Basic](./examples/basic)
- [Complete](./examples/complete)

## Contributing

Contributions welcome. Please open an issue or PR.

## License

MIT
"@ | Set-Content 'README.md'

    @"
MIT License

Copyright (c) $(Get-Date -Format yyyy)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@ | Set-Content 'LICENSE'

    Get-Location
    New-Item -ItemType Directory -Path '.github/workflows' -Force | Out-Null
    $script:TemplateCiWorkflow | Set-Content '.github/workflows/ci-terraform-docs.yml'

    git init
    git add -A
    git commit -m 'initial commit'
    git branch -M main
    git remote add origin https://github.com/$Owner/${repoName}.git
    git push -u origin main

    git tag v0.1.0
    git push origin v0.1.0

    Write-Host 'Creating placeholder secrets...'
    @{
      AZURE_CLIENT_ID       = 'REPLACE_ME'
      AZURE_TENANT_ID       = 'REPLACE_ME'
      AZURE_SUBSCRIPTION_ID = 'REPLACE_ME'
    }.GetEnumerator() | ForEach-Object {
      gh secret set $_.Key --body $_.Value --repo "$Owner/$repoName"
    }

    Write-Host ''
    Write-Host "Repository : '$Owner/$repoName'"
    Write-Host "Path       : '$repoPath'"
    Write-Host ''
    Write-Host 'GitHub Secrets created (Optional, update with real values, if required):'
    Write-Host ' AZURE_CLIENT_ID'
    Write-Host ' AZURE_TENANT_ID'
    Write-Host ' AZURE_SUBSCRIPTION_ID'
    Write-Host ''
    Write-Host ' Requirements checklist:'
    Write-Host " [x] Repo named '$repoPath'"
    Write-Host ' [x] Public repository'
    Write-Host ' [x] main.tf / variables.tf / outputs.tf present'
    Write-Host ' [x] v0.1.0 tag pushed'
    Write-Host " [ ] GitHub OAuth app must be authorized for '$Owner' org/account"
    Write-Host ' https://github.com/settings/connections/applications/b0e1b0f5f7ca9fb13c7d'
    Write-Host ''
    Write-Host ' Once published, module source for Terraform will be:'
    Write-Host ''
    Write-Host "  module '$ModuleName' {"
    Write-Host "    source           = '$Owner/$ModuleName/$Provider'"
    Write-Host "    version          = '~>0.0, < 1.0'"
    Write-Host '    enable_telemetry = var.enable_telemetry'
    Write-Host ''
    Write-Host ' ...'
    Write-Host ''
    Write-Host '  }'
    Write-Host ''
    Write-Host 'Terraform Registry Publishing:'
    Write-Host ' 1. Sign in at 'https://registry.terraform.io' with your GitHub account'
    Write-Host " 2. Click 'Publish' > 'Module'"
    Write-Host " 3. Select the '$repoName' repository"
    Write-Host ' 4. Confirm — registry will detect versions from git tags (v0.1.0 already pushed)'
    Write-Host ''
    Write-Host 'Nothing will appear, until you do a release'
    Write-Host 'gh release create v0.99 --generate-notes --target main'
    Write-Host ''

    # Final script output for automation/consumers
    Write-Output ([pscustomobject]@{
        RepoOwner  = $Owner
        RepoName   = $repoName
        ModuleName = $ModuleName
      })

  } finally {
    Pop-Location
  }
}

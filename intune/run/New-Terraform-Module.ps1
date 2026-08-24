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

$script:TemplateEditorConfig = @'
# EditorConfig: Windows dev host, Azure Container Apps (.NET Aspire), WSL/Linux targets
root = true

# ---- Global defaults ----
[*]
charset = utf-8
indent_style = space
indent_size = 4
end_of_line = crlf
insert_final_newline = true
trim_trailing_whitespace = true
max_line_length = off

# ---- C# / .NET Aspire / ACA projects ----
[*.{cs,csx}]
indent_size = 4
end_of_line = crlf
csharp_new_line_before_open_brace = all
csharp_indent_case_contents = true
csharp_prefer_braces = true
dotnet_sort_system_directives_first = true
dotnet_style_qualification_for_field = false
dotnet_style_qualification_for_property = false
dotnet_style_qualification_for_method = false
dotnet_style_predefined_type_for_locals_parameters_members = true
csharp_style_var_for_built_in_types = false
csharp_style_var_when_type_is_apparent = true
csharp_style_namespace_declarations = file_scoped

[*.{csproj,props,targets}]
indent_size = 2
end_of_line = crlf

# ---- PowerShell (WSL provisioning, Az automation) ----
[*.{ps1,psm1,psd1}]
indent_size = 4
end_of_line = crlf
charset = utf-8-bom

# ---- Terraform (AzureRM / AzureAD / AzApi) ----
[*.{tf,tfvars}]
indent_size = 2
end_of_line = lf
insert_final_newline = true

[*.tfstate]
insert_final_newline = false

# ---- Bash / WSL provisioning scripts ----
[*.sh]
indent_size = 2
end_of_line = lf
insert_final_newline = true

# ---- Dockerfiles (ACA container builds) ----
[{Dockerfile,Dockerfile.*,*.dockerfile}]
indent_size = 4
end_of_line = lf

# ---- YAML (pipelines, ACA revisions, k8s-adjacent manifests) ----
[*.{yml,yaml}]
indent_size = 2
end_of_line = lf

# ---- JSON / Bicep-adjacent / ARM ----
[*.{json,jsonc,bicep}]
indent_size = 2
end_of_line = lf

# ---- Markdown docs ----
[*.md]
indent_size = 2
trim_trailing_whitespace = false
end_of_line = lf

# ---- Batch files (rare, but Windows-native) ----
[*.{cmd,bat}]
end_of_line = crlf

# ---- Makefiles require literal tabs ----
[Makefile]
indent_style = tab
end_of_line = lf
'@

$script:TemplateGitAttributes = @'
# Default: normalize all text files and prefer LF in the repo
* text=auto eol=lf

# Windows batch/cmd usually expects CRLF
*.bat  text eol=crlf
*.cmd  text eol=crlf
*.ps1xml text eol=lf

# PowerShell  usually expects CRLF
*.ps1  text eol=crlf
*.psm1 text eol=crlf
*.psd1 text eol=crlf

# Shell / scripts
*.sh   text eol=lf
*.bash text eol=lf
*.zsh  text eol=lf

# IaC / config
*.tf        text eol=lf
*.tfvars    text eol=lf
*.hcl       text eol=lf
*.yml       text eol=lf
*.yaml      text eol=lf
*.json      text eol=lf
*.md        text eol=lf
*.txt       text eol=lf

# Binary (never touch line endings)
*.png  binary
*.jpg  binary
*.jpeg binary
*.gif  binary
*.pdf  binary
*.zip  binary
*.7z   binary
*.exe  binary
*.dll  binary
'@

$script:Dependabot = @'
---
# Dependabot version updates
#
# Dependabot security updates (CVE-driven) are enabled at the repository level
# via Terraform; this file enables proactive *version* updates for pinned
# provider versions.
#
# Docs: https://docs.github.com/en/code-security/dependabot/dependabot-version-updates/configuration-options-for-the-dependabot.yml-file
version: 2

updates:
  # Terraform providers in the root module, examples, and any submodules.
  - package-ecosystem: terraform
    directories:
      - "/"
      - "/examples/**"
      - "/modules/**"
    schedule:
      interval: weekly
      day: monday
      time: "06:00"
      timezone: Etc/UTC
    groups:
      terraform:
        patterns:
          - "*"
    labels:
      - "Language: Terraform :globe_with_meridians:"
    commit-message:
      prefix: chore
      include: scope
'@

$script:TemplateVsCodeSettings = @'
{
    "files.autoSave": "afterDelay",
    "editor.defaultFormatter": "GitHub.copilot-chat",
    "editor.fontFamily": "FiraCode",
    "[powershell]": {
        "editor.defaultFormatter": "ms-vscode.powershell"
    },
    "[github-actions-workflow]": {
        "editor.defaultFormatter": "esbenp.prettier-vscode"
    },
    "[terraform]": {
        "editor.defaultFormatter": "hashicorp.terraform"
    }
}
'@

$script:TemplateVsCodeExtensions = @'
{
  "recommendations": [
    "EditorConfig.EditorConfig",
    "hashicorp.terraform",
    "ms-azuretools.vscode-azureterraform"
  ]
}
'@

$script:TemplateWelcome = @'
# Welcome to Your Terraform Module

This repository was scaffolded to help you build and publish a reusable Terraform module with a clean structure and CI-ready defaults.

## What's Included

- Module entry files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- Examples: `examples/basic` and `examples/complete`
- Validation and docs workflow in `.github/workflows`
- Formatting and editor standards via `.editorconfig` and `.gitattributes`

## Quick Start

1. Review and update module inputs in `variables.tf`
2. Implement resources in `main.tf`
3. Add outputs in `outputs.tf`
4. Test examples from `examples/basic` and `examples/complete`

## Useful Commands

```bash
terraform fmt -recursive
terraform init
terraform validate
```

## Next Steps

- Update GitHub secrets for CI:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- Create a release tag when ready to publish
- Keep README docs in sync with `terraform-docs`

Happy building.
'@


$script:TemplateDevContainer = @'
{
  "$schema": 'https://raw.githubusercontent.com/devcontainers/spec/main/schemas/devContainer.schema.json',
  'name': 'Azure Terraform',
  'image': 'mcr.microsoft.com/devcontainers/dotnet',
  'features': {
    'ghcr.io/devcontainers/features/github-cli:1': {
      'version': 'latest'
    },
    'ghcr.io/devcontainers/features/docker-in-docker:2': {},
    'ghcr.io/azure/azure-dev/azd:latest': {},
    'ghcr.io/devcontainers/features/azure-cli:1': {
      'version': 'latest'
    },
    'ghcr.io/devcontainers/features/terraform:1': {
      'version': 'latest',
      'installTFsec': 'true',
      'installTerraformDocs': 'true'
    },
    'ghcr.io/devcontainers/features/node:1': {
      'version': 'latest'
    },
    'ghcr.io/devcontainers/features/powershell:1': {
      'version': 'latest'
    },
    'ghcr.io/devcontainers/features/dotnet:2': {
      'version': 'latest',
      'additionalVersions': '9.0',
    }
  },
  'mounts': [
  {
    'type': 'volume',
    'source': 'x509stores',
    'target': '/home/vscode/.dotnet/corefx/cryptography/x509stores'
  },
  {
    'type': 'bind',
    'source': "${localEnv:HOME}${localEnv:USERPROFILE}/.azure",
    'target': '/home/vscode/.azure'
  }
  ],
  'containerEnv': {
    'AZURE_CLIENT_ID': "${{ secrets.AZURE_CLIENT_ID }}",
    'AZURE_TENANT_ID': "${{ secrets.AZURE_TENANT_ID }}",
    'AZURE_SUBSCRIPTION_ID': "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
  },
  'customizations': {
    'codespaces': {
      'openFiles': ["DEVELOPER.md"]
    },
    'vscode': {
      'settings': {
        '[terraform]': {
          'editor.defaultFormatter': 'hashicorp.terraform',
          'editor.formatOnSave': true
        },
        '[tfvars]': {
          'editor.defaultFormatter': 'hashicorp.terraform'
        },
        'editor.bracketPairColorization.enabled': true,
        'editor.codeActionsOnSave': {
          'source.fixAll': 'explicit'
        },
        'editor.formatOnPaste': true,
        'editor.formatOnSave': true,
        'editor.formatOnType': true,
        'editor.guides.bracketPairs': 'active',
        'editor.inlineSuggest.enabled': true,
        'editor.linkedEditing': true,
        'editor.multiCursorModifier': 'alt',
        'editor.renderControlCharacters': true,
        'editor.renderWhitespace': 'all',
        'editor.rulers': [
        {
          'color': '#A5FF90',
          'column': 80
        },
        {
          'color': '#FF628C',
          'column': 100
        }
        ],
        'editor.stickyScroll.enabled': true,
        'editor.suggestSelection': 'first',
        'editor.tabCompletion': 'on',
        'editor.tabSize': 2,
        'extensions.ignoreRecommendations': true,
        'files.associations': {
          '*.sh.tmpl': 'shellscript'
        },
        'files.eol': '\n',
        'files.autoGuessEncoding': false,
        'files.trimTrailingWhitespace': true,
        'terraform.languageServer': {
          'enabled': true
        },
        'json.validate.enable': true,
        'markdown.updateLinksOnFileMove.enabled': 'always'
      },
      'extensions': [
      'GitHub.copilot',
      'GitHub.copilot-chat',
      'HashiCorp.terraform',
      'ms-azuretools.vscode-azureappservice',
      'ms-azuretools.vscode-azurefunctions',
      'ms-azuretools.vscode-azureresourcegroups',
      'ms-azuretools.vscode-azureterraform',
      'ms-dotnettools.csharp',
      'ms-dotnettools.vscode-dotnet-runtime',
      'ms-vscode.powershell',
      'ms-vscode.azurecli',
      'redhat.vscode-yaml',
      'zarige.jsonlint'
      ],
      'unwantedRecommendations': ["eamodio.gitlens"],
      'welcome': {
        'title': '👋 Welcome to this Codespace!',
        'markdown': 'WELCOME.md'
      }
    }
  },
  'postCreateCommand': 'terraform --version && terraform-docs --version && tfsec --version && azd version',
  'postStartCommand': 'git fetch origin && git reset --hard origin/main'
}
'@
##   'onCreateCommand': 'bash .devcontainer/scripts/setup-dotnet-dev-cert.sh',

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

$script:TemplateReleaseWorkflow = @'
name: Module Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Release version (e.g. v1.2.3)"
        required: true
        type: string
      prerelease:
        description: "Mark as pre-release"
        required: false
        type: boolean
        default: false
      draft:
        description: "Create as draft"
        required: false
        type: boolean
        default: false

permissions:
  contents: write

jobs:
  release:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0 # full history for release notes generation

      - name: Validate version format
        run: |
          if [[ ! "${{ inputs.version }}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "ERROR: Version must be in format vX.Y.Z (e.g. v1.2.3)"
            exit 1
          fi

      - name: Check tag does not already exist
        run: |
          if git rev-parse "${{ inputs.version }}" &>/dev/null; then
            echo "ERROR: Tag ${{ inputs.version }} already exists"
            exit 1
          fi

      - name: Create Module Release
        run: |
          gh release create "${{ inputs.version }}" \
            --title "${{ inputs.version }}" \
            --generate-notes \
            --target "${{ github.ref_name }}" \
            ${{ inputs.prerelease && '--prerelease' || '--latest' }} \
            ${{ inputs.draft && '--draft' || '' }}
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
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

  Write-Host "Checking (with view)....'${Owner}/$repoName'"
  if (gh repo view ${Owner}/${repoName} 2>$null) {
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
      '.vscode',
      '.devcontainer',
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

    $script:TemplateWelcome | Set-Content 'WELCOME.md'
    $script:TemplateGitignore | Set-Content '.gitignore'
    $script:TemplateEditorConfig | Set-Content '.editorconfig'
    $script:TemplateGitAttributes | Set-Content '.gitattributes'
    $script:TemplateVsCodeSettings | Set-Content '.vscode/settings.json'
    $script:TemplateVsCodeExtensions | Set-Content '.vscode/extensions.json'
    $script:TemplateDevContainer | Set-Content '.devcontainer/devcontainer.json'
    $script:Dependabot | Set-Content '.github/dependabot.yml'

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
    $script:TemplateReleaseWorkflow | Set-Content '.github/workflows/release.yml'

    git init
    git add -A
    git commit -m 'initial commit'
    git branch -M main
    git remote add origin https://github.com/$Owner/${repoName}.git
    git push -u origin main

    git tag v0.1.0
    git push origin v0.1.0

    gh repo edit "$Owner/$repoName" --homepage "https://registry.terraform.io/modules/$Owner/$ModuleName/$Provider"

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
        Repo       = "https://github.com/$Owner/$repoName"
        RepoOwner  = $Owner
        RepoName   = $repoName
        ModuleName = $ModuleName
      })

  } finally {
    Pop-Location
  }
}

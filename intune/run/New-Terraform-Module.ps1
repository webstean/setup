function New-TerraformModuleRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,         # e.g. 'container-app

        [string]$Provider = 'azurerm',

        [string]$Description
    )

    # Terraform Registry naming convention: terraform-<provider>-<module>
    $repoName = "terraform-$Provider-$ModuleName"

    # Check gh cli
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Install via: winget install GitHub.cli"
    }

    if (-not (gh auth status 2>&1 | Select-String 'Logged in')) {
        throw "Not authenticated. Run: gh auth login"
    }

    $desc = if ($Description) { $Description } else { "Terraform module for $ModuleName on $Provider" }

    Write-Host "Creating repository: $repoName"
    gh repo create $repoName --public --description $desc --clone

    $repoPath = Join-Path (Get-Location) $repoName

    # Get GitHub org/user for OIDC subject
    $ghUser = (gh api user | ConvertFrom-Json).login

    Push-Location $repoPath

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

        @'
terraform {
  required_version = ">= 1.3.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0.0, < 5.0.0"
    }
  }
}
'@ | Set-Content 'versions.tf'

        @'
# Input variables
'@ | Set-Content 'variables.tf'

        @'
# Resources
'@ | Set-Content 'main.tf'

        @'
# Outputs
'@ | Set-Content 'outputs.tf'

        @'
module "example" {
  source = "../../"
}
'@ | Set-Content 'examples/basic/main.tf'

        @'
terraform {
  required_version = ">= 1.3.0"
}
'@ | Set-Content 'examples/basic/versions.tf'

        '' | Set-Content 'examples/basic/variables.tf'
        '' | Set-Content 'examples/basic/outputs.tf'

        Copy-Item 'examples/basic/main.tf'      'examples/complete/main.tf'
        Copy-Item 'examples/basic/versions.tf'  'examples/complete/versions.tf'
        Copy-Item 'examples/basic/variables.tf' 'examples/complete/variables.tf'
        Copy-Item 'examples/basic/outputs.tf'   'examples/complete/outputs.tf'

        @'
# go test -v -timeout 30m
'@ | Set-Content 'tests/main_test.go'

        @'
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
'@ | Set-Content '.terraform-docs.yml'

        @'
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
'@ | Set-Content '.gitignore'

        @"
# terraform-$Provider-$ModuleName

$desc

## Usage

``````hcl
module "$ModuleName" {
  source  = "<namespace>/$ModuleName/$Provider"
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

        New-Item -ItemType Directory -Path '.github/workflows' -Force | Out-Null
        @'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write   # required for OIDC token
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~> 1.9"

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
'@ | Set-Content '.github/workflows/ci.yml'

        git add -A
        git commit -m "chore: initial module scaffold"
        git push origin main

        git tag v0.1.0
        git push origin v0.1.0

        # OIDC federation credential subjects for this repo
        $oidc = [PSCustomObject]@{
            Issuer      = 'https://token.actions.githubusercontent.com'
            # Subjects cover push to main and any PR
            Subjects    = @(
                "repo:$ghUser/${repoName}:ref:refs/heads/main"
                "repo:$ghUser/${repoName}:pull_request"
            )
        }

        Write-Host ""
        Write-Host "Repository : $repoName"
        Write-Host "Path       : $repoPath"
        Write-Host ""
        Write-Host "--- OIDC Federated Credential ---"
        Write-Host "Issuer  : $($oidc.Issuer)"
        Write-Host "Subjects:"
        $oidc.Subjects | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        Write-Host "Terraform (azurerm_federated_identity_credential):"
        $oidc.Subjects | ForEach-Object {
            $label = if ($_ -match 'pull_request') { 'pr' } else { 'main' }
@"

resource "azurerm_federated_identity_credential" "${ModuleName}_${label}" {
  name                = "$repoName-$label"
  resource_group_name = azurerm_user_assigned_identity.this.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "$($oidc.Issuer)"
  subject             = "$_"
}
"@
        }
        Write-Host ""
        Write-Host "GitHub Secrets required:"
        Write-Host "  AZURE_CLIENT_ID       = <app registration or managed identity client id>"
        Write-Host "  AZURE_TENANT_ID       = <tenant id>"
        Write-Host "  AZURE_SUBSCRIPTION_ID = <subscription id>"

    } finally {
        Pop-Location
    }
}

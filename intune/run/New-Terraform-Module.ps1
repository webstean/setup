function New-TerraformModuleRepo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModuleName,

        [string]$Provider = 'azurerm',

        [string]$Description,

        [string]$Owner = 'webstean'
    )

    $repoName = "terraform-$Provider-$ModuleName"

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) not found. Install via: winget install GitHub.cli"
    }

    if (-not (gh auth status 2>&1 | Select-String 'Logged in')) {
        throw "Not authenticated. Run: gh auth login"
    }

    if (-not $Owner) {
        $Owner = (gh api user | ConvertFrom-Json).login
    }

    $desc = if ($Description) { $Description } else { "Terraform module for $ModuleName on $Provider" }

    Write-Host "Creating repository: $Owner/$repoName"
    gh repo create "$Owner/$repoName" --public --description $desc --clone

    $repoPath = Join-Path (Get-Location) $repoName

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

        '# Input variables'  | Set-Content 'variables.tf'
        '# Resources'        | Set-Content 'main.tf'
        '# Outputs'          | Set-Content 'outputs.tf'

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

        '# go test -v -timeout 30m' | Set-Content 'tests/main_test.go'

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

        New-Item -ItemType Directory -Path '.github/workflows' -Force | Out-Null
        @'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  id-token: write
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

        Write-Host "Creating placeholder secrets..."
        @{
            AZURE_CLIENT_ID       = 'REPLACE_ME'
            AZURE_TENANT_ID       = 'REPLACE_ME'
            AZURE_SUBSCRIPTION_ID = 'REPLACE_ME'
        }.GetEnumerator() | ForEach-Object {
            gh secret set $_.Key --body $_.Value --repo "$Owner/$repoName"
        }

        Write-Host ""
        Write-Host "Repository : $Owner/$repoName"
        Write-Host "Path       : $repoPath"
        Write-Host ""
        Write-Host "GitHub Secrets created (update with real values):"
        Write-Host "  AZURE_CLIENT_ID"
        Write-Host "  AZURE_TENANT_ID"
        Write-Host "  AZURE_SUBSCRIPTION_ID"
        Write-Host ""
        Write-Host "Terraform Registry Publishing:"
        Write-Host "  1. Sign in at https://registry.terraform.io with your GitHub account"
        Write-Host "  2. Click 'Publish' > 'Module'"
        Write-Host "  3. Select the '$repoName' repository"
        Write-Host "  4. Confirm — registry will detect versions from git tags (v0.1.0 already pushed)"
        Write-Host ""
        Write-Host "  Requirements checklist:"
        Write-Host "    [x] Repo named terraform-<provider>-<module>"
        Write-Host "    [x] Public repository"
        Write-Host "    [x] main.tf / variables.tf / outputs.tf present"
        Write-Host "    [x] v0.1.0 tag pushed"
        Write-Host "    [ ] GitHub OAuth app must be authorized for '$Owner' org/account"
        Write-Host "        https://github.com/settings/connections/applications/b0e1b0f5f7ca9fb13c7d"
        Write-Host ""
        Write-Host "  Once published, module source will be:"
        Write-Host "    $Owner/$ModuleName/$Provider"

    } finally {
        Pop-Location
    }
}


### https://github.com/cmb211087/azure-diagrams-skill

## Goal: Install a local MCP Gateway in Podman exposing:
## Filesystem
## Git
## GitHub
## Azure CLI
## Terraform
## Docker/Podman
## Documentation
## Microsoft Learn
## Microsoft Release Communications
## Local Markdown files

[CmdletBinding()]
param(
  [string]$Root = "$HOME\podman-mcp-gateway",
  [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$ContainerRuntime = $(if ($env:ASPIRE_CONTAINER_RUNTIME) { $env:ASPIRE_CONTAINER_RUNTIME } else { 'podman' }),
  [int]$Port = 4444,
  [string]$AdminEmail = $env:UPN ? $env:UPN : 'admin@example.com',
  [securestring]$AdminPassword = $env:STRONGPASSWORD ? (ConvertTo-SecureString $env:STRONGPASSWORD -AsPlainText -Force) : (ConvertTo-SecureString 'changeme' -AsPlainText -Force),
  [string]$JwtSecret = $env:STRONGPASSWORD ? $env:STRONGPASSWORD : 'changeme',
  [switch]$ConfigureVsCode,
  [string]$VsCodeMcpConfigPath = (Join-Path $env:APPDATA 'Code\User\mcp.json'),
  [int]$VsCodeTokenExpiryMinutes = 10080
)

function New-McpGateway {
  [CmdletBinding()]
  param(
    [string]$Root = "$HOME\podman-mcp-gateway",
    [string]$WorkspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$ContainerRuntime = $(if ($env:ASPIRE_CONTAINER_RUNTIME) { $env:ASPIRE_CONTAINER_RUNTIME } else { 'podman' }),
    [int]$Port = 4444,
    [string]$AdminEmail = $env:UPN ? $env:UPN : 'admin@example.com',
    [securestring]$AdminPassword = $env:STRONGPASSWORD ? (ConvertTo-SecureString $env:STRONGPASSWORD -AsPlainText -Force) : (ConvertTo-SecureString 'changeme' -AsPlainText -Force),
    [string]$JwtSecret = $env:STRONGPASSWORD ? $env:STRONGPASSWORD : 'changeme',
    [switch]$ConfigureVsCode,
    [string]$VsCodeMcpConfigPath = (Join-Path $env:APPDATA 'Code\User\mcp.json'),
    [int]$VsCodeTokenExpiryMinutes = 10080
  )

  $ErrorActionPreference = 'Stop'
  $ContainerRuntime = $ContainerRuntime.ToLowerInvariant()

  function ConvertTo-Base64Url {
    param(
      [Parameter(Mandatory)]
      [byte[]]$Bytes
    )

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  }

  function New-McpGatewayBearerToken {
    param(
      [Parameter(Mandatory)]
      [string]$Username,
      [Parameter(Mandatory)]
      [string]$Secret,
      [Parameter(Mandatory)]
      [int]$ExpiresInMinutes
    )

    $now = [DateTimeOffset]::UtcNow
    $header = [ordered]@{
      alg = 'HS256'
      typ = 'JWT'
    }
    $payload = [ordered]@{
      sub = $Username
      iat = $now.ToUnixTimeSeconds()
      iss = 'mcpgateway'
      aud = 'mcpgateway-api'
      jti = [guid]::NewGuid().ToString()
      exp = $now.AddMinutes($ExpiresInMinutes).ToUnixTimeSeconds()
    }

    $encoding = [System.Text.Encoding]::UTF8
    $headerPart = ConvertTo-Base64Url -Bytes $encoding.GetBytes(($header | ConvertTo-Json -Compress))
    $payloadPart = ConvertTo-Base64Url -Bytes $encoding.GetBytes(($payload | ConvertTo-Json -Compress))
    $unsignedToken = "$headerPart.$payloadPart"

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($encoding.GetBytes($Secret))
    try {
      $signature = ConvertTo-Base64Url -Bytes $hmac.ComputeHash($encoding.GetBytes($unsignedToken))
    } finally {
      $hmac.Dispose()
    }

    return "$unsignedToken.$signature"
  }

  function Set-VsCodeMcpGatewayConfig {
    param(
      [Parameter(Mandatory)]
      [string]$ConfigPath,
      [Parameter(Mandatory)]
      [string]$GatewayUrl,
      [Parameter(Mandatory)]
      [string]$BearerToken
    )

    $configDirectory = Split-Path -Parent $ConfigPath
    New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null

    if (Test-Path $ConfigPath) {
      $rawConfig = Get-Content -Raw -Path $ConfigPath
      $config = $rawConfig ? ($rawConfig | ConvertFrom-Json -AsHashtable) : [ordered]@{}
    } else {
      $config = [ordered]@{}
    }

    if (-not $config.ContainsKey('servers') -or $null -eq $config['servers']) {
      $config['servers'] = [ordered]@{}
    }

    $config['servers']['mcp-gateway'] = [ordered]@{
      type    = 'http'
      url     = "$GatewayUrl/mcp"
      headers = [ordered]@{
        Authorization = "Bearer $BearerToken"
      }
    }

    $config | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $ConfigPath
  }

  function Invoke-Compose {
    param(
      [Parameter(Mandatory)]
      [ValidateSet('pull', 'up', 'down')]
      [string]$Action,
      [Parameter(Mandatory)]
      [string]$ComposeFile,
      [switch]$Detached
    )

    $composeArgs = @('compose', '-f', $ComposeFile, $Action)
    if ($Detached -and $Action -eq 'up') {
      $composeArgs += '-d'
    }

    switch ($ContainerRuntime) {
      'docker' { & docker @composeArgs }
      'podman' { & podman @composeArgs }
      'wslc' { & wslc @composeArgs }
      default {
        throw "Unsupported container runtime '$ContainerRuntime'. Expected docker, podman, or wslc."
      }
    }
  }

  if ($ContainerRuntime -eq 'podman') {
    if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
      throw 'Podman is not installed or not in PATH.'
    }
  } elseif ($ContainerRuntime -eq 'docker') {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
      throw 'Docker is not installed or not in PATH.'
    }
  } elseif ($ContainerRuntime -eq 'wslc') {
    if (-not (Get-Command wslc -ErrorAction SilentlyContinue)) {
      throw 'WSLC is not installed or not in PATH.'
    }
  }

  $AdminPasswordPlain = [System.Net.NetworkCredential]::new('', $AdminPassword).Password
  $WorkspaceRootCompose = ($WorkspaceRoot -replace '\\', '/')

  New-Item -ItemType Directory -Force -Path $Root | Out-Null
  Push-Location
  try {
    Set-Location $Root

    @"
MCPGATEWAY_UI_ENABLED=true
MCPGATEWAY_ADMIN_API_ENABLED=true
MCPGATEWAY_LOG_LEVEL=INFO
MCPGATEWAY_CATALOG_ENABLED=true
MCPGATEWAY_CATALOG_FILE=mcp-catalog.yml
MCPGATEWAY_CATALOG_AUTO_HEALTH_CHECK=true

WORKSPACE_ROOT=$WorkspaceRoot

PLATFORM_ADMIN_EMAIL=$AdminEmail
PLATFORM_ADMIN_PASSWORD=$AdminPasswordPlain
PLATFORM_ADMIN_FULL_NAME=Platform Administrator

JWT_SECRET_KEY=$JwtSecret
BASIC_AUTH_USER=admin
BASIC_AUTH_PASSWORD=$AdminPasswordPlain

DATABASE_URL=postgresql://mcpgateway:mcpgateway@postgres:5432/mcpgateway
REDIS_URL=redis://redis:6379/0
"@ | Set-Content -Encoding UTF8 '.env'

    @'
catalog_servers:
  - id: workspace-filesystem
    name: Workspace Filesystem
    category: Utilities
    url: http://filesystem:9001/sse
    auth_type: Open
    provider: Local
    description: Workspace filesystem for local markdown files, repository docs, and file inspection.
    requires_api_key: false
    tags:
      - filesystem
      - markdown
      - docs
      - local-files

  - id: local-git
    name: Local Git
    category: Software Development
    url: http://git:9002/sse
    auth_type: Open
    provider: Local
    description: Git repository tools for the current workspace.
    requires_api_key: false
    tags:
      - git
      - version-control
      - repository

  - id: github
    name: GitHub
    category: Software Development
    url: http://github:9003/sse
    auth_type: OAuth2.1
    provider: GitHub
    description: GitHub API and repository automation tools.
    requires_api_key: false
    tags:
      - github
      - pull-requests
      - issues
      - automation

  - id: powershell
    name: PowerShell
    category: Utilities
    url: http://powershell:9004/sse
    auth_type: Open
    provider: Local
    description: PowerShell execution tools for local automation and system tasks.
    requires_api_key: false
    tags:
      - powershell
      - pwsh
      - automation
      - shell

  - id: microsoft-release-communications
    name: Microsoft Release Communications
    category: Documentation
    url: https://www.microsoft.com/releasecommunications/mcp
    auth_type: Open
    provider: Microsoft
    description: Public Microsoft release communications for Microsoft 365 roadmap and Azure Updates.
    requires_api_key: false
    tags:
      - microsoft
      - release-communications
      - microsoft-365-roadmap
      - azure-updates
'@ | Set-Content -Encoding UTF8 'mcp-catalog.yml'

    @'
from mcp.server.fastmcp import FastMCP

import shutil
import subprocess


mcp = FastMCP("powershell-integration")


@mcp.tool()
def run_powershell(code: str) -> str:
    """Runs PowerShell code and returns the output."""
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell:
        return "Error: PowerShell is not installed in this container."

    process = subprocess.Popen(
        [shell, "-NoLogo", "-NoProfile", "-Command", code],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    output, error = process.communicate()
    if process.returncode != 0:
        return f"Error: {error}"

    return output


if __name__ == "__main__":
    mcp.run()
'@ | Set-Content -Encoding UTF8 'powershell-mcp-server.py'

    @"
services:
  postgres:
    image: docker.io/library/postgres:16-alpine
    container_name: mcp-postgres
    environment:
      POSTGRES_USER: mcpgateway
      POSTGRES_PASSWORD: mcpgateway
      POSTGRES_DB: mcpgateway
    volumes:
      - mcp-postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

  redis:
    image: docker.io/library/redis:7-alpine
    container_name: mcp-redis
    restart: unless-stopped

  filesystem:
    image: ghcr.io/ibm/mcp-context-forge:latest
    container_name: mcp-filesystem
    working_dir: /workspace
    volumes:
      - ${WorkspaceRootCompose}:/workspace:ro
    command: ["python3", "-m", "mcpgateway.translate", "--stdio", "uvx mcp-server-filesystem --directory /workspace", "--expose-sse", "--port", "9001", "--host", "0.0.0.0"]
    ports:
      - "9001:9001"
    restart: unless-stopped

  git:
    image: ghcr.io/ibm/mcp-context-forge:latest
    container_name: mcp-git
    working_dir: /workspace
    volumes:
      - ${WorkspaceRootCompose}:/workspace:ro
    command: ["python3", "-m", "mcpgateway.translate", "--stdio", "uvx mcp-server-git", "--expose-sse", "--port", "9002", "--host", "0.0.0.0"]
    ports:
      - "9002:9002"
    restart: unless-stopped

  github:
    image: ghcr.io/ibm/mcp-context-forge:latest
    container_name: mcp-github
    working_dir: /workspace
    volumes:
      - ${WorkspaceRootCompose}:/workspace:ro
    environment:
      GITHUB_TOKEN: ${GITHUB_TOKEN}
    command: ["python3", "-m", "mcpgateway.translate", "--stdio", "uvx mcp-server-github", "--expose-sse", "--port", "9003", "--host", "0.0.0.0"]
    ports:
      - "9003:9003"
    restart: unless-stopped

  powershell:
    image: mcr.microsoft.com/powershell:7.4-ubuntu-22.04
    container_name: mcp-powershell
    working_dir: /config
    volumes:
      - ./powershell-mcp-server.py:/config/powershell-mcp-server.py:ro
    environment:
      DEBIAN_FRONTEND: noninteractive
    command:
      - pwsh
      - -NoLogo
      - -NoProfile
      - -Command
      - >-
        apt-get update &&
        apt-get install -y python3 python3-pip git &&
        python3 -m pip install --no-cache-dir mcp-contextforge-gateway &&
        python3 -m mcpgateway.translate --stdio "python3 /config/powershell-mcp-server.py" --expose-sse --port 9004 --host 0.0.0.0
    ports:
      - "9004:9004"
    restart: unless-stopped

  gateway:
    image: ghcr.io/ibm/mcp-context-forge:latest
    container_name: mcp-gateway
    env_file:
      - .env
    volumes:
      - ./:/config:ro
    ports:
      - "$Port`:4444"
    depends_on:
      - postgres
      - redis
      - filesystem
      - git
      - github
      - powershell
    restart: unless-stopped
    command: ["mcpgateway", "--host", "0.0.0.0", "--port", "4444"]

volumes:
  mcp-postgres-data:
"@ | Set-Content -Encoding UTF8 'compose.yml'

    Invoke-Compose -Action pull -ComposeFile 'compose.yml'
    Invoke-Compose -Action up -ComposeFile 'compose.yml' -Detached

    if ($ConfigureVsCode) {
      $gatewayUrl = "http://localhost:$Port"
      $bearerToken = New-McpGatewayBearerToken -Username $AdminEmail -Secret $JwtSecret -ExpiresInMinutes $VsCodeTokenExpiryMinutes
      Set-VsCodeMcpGatewayConfig -ConfigPath $VsCodeMcpConfigPath -GatewayUrl $gatewayUrl -BearerToken $bearerToken
    }

    Write-Host ''
    Write-Host 'MCP Gateway running:'
    Write-Host "  UI/API: http://localhost:$Port"
    Write-Host "  MCP:    http://localhost:$Port/mcp"
    Write-Host "  Admin:  $AdminEmail"
    Write-Host "  Pass:   $AdminPasswordPlain"
    if ($ConfigureVsCode) {
      Write-Host "  VS Code MCP config: $VsCodeMcpConfigPath"
    }
    Write-Host ''
    Write-Host 'Useful commands:'
    Write-Host "  $ContainerRuntime compose -f `"$Root\compose.yml`" logs -f gateway"
    Write-Host "  $ContainerRuntime compose -f `"$Root\compose.yml`" down"
  } finally {
    Pop-Location
  }
}
try {
  New-McpGateway @PSBoundParameters
} catch {
  Write-Error "Failed to set up MCP Gateway: $_"  
}

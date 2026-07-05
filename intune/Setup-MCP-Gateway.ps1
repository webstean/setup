### https://github.com/cmb211087/azure-diagrams-skill

MCP Gateway
Run a local MCP gateway in Podman exposing:
Filesystem
Git
GitHub
Azure CLI
Terraform
Docker/Podman
Documentation
Microsoft Learn
Local Markdown files


function New-PodmanMcpGateway {
    [CmdletBinding()]
    param(
        [string]$Root = "$HOME\podman-mcp-gateway",
        [int]$Port = 4444,
        [string]$AdminEmail = "admin@example.com",
        [string]$AdminPassword = "changeme",
        [string]$JwtSecret = "change-this-to-a-long-random-secret-more-than-32-bytes"
    )

    $ErrorActionPreference = "Stop"

    if (-not (Get-Command podman -ErrorAction SilentlyContinue)) {
        throw "Podman is not installed or not in PATH."
    }

    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    Set-Location $Root

    @"
MCPGATEWAY_UI_ENABLED=true
MCPGATEWAY_ADMIN_API_ENABLED=true
MCPGATEWAY_LOG_LEVEL=INFO

PLATFORM_ADMIN_EMAIL=$AdminEmail
PLATFORM_ADMIN_PASSWORD=$AdminPassword
PLATFORM_ADMIN_FULL_NAME=Platform Administrator

JWT_SECRET_KEY=$JwtSecret
BASIC_AUTH_USER=admin
BASIC_AUTH_PASSWORD=$AdminPassword

DATABASE_URL=postgresql://mcpgateway:mcpgateway@postgres:5432/mcpgateway
REDIS_URL=redis://redis:6379/0
"@ | Set-Content -Encoding UTF8 ".env"

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

  gateway:
    image: ghcr.io/ibm/mcp-context-forge:latest
    container_name: mcp-gateway
    env_file:
      - .env
    ports:
      - "$Port`:4444"
    depends_on:
      - postgres
      - redis
    restart: unless-stopped
    command: ["mcpgateway", "--host", "0.0.0.0", "--port", "4444"]

volumes:
  mcp-postgres-data:
"@ | Set-Content -Encoding UTF8 "compose.yml"

    podman compose -f compose.yml pull
    podman compose -f compose.yml up -d

    Write-Host ""
    Write-Host "MCP Gateway running:"
    Write-Host "  UI/API: http://localhost:$Port"
    Write-Host "  Admin:  $AdminEmail"
    Write-Host "  Pass:   $AdminPassword"
    Write-Host ""
    Write-Host "Useful commands:"
    Write-Host "  podman compose -f `"$Root\compose.yml`" logs -f gateway"
    Write-Host "  podman compose -f `"$Root\compose.yml`" down"
}

New-PodmanMcpGateway

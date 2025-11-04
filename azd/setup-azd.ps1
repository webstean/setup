hooks:
  preprovision:
    shell: pwsh
    run: |
      $url     = "https://raw.githubusercontent.com/<org-or-user>/<repo>/<ref>/scripts/sync-azd-config-to-tfvars.ps1"
      $tmpDir  = [System.IO.Path]::GetTempPath()
      $script  = Join-Path $tmpDir "sync-azd-config-to-tfvars.ps1"

      Write-Host "Downloading sync script from $url to $script..."
      Invoke-WebRequest -Uri $url -OutFile $script -UseBasicParsing

      Write-Host "Running sync script for environment $Env:AZD_ENV_NAME..."
      & pwsh $script -EnvironmentName $Env:AZD_ENV_NAME

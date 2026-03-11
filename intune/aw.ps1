function Install-OrUpdate-DotNetTools {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Tools,

        # Use Global by default (installs to $HOME\.dotnet\tools)
        [switch]$Global = $true,

        # If set, installs to this folder instead of global. Mutually exclusive with -Global.
        [string]$ToolPath = "C:\Program Files\DotNet Tools",

        # Include prerelease versions
        [switch]$Prerelease = $true
    )

    if ($PSBoundParameters.ContainsKey('ToolPath') -and $Global) {
        # If caller explicitly set ToolPath, force non-global to avoid invalid combination.
        $Global = $false
    }

    if (-not $Global) {
        if ([string]::IsNullOrWhiteSpace($ToolPath)) {
            throw "ToolPath is empty."
        }
        if (-not (Test-Path -Path $ToolPath -PathType Container)) {
            New-Item -Path $ToolPath -ItemType Directory -Force | Out-Null
        }
    }

    function Invoke-DotNet {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [string[]]$Args
        )

        $p = Start-Process -FilePath "dotnet.exe" -ArgumentList $Args -NoNewWindow -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw "dotnet $($Args -join ' ') failed with exit code $($p.ExitCode)"
        }
    }

    Write-Output "Installing/Updating .NET tools..."

    # List installed tools in the correct scope
    $listArgs = @("tool","list")
    if ($Global) {
        $listArgs += "--global"
    }
    else {
        $listArgs += @("--tool-path", $ToolPath)
    }

    $installed = & dotnet @listArgs 2>$null
    # Normalize to tool package ids found in output table
    $installedIds = @()
    if ($installed) {
        $installedIds = $installed |
            Select-Object -Skip 2 |
            ForEach-Object { ($_ -split '\s+')[0] } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    foreach ($tool in $Tools) {
        $isInstalled = $installedIds -contains $tool

        if (-not $isInstalled) {
            Write-Output "Installing $tool..."
            $args = @("tool","install","--ignore-failed-sources", $tool)
            if ($Prerelease) { $args += "--prerelease" }

            if ($Global) {
                $args += "--global"
            }
            else {
                $args += @("--tool-path", $ToolPath)
            }

            Invoke-DotNet -Args $args
        }
        else {
            Write-Output "Updating $tool..."
            $args = @("tool","update", $tool)
            if ($Prerelease) { $args += "--prerelease" }

            if ($Global) {
                $args += "--global"
            }
            else {
                $args += @("--tool-path", $ToolPath)
            }

            Invoke-DotNet -Args $args
        }
    }

    # Show final state
    Invoke-DotNet -Args $listArgs

    # Add NuGet source if missing (best-effort)
    try {
        $sources = & dotnet nuget list source 2>$null
        if (-not ($sources -match 'searchnuget\.org')) {
            Invoke-DotNet -Args @("nuget","add","source","https://api.nuget.org/v3/index.json","-n","searchnuget.org")
        }
    } catch {
        # Do not fail the whole function for a source add problem
        Write-Warning "Could not add/list NuGet source 'searchnuget.org': $($_.Exception.Message)"
    }
}


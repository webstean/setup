function Set-StarshipAdminIndicator {
    <#
    .SYNOPSIS
        Adds Starship custom modules that change colour based on elevation (Admin vs User).

    .DESCRIPTION
        - Creates/updates ~/.config/starship.toml with two custom modules:
            [custom.admin] -> red icon when elevated
            [custom.user]  -> green icon when not elevated
        - Ensures the modules appear in the prompt format.
        - Optionally appends 'Invoke-Expression (&starship init powershell)' to $PROFILE.
        - Idempotent: re-running updates sections without duplicating them.

    .PARAMETER AddInitToProfile
        When set, ensures Starship init is present in the current user PowerShell profile.

    .PARAMETER AdminStyle
        Starship style for the admin indicator (default: 'bold red').

    .PARAMETER UserStyle
        Starship style for the user indicator (default: 'bold green').

    .PARAMETER AdminIcon
        Icon/text shown when elevated (default: '󰷛').

    .PARAMETER UserIcon
        Icon/text shown when non-elevated (default: '󰈸').

    .OUTPUTS
        PSCustomObject summary of what was changed.

    .EXAMPLE
        Set-StarshipAdminIndicator -AddInitToProfile

    .EXAMPLE
        Set-StarshipAdminIndicator -AdminStyle 'bold yellow' -UserStyle 'bold cyan' -AdminIcon '#' -UserIcon '$'
    #>
    [CmdletBinding()]
    param(
        [switch]$AddInitToProfile,
        [string]$AdminStyle = 'bold red',
        [string]$UserStyle  = 'bold green',
        [string]$AdminIcon  = '󰷛',
        [string]$UserIcon   = '󰈸'
    )

    $result = [pscustomobject]@{
        ConfigPath        = $null
        ProfileUpdated    = $false
        AdminModuleUpsert = $false
        UserModuleUpsert  = $false
        FormatUpdated     = $false
        Notes             = @()
    }

    # Paths
    $configDir    = Join-Path $env:USERPROFILE '.config'
    $starshipToml = Join-Path $configDir 'starship.toml'
    $result.ConfigPath = $starshipToml

    # Ensure dirs/files
    if (-not (Test-Path $configDir)) { New-Item -ItemType Directory -Path $configDir -Force | Out-Null }
    if (-not (Test-Path $starshipToml)) { New-Item -ItemType File -Path $starshipToml -Force | Out-Null }

    # TOML blocks (interpolate styles/icons)
    $adminBlock = @"
[custom.admin]
command = 'powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Output \"$AdminIcon\" }"'
when = 'powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"'
shell = ["powershell"]
format = "[$`output]($`style) "
style = "$AdminStyle"
"@

    $userBlock = @"
[custom.user]
command = 'powershell -NoProfile -Command "if (-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) { Write-Output \"$UserIcon\" }"'
when = 'powershell -NoProfile -Command "-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"'
shell = ["powershell"]
format = "[$`output]($`style) "
style = "$UserStyle"
"@

    $defaultFormat = @"
format = """
$custom.admin\
$custom.user\
$directory\
$git_branch\
$git_status\
$character
"""
"@

    # Helper: upsert a TOML section (replace existing section content or append)
    function _Set-TomlSection {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$SectionHeaderRegex,
            [Parameter(Mandatory)][string]$BlockText
        )
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ($content -match $SectionHeaderRegex) {
            $pattern = "(?ms)$SectionHeaderRegex.*?(?=^\[|\Z)"
            $new = [regex]::Replace($content, $pattern, $BlockText + "`r`n")
            if ($new -ne $content) {
                Set-Content -Path $Path -Value $new -Encoding UTF8
                return $true
            }
            return $false
        } else {
            Add-Content -Path $Path -Value ("`r`n" + $BlockText + "`r`n")
            return $true
        }
    }

    # Upsert modules
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.admin\]\s*$' -BlockText $adminBlock) {
        $result.AdminModuleUpsert = $true
    }
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.user\]\s*$' -BlockText $userBlock) {
        $result.UserModuleUpsert = $true
    }

    # Ensure our modules appear in the format
    $content = Get-Content -Path $starshipToml -Raw
    if ($content -notmatch '^\s*format\s*=' ) {
        Add-Content -Path $starshipToml -Value ("`r`n" + $defaultFormat + "`r`n")
        $result.FormatUpdated = $true
    } else {
        $pattern = '(?ms)^\s*format\s*=\s*"""(.*?)"""'
        if ($content -match $pattern) {
            $inner = $Matches[1]
            if ($inner -notmatch '\$custom\.admin' -or $inner -notmatch '\$custom\.user') {
                $newInner = "$custom.admin`" + [Environment]::NewLine + "$custom.user`" + [Environment]::NewLine + $inner
                $newContent = [regex]::Replace($content, $pattern, 'format = """' + $newInner + '"""')
                if ($newContent -ne $content) {
                    Set-Content -Path $starshipToml -Value $newContent -Encoding UTF8
                    $result.FormatUpdated = $true
                }
            }
        }
    }

    # Optionally add Starship init to profile
    if ($AddInitToProfile) {
        $profilePath = $PROFILE
        if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }
        $profileContent = Get-Content -Path $profilePath -Raw
        $initLine = 'Invoke-Expression (&starship init powershell)'
        if ($profileContent -notmatch [regex]::Escape($initLine)) {
            Add-Content -Path $profilePath -Value "`r`n$initLine`r`n"
            $result.ProfileUpdated = $true
        } else {
            $result.Notes += 'Starship init already present in $PROFILE.'
        }
    }

    $result
}
Set-StarshipAdminIndicator

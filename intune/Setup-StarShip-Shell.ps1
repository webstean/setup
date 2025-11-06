function Set-StarshipAdminIndicator {
    <#
    .SYNOPSIS
        Adds Starship custom modules that change colour based on elevation (Admin vs User).
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
    if (-not (Test-Path $configDir))   { New-Item -ItemType Directory -Path $configDir   -Force | Out-Null }
    if (-not (Test-Path $starshipToml)){ New-Item -ItemType File      -Path $starshipToml -Force | Out-Null }

    # Use single-quoted here-strings so $ stays literal inside TOML
    $adminBlock = @'
[custom.admin]
command = 'powershell -NoProfile -Command "if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Write-Output \"__ADMIN_ICON__\" }"'
when = 'powershell -NoProfile -Command "([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)"'
shell = ["powershell"]
format = "[$output]($style) "
style = "__ADMIN_STYLE__"
'@

    $userBlock = @'
[custom.user]
command = 'powershell -NoProfile -Command "if (-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))) { Write-Output \"__USER_ICON__\" }"'
when = 'powershell -NoProfile -Command "-not (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"'
shell = ["powershell"]
format = "[$output]($style) "
style = "__USER_STYLE__"
'@

    # Inject chosen styles/icons (NO space before .Replace)
    $adminBlock = $adminBlock.Replace('__ADMIN_STYLE__', $AdminStyle).Replace('__ADMIN_ICON__', $AdminIcon)
    $userBlock  = $userBlock.Replace('__USER_STYLE__',  $UserStyle).Replace('__USER_ICON__',  $UserIcon)

    # Default format (single-quoted so $custom.* is literal)
    $defaultFormat = @'
format = """
$custom.admin\
$custom.user\
$directory\
$git_branch\
$git_status\
$character
"""
'@

    # Helper: upsert a TOML section
    function _Set-TomlSection {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$SectionHeaderRegex,
            [Parameter(Mandatory)][string]$BlockText
        )
        $content = Get-Content -Path $Path -Raw -ErrorAction Stop
        if ($content -match $SectionHeaderRegex) {
            $pattern = "(?ms)$SectionHeaderRegex.*?(?=^\[|\Z)"
            $new     = [regex]::Replace($content, $pattern, $BlockText + "`r`n")
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
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.admin\]\s*$' -BlockText $adminBlock) { $result.AdminModuleUpsert = $true }
    if (_Set-TomlSection -Path $starshipToml -SectionHeaderRegex '^\[custom\.user\]\s*$'  -BlockText $userBlock)  { $result.UserModuleUpsert  = $true }

    # Ensure our modules appear in the format
    $content = Get-Content -Path $starshipToml -Raw
    if ($content -notmatch '^\s*format\s*=' ) {
        Add-Content -Path $starshipToml -Value ("`r`n" + $defaultFormat + "`r`n")
        $result.FormatUpdated = $true
    } else {
        # Prepend our two module lines if missing (escape $ so TOML keeps it)
        $pattern = '(?ms)^\s*format\s*=\s*"""(.*?)"""'
        if ($content -match $pattern) {
            $inner      = $Matches[1]
            $needsAdmin = ($inner -notmatch '\$custom\.admin')
            $needsUser  = ($inner -notmatch '\$custom\.user')
            if ($needsAdmin -or $needsUser) {
                $prepend = @()
                if ($needsAdmin) { $prepend += '`$custom.admin\' }
                if ($needsUser)  { $prepend += '`$custom.user\' }
                $newInner   = ($prepend -join [Environment]::NewLine) + [Environment]::NewLine + $inner
                $newContent = [regex]::Replace($content, $pattern, 'format = """' + $newInner + '"""')
                if ($newContent -ne $content) {
                    Set-Content -Path $starshipToml -Value $newContent -Encoding UTF8
                    $result.FormatUpdated = $true
                }
            }
        }
    }

    $result
}
Set-StarshipAdminIndicator

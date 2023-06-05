
## https://github.com/devblackops/Terminal-Icons
Install-Module -Name Terminal-Icons -Repository PSGallery -Force

$backgroundimage = "ms-appdata:///Roaming/terminal_cat.jpg"
$font = "MesloLGM NF"
$font = "Fira Code"

function Update-MSTerminal {

    ## Read in JSON file into variable
    $settings = Get-Content -Raw -Path $settingsfile -ErrorAction silentlycontinue | ConvertFrom-Json -Depth 32
    ## $settings.GetType().name
    ## PSCustomObject
    if ($settings) {

        Write-Host ("Adjust config file [$settingsfile]")
        ## Global Defaults
        $settings[0] | Add-Member -Name copyonSelect -Value $true -MemberType NoteProperty -Force
        $settings[0] | Add-Member -Name startOnUserLogin -Value $false -MemberType NoteProperty -Force
        $settings[0] | Add-Member -Name theme -Value "dark" -MemberType NoteProperty -Force
        $settings[0] | Add-Member -Name largePasteWarning -Value $false -MemberType NoteProperty -Force
        $settings[0] | Add-Member -Name multiLinePasteWarning -Value $false -MemberType NoteProperty -Force
        $settings[0] | Add-Member -Name useAcryplic -Value 0 -MemberType NoteProperty -Force
                
        ## Defaults
        $settings.profiles.defaults | Add-Member -Name cursorShape -Value "vintage" -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name bellStyle -Value "window" -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name experimental.autoMarkPrompts -Value $true -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name snapOnInput -Value $true -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name useAtlasEngine -Value $true -MemberType NoteProperty -Force
        
        ## Disable Tabs
        #$settings.list[0].guid | Add-Member -Name hidden -Value $true -MemberType NoteProperty -Force
        #foreach ($profiles in $settings.list) {
        #    $name = $fontFile.Name
        #    Write-Output ("Installing ${name}")
        #    $fonts.CopyHere($fontFile.FullName)
        #}
        
        ## Defaults - Fonts (future)
        #$settings.profiles.defaults | Add-Member -Name font -Value font  -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font | Add-Member -Name face -Value $font -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font | Add-Member -Name size -Value 10.0 -MemberType NoteProperty -Force
        ## "normal", "thin", "extra-light", "light", "semi-light", "medium", "semi-bold", "bold", "extra-bold", "black", "extra-black"
        #$settings.profiles.defaults.font | Add-Member -Name weight -Value "extra-bold" -MemberType NoteProperty -Force
        
        ## font features and ligatures
        #$settings.profiles.defaults.font | Add-Member -Name features -Value features -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv02 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv14 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv25 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv26 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv28 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name cv32 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name ss02 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name ss03 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name ss05 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name ss07 -Value 1 -MemberType NoteProperty -Force
        #$settings.profiles.defaults.font.features | Add-Member -Name ss09 -Value 1 -MemberType NoteProperty -Force
 
        ## Defaults - Fonts (legacy)
        $settings.profiles.defaults | Add-Member -Name fontFace -Value $font -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name fontSize -Value 10 -MemberType NoteProperty -Force
        ## "normal", "thin", "extra-light", "light", "semi-light", "medium", "semi-bold", "bold", "extra-bold", "black", "extra-black"
        $settings.profiles.defaults | Add-Member -Name fontWeight -Value "extra-bold" -MemberType NoteProperty -Force

        ## Defaults - Colour Scheme
        #$settings.profiles.defaults | Add-Member -Name colorScheme -Value colorSchema -MemberType NoteProperty -Force
        #$settings.profiles.defaults.colorScheme | Add-Member -Name light -Value "One Half Light" -MemberType NoteProperty -Force
        #$settings.profiles.defaults.colorScheme | Add-Member -Name dark  -Value "One Half Dark"  -MemberType NoteProperty -Force
        
        ## Default - Background
        $settings.profiles.defaults | Add-Member -Name backgroundImageOpacity -Value 0.1 -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name backgroundImageAlignment -Value "center" -MemberType NoteProperty -Force
        $settings.profiles.defaults | Add-Member -Name opacity -Value 90 -MemberType NoteProperty -Force
        ## "none", "fill", "uniform", "uniformToFill"
        $settings.profiles.defaults | Add-Member -Name backgroundImageStretchMode -Value "uniformToFill" -MemberType NoteProperty -Force
        if ((Test-Path -Path $backgroundimage -PathType Any)) {
                $settings.profiles.defaults | Add-Member -Name backgroundImage -Value "$backgroundimage" -MemberType NoteProperty -Force
            } else {
                $settings.profiles.defaults | Add-Member -Name backgroundImage -Value "desktopWallpaper" -MemberType NoteProperty -Force
        }  
        ## Output variable to JSON file
        Write-Output ("Writing changes to the [$settingsfile]...")
        $settings | ConvertTo-Json -Depth 32 | Out-File $settingsfile -Encoding utf8 -Force
    } else {
        Write-Error ("Settings file [$settingsPath] not found!")
    }
}

function Reset-MsTerminal {
    ## 
    if (Test-Path -Path $settingsfile -PathType Any) {
        Remove-Item -Path $settingsfile
    }
    if (Test-Path -Path $statefile -PathType Any) {
        Remove-Item -Path $statefile
    }
}

## Terminal (unpackaged: Scoop, Chocolately, etc): %LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json
$statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Microsoft\Windows Terminal\settings.json"
if (Test-Path -Path $settingsfile -PathType Any) {
    Update-MsTerminal
}

## Terminal (preview release): %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json
$statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Any) {
    Update-MsTerminal
}

## Terminal (stable / general release): %LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
$statefile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\state.json"
$settingsfile = [Environment]::GetFolderPath("localapplicationdata") + "\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path -Path $settingsfile -PathType Any) {
    Update-MsTerminal
}

## $Host.UI.RawUI.WindowTitle = "New Title"



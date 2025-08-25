#Requires -RunAsAdministrator

function Install-Fonts {
    [CmdletBinding()]
    param (
        [string]$FontName,
        [string]$Owner,
        [string]$Repo,
        [string]$zipfilespec
    )

    #Requires -RunAsAdministrator

    ## GitHub API URL for the latest release
    $url = "https://api.github.com/repos/$Owner/$Repo/releases/latest"

    ## Send a GET request to the GitHub API
    $response = Invoke-RestMethod -Uri $url -Method Get

    ## Extract the download URL for the latest release asset
    $latestRelease = $response.assets | Where-Object { $_.name -like "*$FontName*.zip" } | Select-Object -First 1
    $fontUrl = $latestRelease.browser_download_url
    Write-Output ("Installing Font:$FontName from https://github.com/$Owner/$Repo...") 
    Write-Output ("Downloard URL  :$fontUrl") 

    ## Define the extraction paths
    $fontZipPath = "$env:TEMP\$FontName.zip"
    $fontExtractPath = "$env:TEMP\$FontName"

    ## Download the font
    Write-Output ("Font Zip       :$fontZipPath") 
    Invoke-WebRequest -Uri $fontUrl -OutFile $fontZipPath

    ## Extract the zip file
    Write-Output ("Font Extract   :$fontExtractPath") 
    Expand-Archive -Path $fontZipPath -DestinationPath $fontExtractPath -Force

    ## Install the fonts (for all users, copy to the Fonts directory and update registry)
    $fontFiles = Get-ChildItem "$fontExtractPath\$zipfilespec"
    $totalfonts = 0
    foreach ($fontFile in $fontFiles) {
        $totalfonts++
    }
    Write-Output "Total number of fonts to install: $totalfonts" 
    foreach ($fontFile in $fontFiles) {
        ## User
        #$fontDestinationUser = "$env:USERPROFILE\Documents\Fonts\$($fontFile.Name)"
        ## System
        $fontDestinationSystem = "$env:SystemRoot\Fonts\$($fontFile.Name)"
        ## Copy-Item $fontFile.FullName -Destination $fontDestinationUser
        Copy-Item $fontFile.FullName -Destination $fontDestinationSystem

        # Add font to the registry to ensure it is recognized
        $fontRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        New-ItemProperty -Path $fontRegistryPath -Name "$($fontFile.BaseName) (TrueType)" -Value $fontFile.Name -PropertyType String -Force

        Write-Output ("Installed font: $($fontFile.Name)") 
    }

    ## Clean up temporary font files
    Remove-Item $fontZipPath -Force
    Remove-Item $fontExtractPath -Recurse -Force
}
## Font installs
Install-Fonts -FontName "CascadiaCode" -Owner "microsoft" -Repo "cascadia-code" -zipfilespec "ttf\*.ttf"
Install-Fonts -FontName "FiraCode" -Owner "ryanoasis" -Repo "nerd-fonts" -zipfilespec "*.ttf"
Write-Host ("Setting PowerShell to UTF-8 output encoding...")
[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding


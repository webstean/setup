
function local:Font-Install {
    $FontDirectory = $PSScriptRoot
    if ($FontDirectory -eq $PSHOME.TrimEnd('\')) {
        $FontDirectory = $PSScriptRoot + "\fonts\"
        $FontDirectory
    }

    ## Display count for all the Font Families
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    $fontfamily = (New-Object System.Drawing.Text.InstalledFontCollection).Families
    $fontfamily.Count

    ## Installing all the fonts
    Write-Output "Installing all fonts found in this directory [$FontDirectory]"

    ## Create object and fill it will file name of valid font files
    $fontFiles = New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    Get-ChildItem $FontDirectory -Filter "*.ttf" -Recurse | Foreach-Object {$fontFiles.Add($_)}
    Get-ChildItem $FontDirectory -Filter "*.otf" -Recurse | Foreach-Object {$fontFiles.Add($_)}

    ## OLD
    #$fonts = $null
    #if (!$fonts) {
    #    $shellApp = New-Object -ComObject shell.application
    #    $fonts = $shellApp.NameSpace(0x14)
    #}

    foreach ($fontFile in $fontFiles) {
        $name = $fontFile.Name
        Write-Output ("Installing ${name}")
        ### OLD
        ### This is problematic, post 1809 you need admin right plus it never handled overwrites
        ##$fonts.CopyHere($fontFile.FullName)

        ### NEW - but it needs local admin rights
        ## more compatible
        $dstFullName = "$env:SYSTEMROOT” + "\Fonts\" + $name

        $namewithoutext = $name.TrimEnd('.ttf')
        $namewithoutext = $name.TrimEnd('.otf')

        # copy font file, if successful, right to registry
        if (Copy-Item $fontfile $dstFullName -PassThru) {
            New-ItemProperty -Name $namewithoutext -Path "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -PropertyType string -Value $name -Force
        }
    }
    
    ## Display count for all the Font Families
    [void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    $fontfamily = (New-Object System.Drawing.Text.InstalledFontCollection).Families
    $fontfamily.Count
}

Font-Install


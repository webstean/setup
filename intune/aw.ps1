if (Get-Command podman -ErrorAction SilentlyContinue ) {
    ## Stop podman if it is running,. so upgrade will work
    podman machine stop
}

function HideVideoPicturesFileExplorer {
    $folders = @{
        "Pictures" = "{0DDD015D-B06C-45D5-8C4C-F59713854639}"
        "Videos"   = "{35286A68-3C57-41A1-BBB1-0EAE73D76C95}"
    }

    foreach ($name in $folders.Keys) {
        $guid = $folders[$name]
        $regPath = "HKCR:\CLSID\$guid\ShellFolder"

        if (Test-Path $regPath) {
            # Get current attributes
            $attrs = Get-ItemProperty -Path $regPath -Name "Attributes" -ErrorAction SilentlyContinue
            $current = if ($attrs.Attributes) { $attrs.Attributes } else { 0 }

            # Add SFGAO_HIDDEN flag (0x10000000)
            $newAttrs = $current -bor 0x10000000
            Set-ItemProperty -Path $regPath -Name "Attributes" -Value $newAttrs

            Write-Host "$name folder hidden in File Explorer"
        } else {
            Write-Warning "Registry key for $name not found"
        }
    }
    Stop-Process -Name explorer -Force
}
HideVideoPicturesFileExplorer
exit 0

function Install-VLC {
    <#
    .SYNOPSIS
        Installs VLC (if missing) and sets it as the default app
        for common media file types (current user only).

    .NOTES
        Works best on Windows 10/11 with winget installed.
        May require logoff/logon for associations to fully apply.
    #>

    # 1. Install VLC if not already installed
    if (-not (Get-Command "vlc.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "Installing VLC via winget..."
        winget install --id VideoLAN.VLC -e --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "VLC is already installed."
    }

    # 2. VLC ProgIDs (more precise per extension than just VLC.mp4)
    $vlcProgIDs = @{
        ".mp4" = "VLC.mp4"
        ".mkv" = "VLC.mkv"
        ".avi" = "VLC.avi"
        ".mov" = "VLC.mov"
        ".flv" = "VLC.flv"
        ".wmv" = "VLC.wmv"
        ".mp3" = "VLC.mp3"
        ".wav" = "VLC.wav"
        ".flac" = "VLC.flac"
        ".aac" = "VLC.aac"
        ".ogg" = "VLC.ogg"
        ".m4a" = "VLC.m4a"
    }

    $regBase = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts"

    foreach ($ext in $vlcProgIDs.Keys) {
        $progId = $vlcProgIDs[$ext]
        $userChoicePath = Join-Path (Join-Path $regBase $ext) "UserChoice"

        # Ensure key exists
        if (-not (Test-Path $userChoicePath)) {
            New-Item -Path $userChoicePath -Force | Out-Null
        }

        # Set VLC as default handler
        Set-ItemProperty -Path $userChoicePath -Name "ProgId" -Value $progId -Force
        Write-Host "Associated $ext with VLC ($progId)"
    }

    Write-Host "✅ VLC set as default media player for current user. Logoff/logon may be required."
}
Install-VLC

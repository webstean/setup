# Install Lively Wallpaper via winget (if not already installed)
if (-not (Get-AppxPackage | Where-Object { $_.Name -like "*LivelyWallpaper*" })) {
    Write-Host "Installing Lively Wallpaper..."
    winget install --id=rocksdanister.LivelyWallpaper -e --accept-package-agreements --accept-source-agreements
} else {
    Write-Host "Lively Wallpaper already installed."
}

# Path to your MP4 wallpaper
$VideoPath = "C:\Wallpapers\mywallpaper.mp4"

# Lively CLI path (installed in LocalAppData\Programs by default)
$LivelyExe = "$env:LOCALAPPDATA\Programs\Lively Wallpaper\livelycu.exe"

if (-not (Test-Path $LivelyExe)) {
    $LivelyExe = "$env:LOCALAPPDATA\Lively Wallpaper\livelycu.exe"
}

if (-not (Test-Path $LivelyExe)) {
    Write-Error "Could not find livelycu.exe. Start Lively manually once so it registers."
    exit 1
}

# Add the video wallpaper
& "$LivelyExe" add "$VideoPath"

# Set the video wallpaper as active
& "$LivelyExe" setwallpaper "$VideoPath" --monitor 0   # 0 = primary monitor

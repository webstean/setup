#Requires -RunAsAdministrator

##Download the Client
$downloadUrl = "https://aka.ms/GSAClientDownload"
$destinationFolder = [IO.Path]::GetTempPath() + "GSAClient"

## Check if the destination folder exists, create it if it doesn't
if (-not (Test-Path -Path $destinationFolder -PathType Container)) {
    New-Item -Path $destinationFolder -ItemType Directory | Out-Null
}

# Set the destination file path
$destinationFile = Join-Path -Path $destinationFolder -ChildPath "GlobalSecureAccessClient.exe"

try{
    # Download the GSA Client
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($downloadUrl, $destinationFile)
   Write-Output "Client downloaded and saved to $destinationFile." 
}
catch{
   Write-Output "Error downloading the GSAClient: $($_.Exception.Message)" 
    exit
}
Start-Process -FilePath $destinationFile -ArgumentList "/install", "/quiet", "/norestart" -Wait
Get-WmiObject Win32_Product | Where-Object Name -eq 'Global Secure Access Client' | Format-Table IdentifyingNumber, Name

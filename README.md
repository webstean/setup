# setup

**Various setup scripts**

# Windows Subsystem for Linux (WSL) setup - for development, DevOps etc....

$DistroName = 'Ubuntu'
Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/setup.sh | Select-Object -ExpandProperty content | wsl --distribution $DistroName --


@ Setup for Raspberry Pi

curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/setup.sh | bash -
wget https://raw.githubusercontent.com/webstean/setup/main/setup.sh | bash -


Setup an example development project (baresip)




# setup

**Various setup scripts**

## Windows Subsystem for Linux (WSL) setup - for development, DevOps etc....

Set the WSLENV Variable, so these variables will be passed into WSL
```powershell
[Environment]::SetEnvironmentVariable('WSLENV','OneDriveCommercial:OneDriveConsumer:USERDNSDOMAIN:USERDOMAIN:USERNAME','User')
```

Install WSL (with no distribution)
```powershell
### Powershell
### Setup WSL
wsl --update #to update - which will also update from the store including the kernel and would update from in-windows to the store version
wsl --install --no-launch  #--no-distribution - no default distribution
wsl --set-default-version 2
wsl --status
```

Install a WSL distribution
```powershell
## Powershell
$DistroName = 'Ubuntu'
wsl --install $DistroName --no-launch 
Start-Process -FilePath "${env:USERPROFILE}\AppData\Local\Microsoft\WindowsApps\$DistroName.exe" --config --default-user ${env:USERNAME}
```

Install Microsoft Repo, mssql-tools, azure-functions core, msopenjdk, powershell, /etc/wsl.conf, Xwindows, systat, Azure CLI, Oracle Instant Client (if x86-64), Golang, maven, node via nvm, oh-my-posh

```powershell
## Powershell
$DistroName = 'Ubuntu'
$wslsetuppre = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup-pre.sh | Select-Object -ExpandProperty content
$wslsetup1 = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup1.sh | Select-Object -ExpandProperty content
$wslsetup2 = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup2.sh | Select-Object -ExpandProperty content
$wslsetuppre + $wslsetup1 | wsl --distribution $DistroName --
wsl --terminate ${DistroName}
$wslsetuppre + $wslsetup2 | wsl --distribution $DistroName --
```

## Setup for Raspberry Pi

Great device - quick setup

```shell
## bash / zsh etc...
curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/pi/raspi-setup.sh | bash -
```

or

```shell
## bash / zsh etc...
wget https://raw.githubusercontent.com/webstean/setup/main/pi/raspi-setup.sh | bash -
```

## Setup an example development project (baresip)

Under Linux or WSL

```shell
## bash / zsh etc...
curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/baresip/setup.sh | bash -
```
or

```shell
## bash / zsh etc...
wget https://raw.githubusercontent.com/webstean/setup/main/baresip/setup.sh | bash -
```

## Installing Development Fonts [Windows]

https://raw.githubusercontent.com/webstean/setup/main/fonts/font-install.ps1

You'll need to download the fonts and place them into a "fonts" directory, in the same directoy you run this script.

## Create Linux User Accounts

```shell
## bash / zsh etc...
USER=vscode
PASS=vscode
# quietly add a user without password
sudo adduser --quiet --force-badname --disabled-password --shell /bin/bash --ingroup docker $USER

# set password
echo -e '$PASS\n$PASS\n' | sudo passwd $USER
```

## Remove Linux User Account

```shell
## bash / zsh etc...
USER=vscode
sudo deluser --remove-home $USER
```

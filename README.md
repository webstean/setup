# setup

**Various setup scripts**

## Windows Subsystem for Linux (WSL) setup - for development, DevOps etc....

![F-Droid (including pre-releases)](https://img.shields.io/f-droid/v/:appId)

![Visual Studio App Center Releases](https://img.shields.io/visual-studio-app-center/releases/version/:owner/:app/:token)



Set the WSLENV Variable, so these variables will be passed into WSL
```powershell
### Powershell

#### Get UPN
$getupn = @(whoami /upn)
#### Permanently set UPN user variables
if ( -not ([string]::IsNullOrWhiteSpace($getupn))) { [Environment]::SetEnvironmentVariable('UPN',"$getupn",'User') }

#### Set Strong Password variable
$StrongPassword = "settoomethingsecure"
[Environment]::SetEnvironmentVariable('STRONGPASSWORD',$StrongPassword,'User')
 
[Environment]::SetEnvironmentVariable('WSLENV','OneDriveCommercial/p:STRONGPASSWORD:USERDNSDOMAIN:USERDOMAIN:USERNAME:UPN','User')
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
ex
Install a WSL distribution

To get a list of what can be installed
```powershell
wsl --list --online

```
To get Fedora (RHEL like), you need a separate download via:-
https://github.com/WhitewaterFoundry/Fedora-Remix-for-WSL/releases
This has to be sideloaded, which typically requires Developer Mode (and local administrator) with the following commands:-
```powershell
## Powershell
$repo = "WhitewaterFoundry/Fedora-Remix-for-WSL"
$api = "https://api.github.com/repos/" + $repo + "/releases/latest"
$Response = Invoke-RestMethod -Method Get -Uri $api
## Find the latest release
$tag = $Response.tag_name
$file = "Fedora-Remix-for-WSL-SL_" + $tag + ".0_x64_arm64.msixbundle"
$download = "https://github.com/" + $repo + "/releases/download/" + $tag + "/" +$file
Write-Host "Trying to download $download"
Invoke-WebRequest $download -OutFile $file
Import-Module Appx -UseWindowsPowerShell
Add-AppxPackage -Path $file
$DistroName = 'fedoraremix'
"${env:USERPROFILE}\AppData\Local\Microsoft\WindowsApps\${DistroName}.exe" "install --root"
## Custom with sensible settings
$wslinitalsetup = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslfirstsetup.sh | Select-Object -ExpandProperty content
$wslinitalsetup | wsl --user root --distribution ${DistroName} --
wsl --terminate ${DistroName}
wsl --set-default ${DistroName}
```

To use a standard, set the DistroName variable to the distribution you want to install 
```powershell
## Powershell
$DistroName = 'Ubuntu'
wsl --install ${DistroName} --no-launch 
## Run install with no prompt - run as root
Start-Process -Wait -FilePath "${env:USERPROFILE}\AppData\Local\Microsoft\WindowsApps\${DistroName}.exe" "install --root"
$wslinitalsetup = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslfirstsetup.sh | Select-Object -ExpandProperty content
$wslinitalsetup | wsl --user root --distribution ${DistroName} --
## restart, so systemd get enabled 
wsl --terminate ${DistroName}
wsl --set-default ${DistroName}
```

Install Microsoft Repo, mssql-tools, azure-functions core, msopenjdk, powershell, /etc/wsl.conf, Xwindows, systat, Azure CLI, Oracle Instant Client (if x86-64), Golang, maven, node via nvm, oh-my-posh

```powershell
## Powershell
$DistroName = 'Ubuntu'
$wslsetuppre = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup-pre.sh | Select-Object -ExpandProperty content
$wslsetup1   = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup1.sh | Select-Object -ExpandProperty content
$wslsetup2   = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wsl/wslsetup2.sh | Select-Object -ExpandProperty content
$wslsetuppre + $wslsetup1 | wsl --distribution ${DistroName} --
wsl --terminate ${DistroName}
$wslsetuppre + $wslsetup2 | wsl --distribution ${DistroName} --
```

To delete and start again

> **Warning**
> This will delete the root filesystem of the Linux distribution

```powershell
## Powershell
$DistroName = 'Ubuntu'
wsl --terminate ${DistroName}
wsl --list
## Now unregister the distribution - which deletes the root filesystem
wsl --unregister ${DistroName}

```

## Setup for Raspberry Pi

Great device - quick setup

```shell
## bash / zsh with curl etc...
curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/pi/raspi-setup.sh | bash -
```

or

```shell
## bash / zsh with wget etc...
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
NUSER=vscode
NPASS=vscode
# quietly add a user without password
sudo adduser --quiet --gecos "" --force-badname --disabled-password --shell /bin/bash ${NUSER}

# set password
echo -e '${NPASS}\n${NPASS}\n' | sudo passwd ${NUSER}
```

## Remove Linux User Account

```shell
## bash / zsh etc...
NUSER=vscode
sudo deluser --remove-home ${NUSER}
```

## List of WSL Root Filesystems

```powershell
## Now find and delete the root filesystem
$RootPathFS = (Get-ChildItem HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss | ForEach-Object {Get-ItemProperty $_.PSPath}) | Select-Object DistributionName, @{n="Path";e={$_.BasePath + "\rootfs"}} | Select-Object DistributionName, -ExpandProperty Path
```


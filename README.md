# setup

**Various setup scripts**

## Windows Subsystem for Linux (WSL) setup - for development, DevOps etc....

Install Microsoft Repo, mssql-tools, azure-functions core, msopenjdk, powershell, /etc/wsl.conf, Xwindows, systat, Azure CLI, Oracle Instant Client (if x86-64), Golang, maven, node via nvm, oh-my-posh

```log
$DistroName = 'Ubuntu'
Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wslsetup1.sh | Select-Object -ExpandProperty content | wsl --distribution $DistroName --
```

## Setup for Raspberry Pi

```log
curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/pisetup.sh | bash -
wget https://raw.githubusercontent.com/webstean/setup/main/pisetup.sh | bash -
```

Setup an example development project (baresip)




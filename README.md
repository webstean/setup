# setup

**Various setup scripts**

## Windows Subsystem for Linux (WSL) setup - for development, DevOps etc....

Install WSL
```shell
    $DistroName = 'Ubuntu'
    Start-Process -FilePath "${env:USERPROFILE}\AppData\Local\Microsoft\WindowsApps\$DistroName.exe" --config
```



Install Microsoft Repo, mssql-tools, azure-functions core, msopenjdk, powershell, /etc/wsl.conf, Xwindows, systat, Azure CLI, Oracle Instant Client (if x86-64), Golang, maven, node via nvm, oh-my-posh

```shell
    $DistroName = 'Ubuntu'
    $wslsetuppre = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wslsetup-pre.sh | Select-Object -ExpandProperty content
    $wslsetup1 = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wslsetup1.sh | Select-Object -ExpandProperty content
    $wslsetup2 = Invoke-WebRequest -uri https://raw.githubusercontent.com/webstean/setup/main/wslsetup2.sh | Select-Object -ExpandProperty content
    $wslsetuppre + $wslsetup1 | wsl --distribution $DistroName --
    wsl --terminate ${DistroName}
    $wslsetuppre + $wslsetup2 | wsl --distribution $DistroName --
```

## Setup for Raspberry Pi

```shell
curl -fsSL https://raw.githubusercontent.com/webstean/setup/main/pisetup.sh | bash -
wget https://raw.githubusercontent.com/webstean/setup/main/pisetup.sh | bash -
```

Setup an example development project (baresip)




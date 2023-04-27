#!/usr/bin/env bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

# Setup WSL Linux for use Visual Studio Code (VS Code)
# See: https://code.visualstudio.com/docs/remote/linux
# for VS Code to work remotely on a MAC
# See: https://support.apple.com/en-au/guide/mac-help/mchlp1066/mac

# Supported Distributions (WSL and remote)
# - Red Hat and deriatvies (Oracle & Centos)
# - Debian 
# - Ubuntu
# - Raspbian (Raspberry Pi)
# - Alpine - note, MS Code only has limited remoted support for Alpine

# if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi
if [[ $(id -u) -eq 0 ]] ; then echo "Please DO NOT run as root" ; exit 1 ; fi

# Set SHELL varible, in case it not defined
if [ -z "$SHELL" ] ; then
    export SHELL=/bin/sh
fi

# Enable sudo for all users - by modifying /etc/sudoers
if ! (sudo grep NOPASSWD:ALL /etc/sudoers ) ; then 
    # Everyone
    bash -c "echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
    # AAD
    bash -c "echo '%aad_admins ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
    # AD DS
    bash -c "echo '%AAD\ DC\ Administrators ALL=(ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
fi

# Determine package manager for installing packages
DNF_CMD=$(which dnf) > /dev/null 2>&1
YUM_CMD=$(which yum) > /dev/null 2>&1
APT_CMD=$(which apt-get) > /dev/null 2>&1
APK_CMD=$(which apk) > /dev/null 2>&1
# ${CMD_INSTALL} package
if [[ ! -z $DNF_CMD ]] ; then
    export CMD_INSTALL="sudo dnf install -y"
    export CMD_UPGRADE="sudo dnf upgrade -y"
    export CMD_UPDATE="sudo dnf upgrade"
    export CMD_CLEAN="sudo dnf clean all && rm -rf /tmp/* /var/tmp/*"
elif [[ ! -z $YUM_CMD ]] ; then
    export CMD_INSTALL="sudo yum install -y"
    export CMD_UPGRADE="sudo yum upgrade -y"
    export CMD_UPDATE="sudo yum update"
    export CMD_CLEAN="sudo yum clean all && rm -rf /tmp/* /var/tmp/*"
elif [[ ! -z $APT_CMD ]] ; then
    export CMD_INSTALL="sudo apt-get install -y"
    export CMD_UPGRADE="sudo apt-get upgrade -y"
    export CMD_UPDATE="sudo apt-get update"
    export CMD_CLEAN="sudo apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"
elif [[ ! -z $APK_CMD ]] ; then
    export CMD_INSTALL="sudo apk add -y"
    export CMD_UPGRADE="sudo apt-get upgrade -y"
    export CMD_UPDATE="sudo apk update"
    export CMD_CLEAN="sudo apk clean && rm -rf /tmp/* /var/tmp/*"
else
  echo "error: can't find a package manager"
  exit 1;
fi
echo "Package Manager (Install) : ${CMD_INSTALL}"
echo "Package Manager (Update)  : ${CMD_UPDATE}"
echo "Package Manager (Upgrade) : ${CMD_UPGRADE}"

# Any specifics packages for specific distributions
# Alpine apt - sudo won't be there by default on Alpine
if [ -f /sbin/apk ] ; then  
    ${CMD_INSTALL} sudo
    ${CMD_INSTALL} musl-dev libaio-dev libnsl-dev
fi

# Alpine Libraries for Oracle client
if [ -f /sbin/apk ] ; then
    # enable Edge repositories - hopefully this will go away eventually
    echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories
    ${CMD_UPDATE}
    ${CMD_INSTALL} libnsl libaio musl-dev autconfig
fi

# setup /opt for oracle/microsoft etc..
if [   -d /opt ] ; then sudo rm -rf /opt ; fi 
if [ ! -d /opt ] ; then sudo mkdir -p /opt ; sudo chmod 755 /opt ; fi 
sudo chmod 755 /opt

# Add Microsoft Repos and Applications
if [ -f /usr/bin/apt ] ; then
    # make sure prereqs are installs
    ${CMD_INSTALL} apt-transport-https ca-certificates curl software-properties-common
    
    # Import the public repository GPG keys (depreciated)
    # Note: Instead of using this command a keyring should be placed directly in the 
    # /etc/apt/trusted.gpg.d/ directory with a descriptive name and either "gpg" or "asc" 
    # as file extension.
    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

    # Register the Microsoft Ubuntu repository
    repo=https://packages.microsoft.com/$(lsb_release -s -i)/$(lsb_release -sr)/prod
    # convert to lowercase
    repo=${repo,,}
    echo $repo
    sudo apt-add-repository --yes $repo
    
    # Update the list of products
    $INSTALL_UPDATE
    
    # Skip ELA prompt - I hope
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections

    # Install Microsoft tools
    ${INSTALL_CMD} azure-functions-core-tools
    ${INSTALL_CMD} mssql-tools sqlcmd
    ${INSTALL_CMD} powershell
    ${INSTALL_CMD} msopenjdk-17
        
    if [ -f /etc/profile.d/microsoft-powershell.sh ] ; then sudo rm -f /etc/profile.d/microsoft-powershell.sh ; fi
    if (which pwsh) ; then 
        sudo sh -c 'echo   echo \"Powershell \(pwsh\) found!\"     >>  /etc/profile.d/microsoft-powershell.sh'
    fi
fi

## Check if WSL2, if so install minimal X11 and set some WSL specific settings
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]]; then
    ${CMD_INSTALL} xscreensaver
    ${CMD_INSTALL} x11-apps
    echo $DISPLAY
    # Start xeyes to show X11 working - hopefully (now just works with WSL 2 plus GUI)
    xeyes &
    # Install browser for sqlite
    ${CMD_INSTALL} sqlitebrowser
    sqlitebrowser &
    ## Since this WSL set some settings
    if [ -f /etc/wsl.conf ] ; then sudo rm -f /etc/wsl.conf ; fi
    sudo sh -c 'echo [boot]                     >>  /etc/wsl.conf'
    sudo sh -c 'echo systemd=true               >>  /etc/wsl.conf'
    
    sudo sh -c 'echo [automount]                >>  /etc/wsl.conf'
    sudo sh -c 'echo root = \/mnt               >>  /etc/wsl.conf'
    sudo sh -c 'echo options = "metadata"       >>  /etc/wsl.conf'

    sudo sh -c 'echo [interop]                  >>  /etc/wsl.conf'
    sudo sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sudo sh -c 'echo appendWindowsPath = true   >>  /etc/wsl.conf'

    sudo sh -c 'echo [network]                  >>  /etc/wsl.conf'
    sudo sh -c 'echo generateResolvConf = true  >>  /etc/wsl.conf'
    sudo sh -c 'echo generateHosts = true       >>  /etc/wsl.conf'
fi


                                       

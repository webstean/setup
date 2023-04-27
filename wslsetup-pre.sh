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

#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## only supports running as root
if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

## check required variables are defined
if [[ -z "${USERNAME}" && -z "${STRONGPASSWORD}" ]] ; then
    echo "Required environment variables not set"
    exit 1
fi

## Determine OS platform
UNAME=$(uname | tr "[:upper:]" "[:lower:]")
# If Linux, try to determine specific distribution
if [ "$UNAME" == "linux" ]; then
    # If available, use LSB to identify distribution
    if [ -f /etc/lsb-release -o -d /etc/lsb-release.d ]; then
        export DISTRO=$(lsb_release -i | cut -d: -f2 | sed s/'^\t'//)
    # Otherwise, use release info file
    else
        export DISTRO=$(ls -d /etc/[A-Za-z]*[_-][rv]e[lr]* | grep -v "lsb" | cut -d'/' -f3 | cut -d'-' -f1 | cut -d'_' -f1)
    fi
fi
echo $DISTRO

if [[ ! $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    echo "Sorry, only supports WSL2 (not WSL1)"
    exit 1
fi

exit 0

## Check if WSL2, enable systemd etc via wsl.conf, sort out sudo
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if [ -f /etc/wsl.conf ] ; then sudo rm -f /etc/wsl.conf ; fi
    sudo sh -c 'echo [boot]                     >>  /etc/wsl.conf'
    ## enable systemd for compatiblity
    sudo sh -c 'echo systemd=true               >>  /etc/wsl.conf'

    sudo sh -c 'echo [automount]                >>  /etc/wsl.conf'
    sudo sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sudo sh -c 'echo root = \/mnt               >>  /etc/wsl.conf'
    ## copy from: https://github.com/WhitewaterFoundry/Fedora-Remix-for-WSL/blob/master/linux_files/wsl.conf
    sudo sh -c 'echo options = "metadata,uid=1000,gid=1000,umask=22,fmask=11,case=off" >>  /etc/wsl.conf'
    sudo sh -c 'echo mountFsTab = true          >>  /etc/wsl.conf'

    sudo sh -c 'echo [network]                  >>  /etc/wsl.conf'
    ## unlike WSL1 - let WSL manage this itself - it will be a lot more reliable
    ## still need to be customised if using a proxy via /etc/profile.d/web-proxy.sh'
    sudo sh -c 'echo generateResolvConf = true  >>  /etc/wsl.conf'
    sudo sh -c 'echo generateHosts = true       >>  /etc/wsl.conf'
   
    ## if sudo group exists - add
    if (grep sudo /etc/group) ; then
        usermod -a -G sudo ${USERNAME}
    fi
    ## if docker group exists - add
    if (grep docker /etc/group) ; then
        usermod -a -G docker ${USERNAME}
    fi
   
else
    echo "Sorry, only supports WSL2 (not WSL1)"
    exit 1
fi

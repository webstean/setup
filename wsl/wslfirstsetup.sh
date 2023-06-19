#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## Check if WSL2, enable systemd etc via wsl.conf
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if [ -f /etc/wsl.conf ] ; then sudo rm -f /etc/wsl.conf ; fi
    sudo sh -c 'echo [boot]                     >>  /etc/wsl.conf'
    sudo sh -c 'echo systemd=true               >>  /etc/wsl.conf'

    sudo sh -c 'echo [automount]                >>  /etc/wsl.conf'
    sudo sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sudo sh -c 'echo root = \/mnt               >>  /etc/wsl.conf'
    ## copy from: https://github.com/WhitewaterFoundry/Fedora-Remix-for-WSL/blob/master/linux_files/wsl.conf
    sudo sh -c 'echo options = "metadata,uid=1000,gid=1000,umask=22,fmask=11,case=off" >>  /etc/wsl.conf'
    sudo sh -c 'echo mountFsTab = true          >>  /etc/wsl.conf'

    sudo sh -c 'echo [interop]                  >>  /etc/wsl.conf'
    sudo sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sudo sh -c 'echo appendWindowsPath = true   >>  /etc/wsl.conf'

    sudo sh -c 'echo [network]                  >>  /etc/wsl.conf'
    sudo sh -c 'echo generateResolvConf = true  >>  /etc/wsl.conf'
    sudo sh -c 'echo generateHosts = true       >>  /etc/wsl.conf'
    
    echo "USERNAME = [${USERNAME}]"
    if [ ! -z "${USERNAME+x}" ] ; then
        echo "Setting default WSL user as: $USERNAME"
        sudo sh -c 'echo [user]                     >>  /etc/wsl.conf'
        sudo sh -c 'echo default = ${USERNAME}      >>  /etc/wsl.conf'
    fi
else
    echo "Sorry, only supports WSL2 (not WSL1)"
    exit 1
fi

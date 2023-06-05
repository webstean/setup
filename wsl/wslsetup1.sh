#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## Check if WSL2, if so install minimal X11 and set some WSL specific settings
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]]; then
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

    if [[ -z "${USERNAME}" ]]; then 
        sudo sh -c 'echo [user]                     >>  /etc/wsl.conf'
        sudo sh -c 'echo default = ${USERNAME}      >>  /etc/wsl.conf'
    fi
else
    echo "Sorry, can only install on WSL2 (not WSL1)"
    exit 1
fi


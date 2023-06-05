#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

# setup /opt for oracle/microsoft etc..
if [   -d /opt ] ; then sudo rm -rf /opt ; fi 
if [ ! -d /opt ] ; then sudo mkdir -p /opt ; sudo chmod 755 /opt ; fi 

# get everything upto date
${CMD_UPDATE}
${CMD_UPGRADE}

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
    ${CMD_UPDATE}
    
    # Skip EULA prompt
    echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
    echo msodbcsql18 msodbcsql/ACCEPT_EULA boolean true | sudo debconf-set-selections
    export ACCEPT_EULA=y

    # Install Microsoft tools
    ${CMD_INSTALL} ttf-mscorefonts-installer
    ${CMD_INSTALL} azure-functions-core-tools
    ${CMD_INSTALL} mssql-tools 
    ${CMD_INSTALL} sqlcmd
    ${CMD_INSTALL} powershell
       
    if [ -f /etc/profile.d/microsoft-powershell.sh ] ; then sudo rm -f /etc/profile.d/microsoft-powershell.sh ; fi
    if (which pwsh) ; then 
        sudo sh -c 'echo   echo \"Powershell \(pwsh\) found!\"     >>  /etc/profile.d/microsoft-powershell.sh'
    fi
    
    # Install Java
    ${CMD_INSTALL} msopenjdk-17
    ${CMD_INSTALL} default-jre
    if [ -f /etc/profile.d/microsoft-java.sh ] ; then sudo rm -f /etc/profile.d/microsoft-java.sh ; fi
    if (which pwsh) ; then 
        sudo sh -c 'echo   echo \"Microsoft Java \(java\) found!\"     >>  /etc/profile.d/microsoft-java.sh'
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

    if [[ -z "${USERNAME}" ]]; then 
        sudo sh -c 'echo [user]                     >>  /etc/wsl.conf'
        sudo sh -c 'echo default = ${USERNAME}      >>  /etc/wsl.conf'
    fi
else
    echo "Sorry, can only install on WSL2 (not WSL1)"
    exit 1
fi


# install and config sysstat
$CMD_INSTALL sysstat
sudo sh -c 'echo ENABLED="true" >  /etc/default/sysstat'
sudo systemctl stop sysstat --no-pager
sudo systemctl enable sysstat --no-pager
sudo systemctl start sysstat --no-pager
sudo systemctl status sysstat --no-pager
# sar -u

# system will no reboot

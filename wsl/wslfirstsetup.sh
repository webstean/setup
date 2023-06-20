#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## only supports running as root
if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi

## Check if WSL2, enable systemd etc via wsl.conf
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if [ -f /etc/wsl.conf ] ; then rm -f /etc/wsl.conf ; fi
    sh -c 'echo [boot]                     >>  /etc/wsl.conf'
    ## enable systemd for compatiblity
    sh -c 'echo systemd=true               >>  /etc/wsl.conf'

    sh -c 'echo [automount]                >>  /etc/wsl.conf'
    sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sh -c 'echo root = \/mnt               >>  /etc/wsl.conf'
    ## copy from: https://github.com/WhitewaterFoundry/Fedora-Remix-for-WSL/blob/master/linux_files/wsl.conf
    sh -c 'echo options = "metadata,uid=1000,gid=1000,umask=22,fmask=11,case=off" >>  /etc/wsl.conf'
    sh -c 'echo mountFsTab = true          >>  /etc/wsl.conf'

    sh -c 'echo [interop]                  >>  /etc/wsl.conf'
    sh -c 'echo enabled = true             >>  /etc/wsl.conf'
    sh -c 'echo appendWindowsPath = true   >>  /etc/wsl.conf'

    sh -c 'echo [network]                  >>  /etc/wsl.conf'
    ## unlike WSL1 - let WSL manage this itself - it will be a lot more reliable
    ## still need to be customised if using a proxy via /etc/profile.d/web-proxy.sh'
    sh -c 'echo generateResolvConf = true  >>  /etc/wsl.conf'
    sh -c 'echo generateHosts = true       >>  /etc/wsl.conf'
    
    echo "USERNAME = [${USERNAME}]"
    if [ ! -z "${USERNAME}" ] ; then
        echo "Setting default WSL user as: $USERNAME"
        sh -c 'echo [user]                     >>  /etc/wsl.conf'
        sh -c 'echo default = ${USERNAME}      >>  /etc/wsl.conf'
    fi
    # Enable sudo for all users - by modifying /etc/sudoers
    if ! (sudo grep NOPASSWD:ALL /etc/sudoers  > /dev/null 2>&1 ) ; then 
        # Everyone
        bash -c "echo '#Everyone - WSL' | sudo EDITOR='tee -a' visudo"
        bash -c "echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
        # AAD (experimental)
        bash -c "echo '#Azure AD - WSL' | sudo EDITOR='tee -a' visudo"
        bash -c "echo '%sudo aad_admins=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
    else
        echo "/etc/sudoers edit not required!"
    fi
else
    echo "Sorry, only supports WSL2 (not WSL1)"
    exit 1
fi

if [[ ! -z "${USERNAME+x}" && ! -z "${STRONGPASSWORD}" ]] ; then
    echo "Setting up [$USERNAME]"
    # quietly add a user without password
    adduser --quiet --gecos "" --force-badname --disabled-password --shell /bin/bash ${USERNAME}
    # set password
    echo -e '${STRONGPASSWORD}\n${STRONGPASSWORD}\n' | passwd ${USERNAME}
else
    echo "Required environment variables not set"
    exit 1
fi

## Environent Variables for proxy support
sh -c 'echo "## Web Proxy Setup - edit as required"                               >  /etc/profile.d/web-proxy.sh'
sh -c 'echo "## Squid default port is 3128, but many setup the proxy on port 80,8000,8080" >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "anon_web-proxy() {"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Set variable for proxy and port"                                >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  port=3128"                                                         >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  webproxy=webproxy.local"                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Proxy Exceptions"                                               >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8" >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Anonymous Proxy"                                                >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export {http,https,ftp}_proxy=http://\${webproxy}:\${port}"        >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export HTTPS_PROXY=http://\${webproxy}:\${port}"                   >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export FTP_PROXY=http://\${webproxy}:\${port}"                     >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  return;"                                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "}"                                                                   >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "auth_web-proxy() {"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Set variable for proxy and port"                                >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  port=3128"                                                         >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  webproxy=webproxy.local"                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Set variables for authenticated proxy"                          >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  USERN=UserName"                                                    >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  @ME=Password"                                                      >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Proxy Exceptions"                                               >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8" >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export {http,https,ftp}_proxy=http://\${USERN}:\${@ME}\${webproxy}:\${port}/"  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  return;"                                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "}"                                                                   >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "## uncomment for unauthenticated proxy ##"                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "# anon_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "## uncomment for authenticated proxy ##"                             >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "# auth_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "export extaddr=$(curl -s ifconfig.me)"                               >> /etc/profile.d/web-proxy.sh'

#!/usr/bin/bash

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## Check if WSL2, enable systemd etc via wsl.conf
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
    
    echo "USERNAME = ${USERNAME}]"
    if [ -z "${USERNAME}" ] ; then
        echo "Setting default WSL user as: $USERNAME"
        sudo sh -c 'echo [user]                     >>  /etc/wsl.conf'
        sudo sh -c 'echo default = ${USERNAME}      >>  /etc/wsl.conf'
    fi
else
    echo "Sorry, only supports WSL2 (not WSL1)"
    exit 1
fi

## Global environmment variables (editable)
sudo sh -c "echo export FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT=1  >  /etc/profile.d/global-variables.sh"
sudo sh -c "echo # export AW1=AW1       >>  /etc/profile.d/global-variables.sh"
# Turn off Microsoft telemetry for Azure Function Tools

# Environent Variables for proxy support
# Squid default port is 3128, but many setup the proxy on port 80,8000,8080
sudo sh -c 'echo "## Web Proxy Setup - edit as required"                               >  /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "anon_web-proxy() {"                                                       >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Set variable for proxy and port"                                >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  port=3128"                                                         >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  webproxy=webproxy.local"                                           >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Proxy Exceptions"                                               >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8" >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Anonymous Proxy"                                                >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export {http,https,ftp}_proxy=http://\${webproxy}:\${port}"        >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export HTTPS_PROXY=http://\${webproxy}:\${port}"                   >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export FTP_PROXY=http://\${webproxy}:\${port}"                     >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  return;"                                                           >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "auth_web-proxy() {"                                                       >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Set variable for proxy and port"                                >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  port=3128"                                                         >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  webproxy=webproxy.local"                                           >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Set variables for authenticated proxy"                          >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  USERN=UserName"                                                    >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  @ME=Password"                                                      >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  ## Proxy Exceptions"                                               >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8" >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  export {http,https,ftp}_proxy=http://\${USERN}:\${@ME}\${webproxy}:\${port}/"  >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "  return;"                                                           >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "}"                                                                   >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "# anon_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "# auth_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sudo sh -c 'echo "export extaddr=$(curl -s ifconfig.me)"                               >> /etc/profile.d/web-proxy.sh'

# leave along at C.UTF-8 for maximum compatiblity
##sudo locale-gen "C.UTF-8"
##sudo update-locale LANG=C.UTF-8 LANGUAGE=C.UTF-8 LC_MESSAGES=C.UTF-8 LC_COLLATE= LC_CTYPE= LC_ALL=C

# the system will now reboot

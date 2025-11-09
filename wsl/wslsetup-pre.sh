# Setup WSL Linux for use Visual Studio Code (VS Code)
# See: https://code.visualstudio.com/docs/remote/linux
# for VS Code to work remotely on a MAC
# See: https://support.apple.com/en-au/guide/mac-help/mchlp1066/mac

# Supported Distributions (WSL and remote)
# - Red Hat and deriatvies (Oracle & Centos)
# - Debian 
# - Ubuntu
# - Raspbian (Raspberry Pi)
# - Alpine - note, MS Code only has limited remote support for Alpine

# Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable

## WSL only
if [[ ! $(grep -i WSL /proc/sys/kernel/osrelease) ]]; then echo "Only runs on WSL" ; exit 1 ; fi

# if [[ $(id -u) -ne 0 ]] ; then echo "Please run as root" ; exit 1 ; fi
#if [[ $(id -u) -eq 0 ]] ; then echo "Please DO NOT run as root" ; exit 1 ; fi


# Set SHELL varible, in case it not defined
if [ -z "$SHELL" ] ; then
    export SHELL=/bin/sh
fi

# Enable sudo for all users - by modifying /etc/sudoers
if ! (sudo grep NOPASSWD:ALL /etc/sudoers  > /dev/null 2>&1 ) ; then 
    # Everyone
    bash -c "echo '#Everyone - WSL' | sudo EDITOR='tee -a' visudo"
    bash -c "echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
    # AAD
    bash -c "echo '#Azure AD - WSL' | sudo EDITOR='tee -a' visudo"
    bash -c "echo '%sudo aad_admins=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
else
    echo "/etc/sudoers edit not required!"
fi

## Template: Environment Variables for proxy support
sh -c 'echo "## Web Proxy Setup - edit as required"                               >  /etc/profile.d/web-proxy.sh'
sh -c 'echo "## Squid default port is 3128, but many setup the proxy on port 80,8000,8080" >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "anon_web-proxy() {"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Set variable for proxy and port"                                >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  port=3128"                                                         >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  webproxy=webproxy.local"                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Proxy Exceptions"                                               >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export NO_PROXY=localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8" >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  ## Anonymous Proxy"                                                >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export {http,https}_proxy=http://\${webproxy}:\${port}"        >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  export HTTPS_PROXY=http://\${webproxy}:\${port}"                   >> /etc/profile.d/web-proxy.sh'
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
sh -c 'echo "  export {http,https}_proxy=http://\${USERN}:\${@ME}\${webproxy}:\${port}/"  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "  return;"                                                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "}"                                                                   >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "## uncomment for unauthenticated proxy ##"                           >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "# anon_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "## uncomment for authenticated proxy ##"                             >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "# auth_web-proxy()"                                                  >> /etc/profile.d/web-proxy.sh'
sh -c 'echo "export extaddr=\$(curl -s ifconfig.me)"                              >> /etc/profile.d/web-proxy.sh'

exit 0

# Determine package manager for installing packages
DNF_CMD=$(which dnf) > /dev/null 2>&1
YUM_CMD=$(which yum) > /dev/null 2>&1
APT_CMD=$(which apt-get) > /dev/null 2>&1
APK_CMD=$(which apk) > /dev/null 2>&1
RPM_CMD=$(which rpm) > /dev/null 2>&1
# ${CMD_INSTALL} package
if [[ ! -z $DNF_CMD ]] ; then
    export CMD_INSTALL="sudo ACCEPT_EULA=Y dnf install -y"
    export CMD_UPGRADE="sudo dnf upgrade -y"
    export CMD_UPDATE="sudo dnf upgrade"
    export CMD_CLEAN="sudo dnf clean all && sudo rm -rf /tmp/* /var/tmp/*"
elif [[ ! -z $YUM_CMD ]] ; then
    export CMD_INSTALL="sudo ACCEPT_EULA=Y yum install -y"
    export CMD_UPGRADE="sudo yum upgrade -y"
    export CMD_UPDATE="sudo yum update"
    export CMD_CLEAN="sudo yum clean all && sudo rm -rf /tmp/\* /var/tmp/\*"
elif [[ ! -z $APT_CMD ]] ; then
    export DEBIAN_FRONTEND=noninteractive
    export CMD_INSTALL="sudo ACCEPT_EULA=Y apt-get install -y"
    export CMD_UPGRADE="sudo apt-get upgrade -y"
    export CMD_UPDATE="sudo apt-get update"
    export CMD_CLEAN="sudo apt-get clean -y && sudo rm -rf /var/lib/apt/lists/* && sudo rm -rf /tmp/* && sudo rm -rf /var/tmp/*"
elif [[ ! -z $APK_CMD ]] ; then
    export CMD_INSTALL="sudo apk add -y"
    export CMD_UPGRADE="sudo apk upgrade -y"
    export CMD_UPDATE="sudo apk update"
    export CMD_CLEAN="sudo apk clean && sudo rm -rf /tmp/\* /var/tmp/\*"
elif [[ ! -z $APK_CMD ]] ; then
    export CMD_INSTALL="sudo export ACCEPT_EULA='y' rpm -ivh"
    export CMD_UPGRADE=""
    export CMD_UPDATE="sudo export ACCEPT_EULA='y' rpm -ivh"
    export CMD_CLEAN=""
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

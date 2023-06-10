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

# Set Timezone - includes keeping the machine to the right time but not sure how?
# WSL Error: System has not been booted with systemd as init system (PID 1). Can't operate.
#          : unless you edit /etc/wsl.conf to enable systemd
sudo timedatectl set-timezone Australia/Melbourne
timedatectl status 

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

    ## if java is installed, install maven build system
    ## Maven is a build automation tool used primarily for Java projects
    if (which java) ; then
        ${CMD_INSTALL} maven
    fi
fi

## Check if WSL2, - XWindows is supported (natively) - so install some GUI stuff
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]]; then
    ${CMD_INSTALL} xscreensaver
    ${CMD_INSTALL} x11-apps
    echo $DISPLAY
    # Start xeyes to show X11 working - hopefully (now just works with WSL 2 plus GUI)
    xeyes &
    # Install browser for sqlite
    ${CMD_INSTALL} sqlitebrowser
    sqlitebrowser &
fi

# install and config sysstat
$CMD_INSTALL sysstat
sudo sh -c 'echo ENABLED="true" >  /etc/default/sysstat'
sudo systemctl stop sysstat --no-pager
sudo systemctl enable sysstat --no-pager
sudo systemctl start sysstat --no-pager
sudo systemctl status sysstat --no-pager
# sar -u

# Docker - requires systemd
if [ 1 ] ; then

    # get rid of anything old
    sudo apt-get remove docker docker-engine docker.io containerd runc
    
    # install
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo chmod 755 get-docker.sh
    sudo sh get-docker.sh
    
    ## verify
    sudo docker run hello-world
    
    # run Azure CLI as a container
    #sudo git clone https://github.com/gtrifonov/raspberry-pi-alpine-azure-cli.git
    #sudo docker build . -t azure-cli
    #sudo docker run -d -it --rm --name azure-cli azure-cli

    ## allow user to run docker commands
    sudo -E usermod -aG docker $USER
    
    ## set controlable via Docker Desktop
    sudo sh -c 'echo "export DOCKER_HOST=tcp://localhost:2375" > /etc/profile.d/docker.sh'
fi

# Ensure git is install and then configure it 
${CMD_INSTALL} git
if [ -x /usr/bin/git ]; then
    git config --global color.ui true
    git config --global user.name "Andrew Webster"
    if [[ -z "${UPN}" ]]; then 
        git config --global user.email "${UPN}"
    fi
    # cached credentials for 2 hours
    git config --global credential.helper 'cache --timeout 7200'
    git config --global advice.detachedHead false
    git config --list
fi

# Install Oracle Database Instant Client via permanent OTN link
oracleinstantclientinstall() {
    # Dependencies for Oracle Client
    ${CMD_INSTALL} libaio 
    ${CMD_INSTALL} libaio2 
    ${CMD_INSTALL} unzip
    # Permanent Link (latest version) - Instant Client - Basic (x86 64 bit) - you need this for anything else to work
    # Note: there is no Instant Client for the ARM processor, Intel/AMD x86 only
    tmpdir=$(mktemp -d)
    wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basic-linuxx64.zip -nc --directory-prefix=${tmpdir}
    wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-sqlplus-linuxx64.zip -nc --directory-prefix=${tmpdir}
    wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-tools-linuxx64.zip -nc --directory-prefix=${tmpdir}

    if [   -d /opt/oracle ] ; then sudo rm -rf /opt/oracle ; fi 
    if [ ! -d /opt/oracle ] ; then sudo mkdir -p /opt/oracle ; sudo chmod 755 /opt/oracle ; fi 
    echo "Extracting Oracle Instant client..."
    sudo unzip -qo ${tmpdir}/instantclient-basic*.zip -d /opt/oracle
    sudo unzip -qo ${tmpdir}/instantclient-sqlplus*.zip -d /opt/oracle
    sudo unzip -qo ${tmpdir}/instantclient-tools*.zip -d /opt/oracle

    # rm instantclient-basic*.zip
    set -- /opt/oracle/instantclient*
    export LD_LIBRARY_PATH=$1
    if [ -f /etc/profile.d/instant-oracle.sh ] ; then
        sudo rm /etc/profile.d/instant-oracle.sh 
    fi
    ### Enviromnet variables for Instance Client
    ### https://docs.oracle.com/en/database/oracle/oracle-database/21/lacli/environment-variables-instant-client.html
    sudo sh -c "echo # Oracle Instant Client Setup     >  /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo oracle-instantclient\(\) {        >>  /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo   export LD_LIBRARY_PATH=$1       >> /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo   export PATH=$1:'\$PATH'         >> /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo }                                 >> /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo if [ -d /opt/oracle/instantclient\* ] \; then >> /etc/profile.d/instant-oracle.sh"
    sudo sh -c 'echo   echo \"Oracle Database Instant Client \(sqlplus\) found!\"     >>  /etc/profile.d/instant-oracle.sh'
    sudo sh -c "echo   oracle-instantclient            >>  /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo fi                                >>  /etc/profile.d/instant-oracle.sh"
    sudo sh -c "echo # example: sqlplus scott/tiger@//myhost.example.com:1521/myservice >>  /etc/profile.d/instant-oracle.sh"
 
    # Q: How do I ensure that my Oracle Net files like "tnsnames.ora" and "sqlnet.ora" are being used in Instant Client?
    # A: Files like "tnsnames.ora", "sqlnet.ora" and "oraaccess.xml" will be located by Instant Client by setting the TNS_ADMIN environment variable
    # or registry entry to the directory containing the files. Use the full directory path; do not include a file name. 
    # Alternatively create a subdirectory "network/admin" under the Instant Client directory for the Oracle Net files.
    # This is the default location and so no TNS_ADMIN variable is required.
    mkdir -p ${LD_LIBRARY_PATH}/network/admin
    
    # copy tnsnames inplace if found
    return 0
}
    
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
    # only supported on x86 64bit
    oracleinstantclientinstall
fi

# Join Active Directory 
joinactivedirectory() {
    # Environment variables
    # USERDNSDOMAIN : DNS Name of Active Directory domain
    # JOINACC       : Name of Join Account
    if [[ -z "${USERDNSDOMAIN}" ]]; then 
        echo "Variable: USERNDNSDOMAIN is not assigned"
        return 1
    fi
    # Dependencies for AD Join
    ${CMD_INSTALL} realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools
    ${CMD_INSTALL} cifs-utils
    # Info on Domain
    echo "Join AD domain: ${USERDNSDOMAIN}"
    sudo realm discover ${USERDNSDOMAIN}
    # Generatoe Kerberos ticket
    sudo kinit contosoadmin@${USERDNSDOMAIN}
    # Join the Domain
    sudo realm join --verbose ${USERDNSDOMAIN}-U 'contosoadmin@${USERDNSDOMAIN}'

    return 0
}

# Mount SMB Azure File Share on Linux - expects to already be logged in
mountazurefiles() {
    # https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-linux?tabs=Ubuntu%2Csmb311
    ${CMD_INSTALL} cifs-utils
    ${CMD_INSTALL} autofs
    
    az login
    if [ -z ${RESOURCE_GROUP_NAME} ] ; then
        return 1;
    fi
    if [ -z ${STORAGE_ACCOUNT_NAME} ] ; then
        return 1;
    fi
    
    # This command assumes you have logged in with az login
    HTTP_ENDPOINT=$(az storage account show \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $STORAGE_ACCOUNT_NAME \
        --query "primaryEndpoints.file" --output tsv | tr -d '"')
    SMBPATH=$(echo $HTTP_ENDPOINT | cut -c7-${#HTTP_ENDPOINT})
    FILE_HOST=$(echo $-- | tr -d "/")

    nc -zvw3 $FILE_HOST 445
        
    return 0
}

# essentials
${CMD_INSTALL} apt-transport-https
${CMD_INSTALL} ca-certificates
${CMD_INSTALL} software-properties-common
${CMD_INSTALL} screenfetch
${CMD_INSTALL} unzip
${CMD_INSTALL} git
${CMD_INSTALL} curl
${CMD_INSTALL} wget
${CMD_INSTALL} jq
${CMD_INSTALL} dos2unix

## build/development dependencies
if [ -d /usr/local/src ] ; then sudo rm -rf /usr/local/src ; fi
sudo mkdir -p /usr/local/src && sudo chown ${USER} /usr/local/src && chmod 744 /usr/local/src 
${CMD_INSTALL} build-essential pkg-config intltool libtool autoconf
## sqllite
${CMD_INSTALL} sqlite3 libsqlite3-dev
## create database test.db
# sqlite test.db

# Handle SSH Agent - at logon
sudo sh -c 'echo "# ssh-agent.sh - start ssh agent" > /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# The ssh-agent is a helper program that keeps track of user identity keys and their passphrases. " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# The agent can then use the keys to log into other servers without having the user type in a " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# password or passphrase again. This implements a form of single sign-on (SSO)." >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "env=~/.ssh/agent.env" >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "if ! [ -f \$env ] ; then " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "   return 0 " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "fi ">> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "agent_load_env () { test -f \"\$env\" && . \"\$env\" >| /dev/null ; }" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "agent_start () { ">>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "    (umask 077; ssh-agent >| \"\$env\")" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "    . "\$env" >| /dev/null" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "}" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "agent_load_env" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# agent_run_state: 0=agent running w/ key; 1=agent w/o key; 2=agent not running" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "agent_run_state=\$(ssh-add -l >| /dev/null 2>&1; echo \$?)" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "if [ ! \"\$SSH_AUTH_SOCK\" ] || [ \$agent_run_state = 2 ]; then" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "        agent_start" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "        ssh-add" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "elif [ \"\$SSH_AUTH_SOCK\" ] && [ \$agent_run_state = 1 ]; then ">>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "        ssh-add" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "fi" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "unset env" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# ssh setup" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "# # from host ssh-copy-id pi@raspberrypi.local - to enable promptless logon" >>/etc/profile.d/ssh-agent.sh'

## get some decent stuff working for all bash users
sudo sh -c 'echo "# Ensure \$LINES and \$COLUMNS always get updated."   >  /etc/profile.d/bash.sh'
sudo sh -c 'echo shopt -s checkwinsize                                 >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Limit number of lines and entries in the history." >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTFILESIZE=50000                             >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTSIZE=50000                                 >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Add a timestamp to each command."                  >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTTIMEFORMAT=\"%Y/%m/%d %H:%M:%S:\"          >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Duplicate lines and lines starting with a space are not put into the history." >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTCONTROL=ignoreboth                         >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Append to the history file, dont overwrite it."    >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo shopt -s histappend                                   >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Enable bash completion."                           >>  /etc/profile.d/bash.sh'
sudo sh -c "echo [ -f /etc/bash_completion ] \&\& . /etc/bash_completion >>  /etc/profile.d/bash.sh"

sudo sh -c 'echo "# Improve output of less for binary files."          >> /etc/profile.d/bash.sh'
sudo sh -c 'echo [ -x /usr/bin/lesspipe ] \&\& eval "$(SHELL=/bin/sh lesspipe)"   >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Alias to provide distribution name"                 >> /etc/profile.d/bash.sh'
sudo sh -c 'alias distribution=\$(. /etc/os-release;echo \$ID\$VERSION_ID) >> /etc/profile.d/bash.sh'

## Install Node through Node Version Manager (nvm)
## https://github.com/nvm-sh/nvm
wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.3/install.sh | bash
## The script clones the nvm repository to ~/.nvm, and attempts to add the source lines from the snippet below
## to the correct profile file (~/.bash_profile, ~/.zshrc, ~/.profile, or ~/.bashrc).
source ~/.bashrc
command -v nvm
nvm --version
## install late node
# nvm install 13.10.1 # Specific minor release
# nvm install 14 # Specify major release only
## install latest
nvm install node
## install Active Long Term Support (LTS)
# nvm install --lts
nvm ls
if [ -f /etc/profile.d/nodejs.sh ] ; then sudo rm -f /etc/profile.d/nodejs.sh ; fi
if (which node) ; then 
    sudo sh -c 'echo if \(which node\) \; then           >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo   echo \"Node JS \(node\) found -  use nvm to manage!\"  >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo fi >>  /etc/profile.d/nodejs.sh'
fi
    
# Install Terraform.
# curl "https://releases.hashicorp.com/terraform/0.12.26/terraform_0.12.26_linux_amd64.zip" -o "terraform.zip" \
#  && unzip -qo terraform.zip && chmod +x terraform \
#  && sudo mv terraform ~/.local/bin && rm terraform.zip

sudo ldconfig

## Install AWS CLI (global)
#cd ~
#curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
#unzip -qo awscliv2.zip
#sudo ~/./aws/install
#rm awscliv2.zip

## Install Azure CLI (global) - much better to run inside a docker container (installer/updates are very buggy)
#curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash && az version
## automatic upgrade enabled
#az config set auto-upgrade.enable=yes --only-show-errors  # automatic upgrade enabled
# dont prompt
##az config set auto-upgrade.prompt=no  --only-show-errors # dont prompt
##az version
##if [ -f  /etc/profile.d/azurecli.sh  ] ; then sudo rm -f /etc/profile.d/azurecli.sh ; fi
##sudo sh -c 'echo echo \"Azure CLI \(az\) found!\"     >>  /etc/profile.d/azurecli.sh'
##sudo sh -c 'echo # az account show --output table >>  /etc/profile.d/azurecli.sh'
   
# Install GoLang - current user
wget -q -O - https://git.io/vQhTU | bash
if [ -f  /etc/profile.d/golang.sh  ] ; then sudo rm -f /etc/profile.d/golang.sh ; fi
sudo sh -c 'echo if \(which go\) \; then           >>  /etc/profile.d/golang.sh'
sudo sh -c 'echo echo \"Golang \(go\) found!\"     >>  /etc/profile.d/golang.sh'
sudo sh -c 'echo fi                                >>  /etc/profile.d/golang.sh'

## Install Google Cloud (GCP) CLI
#cd ~ && curl https://sdk.cloud.google.com > install.sh
#chmod +x install.sh
#bash install.sh --disable-prompts
#~/google-cloud-sdk/install.sh --quiet

## need to AAD logon working with
## interactively via browser
# az login

# openssl req -x509 \
#     -newkey rsa:2048 \
#     -keyout key.pem \
#     -out cert.pem \
#     -days 36500 \
#     -nodes \
#     -subj "/C=AU/ST=Victoria/L=Melbourne/O=webstean/OU=IT/CN=webstean.com"

## Oh-My-Posh - Colourful Commandline Prompt
sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
sudo chmod +x /usr/local/bin/oh-my-posh
mkdir ~/.poshthemes
wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O ~/.poshthemes/themes.zip
unzip -qo ~/.poshthemes/themes.zip -d ~/.poshthemes
chmod u+rw ~/.poshthemes/*.omp.*
rm ~/.poshthemes/themes.zip
# oh-my-posh font install "Meslo LGM NF"
# oh-my-posh font install Meslo
oh-my-posh get shell
# eval "$(oh-my-posh init bash)"
eval "$(oh-my-posh init `oh-my-posh get shell`)"
oh-my-posh notice
## themes can be found in ~/.poshthemes/ for example: dracula.omp.json
## oh-my-posh init `oh-my-posh get shell` -c dracula.omp.json
## Eg:-
## eval "$(oh-my-posh init `oh-my-posh get shell` -c dracula.omp.json`)"

## Generate
## https://textkool.com/en/ascii-art-generator
## note: any ` needs to be escaped with \
if [ -f  ~/.logo  ] ; then rm -f ~/.logo ; fi
cat >> ~/.logo <<EOF
                     _                   
     /\             | |                  
    /  \   _ __   __| |_ __ _____      __
   / /\ \ | '_ \ / _\` | '__/ _ \ \ /\ / /
  / ____ \| | | | (_| | | |  __/\ V  V / 
 /_/    \_\_| |_|\__,_|_|  \___| \_/\_/  
                                         
 Development Environment
 
EOF
if [ -f  /etc/profile.d/zlogo.sh  ] ; then sudo rm -f /etc/profile.d/zlogo.sh ; fi
sudo sh -c 'echo if [ -f  \~/.logo ] \; then >>  /etc/profile.d/zlogo.sh'
sudo sh -c 'echo    cat \~/.logo >>  /etc/profile.d/zlogo.sh'
sudo sh -c 'echo fi >>  /etc/profile.d/zlogo.sh'

${CMD_CLEAN}

touch $HOME/.hushlogin

export CMD_INSTALL=
export CMD_UPGRADE=
export CMD_UPDATE=
export CMD_CLEAN=

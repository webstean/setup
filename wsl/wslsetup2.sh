
#!/usr/bin/bash

## assume: we have network connectivity.

## Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable
set -x

## start from scratch - normally no!
#if [   -d /opt ] ; then sudo rm -rf /opt ; fi 
#if [ ! -d /opt ] ; then sudo mkdir -p /opt ; sudo chmod 755 /opt ; fi 

## get everything upto date
${CMD_UPDATE}
${CMD_UPGRADE}

## Set Timezone - includes keeping the machine to the right time but not sure how?
## WSL Error: System has not been booted with systemd as init system (PID 1). Can't operate.
##          : unless you edit /etc/wsl.conf to enable systemd
sudo timedatectl set-timezone Australia/Melbourne
timedatectl status 

source ~/.bashrc

## Add Microsoft Repos and Applications
if [ -f /usr/bin/apt && ! grep packages.microsoft.com /etc/apt/sources.list ] ; then
    ## make sure prereqs are installs
    ${CMD_INSTALL} apt-transport-https ca-certificates curl software-properties-common
    
    ## Import the public repository GPG keys (depreciated)
    ## Note: Instead of using this command a keyring should be placed directly in the 
    ## /etc/apt/trusted.gpg.d/ directory with a descriptive name and either "gpg" or "asc" 
    ## as file extension.
    curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -

    ## Register the Microsoft Ubuntu repository
    repo=https://packages.microsoft.com/$(lsb_release -s -i)/$(lsb_release -sr)/prod
    ## convert to lowercase
    repo=${repo,,}
    echo $repo
    sudo apt-add-repository --yes $repo
    
    ## Update the list of products
    ${CMD_UPDATE}
    
    ## Install WSL Utilities
    sudo add-apt-repository ppa:wslutilities/wslu
    sudo apt update
    sudo apt install wslu
    
    ## Skip EULA prompt
    echo 'debconf debconf/frontend select Noninteractive' | sudo debconf-set-selections
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
    echo msodbcsql18 msodbcsql/ACCEPT_EULA boolean true | sudo debconf-set-selections
    echo mssql-tools mssql-tools/ACCEPT_EULA boolean true | sudo debconf-set-selections
    echo "servicefabric servicefabric/accepted-eula-ga select true" | sudo debconf-set-selections
    echo "servicefabricsdkcommon servicefabricsdkcommon/accepted-eula-ga select true" | sudo debconf-set-selections
    export ACCEPT_EULA=y

    ## Install Microsoft tools
    ${CMD_INSTALL} ttf-mscorefonts-installer
    ${CMD_INSTALL} azure-functions-core-tools
    ${CMD_INSTALL} mssql-tools 
    ${CMD_INSTALL} sqlcmd
    ${CMD_INSTALL} powershell
    
    ## Powershell
    if [ -f /etc/profile.d/microsoft-powershell.sh ] ; then sudo rm -f /etc/profile.d/microsoft-powershell.sh ; fi
    if (which pwsh) ; then 
        sudo sh -c 'echo   echo \"Powershell \(pwsh\) found!\"     >>  /etc/profile.d/microsoft-powershell.sh'
    fi
    
    ## Install Java from Microsoft -  only if java not installed already
    if (! which java) ; then
        ${CMD_INSTALL} msopenjdk-17
        ${CMD_INSTALL} default-jre
    fi
fi

## Azure IOTEdge
if (1) ; then
    sudo apt-get -y update;   sudo apt-get -y install moby-engine  
    if [ -f /etc/docker/daemon.json ] ; then
        sudo sh -c "{                                >  ~/config-docker-for-iotedge.sh"
        sudo sh -c "    \"log-driver\": \"local\"    >> ~/config-docker-for-iotedge.sh"
        sudo sh -c "}                                >> ~/config-docker-for-iotedge.sh"
    fi
    curl -ssl https://raw.githubusercontent.com/moby/moby/master/contrib/check-config.sh -o check-config.sh
    chmod +x check-config.sh
    ## ./check-config.sh
    sudo apt-get -y install aziot-edge defender-iot-micro-agent-edge
    ## sudo iotedge config mp --connection-string 'PASTE_DEVICE_CONNECTION_STRING_HERE'
    ## sudo iotedge config apply -c '/etc/aziot/config.toml'
    sudo iotedge system status
    sudo iotedge system logs
    sudo iotedge check
    sudo iotedge check --verbose
    sudo iotedge list
fi

## Check if WSL2, - XWindows is supported (natively) - so install some GUI stuff
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if ! [ -x /usr/bin/sqlitebrowser ] ; then
        ${CMD_INSTALL} xscreensaver
        ${CMD_INSTALL} x11-apps
        echo $DISPLAY
        ## Start xeyes to show X11 working - hopefully (now just works with WSL 2 plus GUI)
        ## xeyes &
        ## Install browser for sqlite
        ${CMD_INSTALL} sqlitebrowser
        # sqlitebrowser &
    fi
    # export WINHOME=$(wslpath "$(wslvar USERPROFILE)")
fi

## install and config sysstat
$CMD_INSTALL sysstat
sudo sh -c 'echo ENABLED="true" >  /etc/default/sysstat'
sudo systemctl stop sysstat --no-pager
sudo systemctl enable sysstat --no-pager
sudo systemctl start sysstat --no-pager
sudo systemctl status sysstat --no-pager
# sar -u

## sync the time automatioally
sudo systemctl enable systemd-timesyncd.service
sudo systemctl status systemd-timesyncd.service

## Docker - requires systemd
## Only install docker if it doesn't already exist
if [ ! -x "$(command -v docker)" ] ; then

    ## get rid of anything old
    sudo apt-get remove docker docker-engine docker.io containerd runc
    
    ## install
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo chmod 755 get-docker.sh
    sudo sh get-docker.sh
    
    ## verify
    sudo docker run hello-world
    
    ## run Azure CLI as a container
    #sudo git clone https://github.com/gtrifonov/raspberry-pi-alpine-azure-cli.git
    #sudo docker build . -t azure-cli
    #sudo docker run -d -it --rm --name azure-cli azure-cli

    ## allow user to run docker commands
    if (grep docker /etc/group) ; then 
        sudo -E usermod -aG docker $USER
    fi
    if (grep wheel /etc/group) ; then 
        sudo -E usermod -aG wheel $USER
    fi
    
    ## set controlable via Docker Desktop
    sudo sh -c 'echo "export DOCKER_HOST=tcp://localhost:2375" > /etc/profile.d/docker.sh'
fi

## install WASM
curl https://get.wasmer.io -sSfL | sh
## example
## wasmer run python/python -- -c "for x in range(999): print(f'{x} square: {x*x}')"

## Ensure git is install and then configure it 
${CMD_INSTALL} git
if [ -x /usr/bin/git ]; then
    git config --global color.ui true
    git config --global user.name "Andrew Webster"
    if [ ! ${UPN} == '' ]; then 
        git config --global user.email "${UPN}"
    fi
    # cached credentials for 2 hours
    git config --global credential.helper 'cache --timeout 7200'
    git config --global advice.detachedHead false
    git config --list
fi

## Install Oracle Database Instant Client via permanent OTN link
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
 
    ## Q: How do I ensure that my Oracle Net files like "tnsnames.ora" and "sqlnet.ora" are being used in Instant Client?
    ## A: Files like "tnsnames.ora", "sqlnet.ora" and "oraaccess.xml" will be located by Instant Client by setting the TNS_ADMIN environment variable
    ## or registry entry to the directory containing the files. Use the full directory path; do not include a file name. 
    ## Alternatively create a subdirectory "network/admin" under the Instant Client directory for the Oracle Net files.
    ## This is the default location and so no TNS_ADMIN variable is required.
    if [ ! -d ${LD_LIBRARY_PATH}/network/admin ] ; then mkdir -p ${LD_LIBRARY_PATH}/network/admin ; fi
    
    ## TSNNAME.ORA example
    # 
    # ORAHOST1 =
    #   (DESCRIPTION =
    #     (ADDRESS_LIST =
    #       (ADDRESS = (PROTOCOL = TCP)(HOST = orahost1.local.ora)(PORT = 1521))
    # )
    # (CONNECT_DATA =
    #  (SERVICE_NAME = orahost1.local.ora)
    # )
     
    # copy tnsnames inplace if found
    if [[ -f "${OneDriveCommercial}/oracle/tnsnames.ora" ]] ; then
        echo "Found oracle tnsnames.ora, putting it inplace..."
        sudo cp   "${OneDriveCommercial}/oracle/tnsnames.ora" "${LD_LIBRARY_PATH}/network/admin"
        sudo chmod 444 ${LD_LIBRARY_PATH}/network/admin/tnsnames.ora
    fi
    
    ## use Oraclw SQL statement to create CSV files you can export and import into some else (like sqllite)
    ## https://www.dba-oracle.com/t_export%20table_to_csv.htm
    # set heading off
    # spool myfile.csv
    # select col1|','||col2 from my_tables;
    # set colsep ','
    # select * from my_table;
    # spool off;
    
    return 0
}

# Install Oracle SQL Developer
oraclesqldeveloperinstall() {
    ## https://www.oracle.com/database/sqldeveloper/technologies/download/#license-lightbox
    echo 
}

## only supported on x86 64bit
MACHINE_TYPE=`uname -m`
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
    ## don't bother if already installed
    set -- /opt/oracle/instantclient*
    if [ ! -d $1 ] ; then
         echo
         oracleinstantclientinstall
    fi
fi

# Join Active Directory 
joinactivedirectory() {
    # Environment variables
    # USERDNSDOMAIN : DNS Name of Active Directory domain
    # JOINACC       : Name of Join Account
    echo "Trying to join AD Domain ${USERDNSDOMAIN} with the account: ${JOINACC}" 
    if [[ -z "${USERDNSDOMAIN}" ]]; then 
        echo "Error: Variable: USERNDNSDOMAIN is not defined!"
        return 1
    fi
    if [[ "${USERDNSDOMAIN}" != *.* ]]; then
        echo "Error: Variable: USERNDNSDOMAIN looks invalid - not a FQDN name!"
        return 1
    fi
    if [[ -z "${JOINACC}" ]]; then 
        echo "Error: Variable: JOINACC is not defined!"
        return 1
    fi
    
    # Define full account name variable
    FULLJOINACC = '${JOINACC}@${USERDNSDOMAIN}'
        
    ## Dependencies for AD Join
    echo ${CMD_INSTALL} realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools
    echo ${CMD_INSTALL} cifs-utils
    ## Info on Domain
    echo "Join AD domain: ${USERDNSDOMAIN}"
    if (sudo realm discover ${USERDNSDOMAIN}) ; then
        # Generate Kerberos ticket
        echo sudo kinit ${FULLJOINACC}
        # Join the Domain
        echo sudo realm join --verbose ${USERDNSDOMAIN}-U '${FULLJOINACC}'
    else
        return 1
    fi
    return 0
}

## Mount SMB Azure File Share on Linux - expects to already be logged in
mountazurefiles() {
    ## https://learn.microsoft.com/en-us/azure/storage/files/storage-how-to-use-files-linux?tabs=Ubuntu%2Csmb311
    ${CMD_INSTALL} cifs-utils
    ${CMD_INSTALL} autofs
    
    az login
    if [ -z ${RESOURCE_GROUP_NAME} ] ; then
        return 1;
    fi
    if [ -z ${STORAGE_ACCOUNT_NAME} ] ; then
        return 1;
    fi
    
    ## This command assumes you have logged in with az login
    HTTP_ENDPOINT=$(az storage account show \
        --resource-group $RESOURCE_GROUP_NAME \
        --name $STORAGE_ACCOUNT_NAME \
        --query "primaryEndpoints.file" --output tsv | tr -d '"')
    SMBPATH=$(echo $HTTP_ENDPOINT | cut -c7-${#HTTP_ENDPOINT})
    FILE_HOST=$(echo $-- | tr -d "/")

    nc -zvw3 $FILE_HOST 445
        
    return 0
}

## essentials
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
${CMD_INSTALL} gnupg2
${CMD_INSTALL} python3
${CMD_INSTALL} python3-pip

## build/development dependencies
if [ -d /usr/local/src ] ; then sudo rm -rf /usr/local/src ; fi
sudo mkdir -p /usr/local/src && sudo chown ${USER} /usr/local/src && chmod 744 /usr/local/src 
${CMD_INSTALL} build-essential pkg-config intltool libtool autoconf
## sqllite
${CMD_INSTALL} sqlite3 libsqlite3-dev
## create database test.db
# sqlite test.db
# sqlite3 -batch test.db "create table n (id INTEGER PRIMARY KEY,f TEXT,l TEXT);"

## Handle SSH Agent - at logon
sudo sh -c 'echo "## ssh-agent.sh - start ssh agent" > /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## The ssh-agent is a helper program that keeps track of user identity keys and their passphrases. " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## The agent can then use the keys to log into other servers without having the user type in a " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## password or passphrase again. This implements a form of single sign-on (SSO)." >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo SSH_ENV="$HOME/.ssh/agent-environment" >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo function start_agent { >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo echo "Initialising new SSH agent..." >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo /usr/bin/ssh-agent | sed \'s/^echo/#echo/\' > \"\${SSH_ENV}\" >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo echo succeeded >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo chmod 600 \${SSH_ENV} >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo . \"\${SSH_ENV}\" > /dev/null >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo } >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo ## Source SSH settings, if applicable >> /etc/profile.d/ssh-agent.sh'
## sudo sh -c 'echo if [ -f \"\${SSH_ENV}\" ] ; then >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo . "\${SSH_ENV}\" > /dev/null >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo ps -ef | grep \${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || { >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo start_agent; >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo } >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo else >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo start_agent; >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo fi >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo echo "# from host ssh-copy-id pi@raspberrypi.local - to enable promptless logon" >>/etc/profile.d/ssh-agent.sh'

## Copy to clipboard
# cat ~/.ssh/id_rsa.pub | clip.exe

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
sudo sh -c 'echo "alias distribution=\". /etc/os-release;echo \$ID\$VERSION_ID)\"" >> /etc/profile.d/bash.sh'

## Azure environment
sudo sh -c 'echo "# Setup Azure environment up - if it exists"           >> /etc/profile.d/azure.sh'
sudo sh -c 'echo "if [ -f "\${OneDriveCommercial}/azure/azuresp.sh" ] ; then >> /etc/profile.d/azure.sh'
sudo sh -c 'echo "    source "\${OneDriveCommercial}/azure/azuresp.sh"   >> /etc/profile.d/azure.sh'
sudo sh -c 'echo "fi"                                                    >> /etc/profile.d/azure.sh'

## AWS environment
sudo sh -c 'echo "# Setup AWS environment up - if it exists"             >> /etc/profile.d/aws.sh'
sudo sh -c 'echo "if [ -f "\${OneDriveCommercial}/aws/awssp.sh" ] ; then >> /etc/profile.d/aws.sh'
sudo sh -c 'echo "    source "\${OneDriveCommercial}/aws/awsp.sh"        >> /etc/profile.d/aws.sh'
sudo sh -c 'echo "fi"                                                    >> /etc/profile.d/aws.sh'

## Google Cloud environment
sudo sh -c 'echo "# Setup Google GCP environment up - if it exists"     >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "if [ -f "\${OneDriveCommercial}/gcp/gcpsp.sh" ] ; then >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "    source "\${OneDriveCommercial}/gcp/gcpsp.sh"   >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "fi"                                                   >> /etc/profile.d/gcp.sh'

## shortcut to Windows home directory
sudo sh -c 'echo "export WINHOME=$(wslpath \"$(wslvar USERPROFILE)\")"   > /etc/profile.d/winhome.sh'

## Install Node through Node Version Manager (nvm)
## https://github.com/nvm-sh/nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash
## The script clones the nvm repository to ~/.nvm, and attempts to add the source lines from the snippet below
## to the correct profile file (~/.bash_profile, ~/.zshrc, ~/.profile, or ~/.bashrc).
source ~/.bashrc
if (command -v nvm ) ; then
    nvm --version
    ## install late node
    # nvm install 13.10.1 # Specific minor release
    # nvm install 14 # Specify major release only
    ## install latest
    nvm install node
    ## install Active Long Term Support (LTS)
    # nvm install --lts
    nvm ls
fi
if [ -f /etc/profile.d/nodejs.sh ] ; then sudo rm -f /etc/profile.d/nodejs.sh ; fi
if (which node) ; then 
    sudo sh -c 'echo if \(which node\) \; then           >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo   echo \"Node JS \(node\) found -  use nvm to manage!\"  >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo fi >>  /etc/profile.d/nodejs.sh'
fi
    
## Install Terraform.
# curl "https://releases.hashicorp.com/terraform/0.12.26/terraform_0.12.26_linux_amd64.zip" -o "terraform.zip" \
#  && unzip -qo terraform.zip && chmod +x terraform \
#  && sudo mv terraform ~/.local/bin && rm terraform.zip

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

## Install GoLang - current user
if ! [ -x ~.go/bin/go ] ; then
    wget -q -O - https://git.io/vQhTU | bash
    if [ -f  /etc/profile.d/golang.sh  ] ; then sudo rm -f /etc/profile.d/golang.sh ; fi
    sudo sh -c 'echo if ! [ -x \~.go/bin/go ] ; then   >>  /etc/profile.d/golang.sh'
    sudo sh -c 'echo echo \"Golang \(go\) found!\"     >>  /etc/profile.d/golang.sh'
    sudo sh -c 'echo fi                                >>  /etc/profile.d/golang.sh'
fi

## Install Google Cloud (GCP) CLI
#cd ~ && curl https://sdk.cloud.google.com > install.sh
#chmod +x install.sh
#bash install.sh --disable-prompts
#~/google-cloud-sdk/install.sh --quiet

# openssl req -x509 \
#     -newkey rsa:2048 \
#     -keyout key.pem \
#     -out cert.pem \
#     -days 36500 \
#     -nodes \
#     -subj "/C=AU/ST=Victoria/L=Melbourne/O=webstean/OU=IT/CN=${UPN}"
# copy to Windows clipboard
# cat ~/.ssh/id_rsa.pub | clip.exe

## Oh-My-Posh - Colourful Commandline Prompt
sudo wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/posh-linux-amd64 -O /usr/local/bin/oh-my-posh
sudo chmod +x /usr/local/bin/oh-my-posh
if [ ! -d ~/.poshthemes ] ; then
    mkdir ~/.poshthemes
    wget https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip -O ~/.poshthemes/themes.zip
    unzip -qo ~/.poshthemes/themes.zip -d ~/.poshthemes
    chmod u+rw ~/.poshthemes/*.omp.*
    rm ~/.poshthemes/themes.zip
fi
set -x
oh-my-posh get shell
# eval "$(oh-my-posh init bash)"
eval "$(oh-my-posh init `oh-my-posh get shell`)"
oh-my-posh notice
## themes can be found in ~/.poshthemes/ for example: dracula.omp.json
## oh-my-posh init `oh-my-posh get shell` -c  ~/.poshthemes/dracula.omp.json
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

echo ${CMD_CLEAN}

touch $HOME/.hushlogin

 ## if java is installed, install maven build system
 ## Maven is a build automation tool used primarily for Java projects
 if [ -x "$(command -v java)" ] ; then
    ${CMD_INSTALL} maven
 fi

export CMD_INSTALL=
export CMD_UPGRADE=
export CMD_UPDATE=
export CMD_CLEAN=

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
sudo apt-get update -y
sudo apt-get upgrade -y

## Check if WSL2, - XWindows is supported (natively) - so install some GUI stuff
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if ! [ -x /usr/bin/sqlitebrowser ] ; then
        apt-get install -y x11-apps
        echo $DISPLAY
        ## Start xeyes to show X11 working - hopefully (now just works with WSL 2 plus GUI)
        xeyes &
    fi
    ## WSL Audio (via Pulse Audio)
    ## https://github.com/mikeroyal/PipeWire-Guide
    #sudo apt-get install -y pulseaudio pulseaudio-utils mpv
    sudo apt-get install -y pipewire pipewire-audio-client-libraries pipewire-pulse pipewire-alsa wireplumber mpv

    sudo mkdir -p /etc/pulse && sudo tee /etc/pulse/client-rt.conf >/dev/null <<'EOF'
realtime-scheduling = yes
realtime-priority = 5
nice-level = -11
EOF
    if ( !(LANG=C pactl info >/dev/null 2>&1 || echo "⚠ Pulse/PipeWire not running")) ; then
        LANG=C pactl info | grep "Server Name"
        LANG=C pactl info | grep "Server String"
        wget --https-only --no-verbose -O /tmp/jump.ogg https://commondatastorage.googleapis.com/codeskulptor-assets/jump.ogg
        mpv --no-video /tmp/jump.ogg
    fi
fi
    
## Set Timezone - includes keeping the machine to the right time but not sure how?
## WSL Error: System has not been booted with systemd as init system (PID 1). Can't operate.
##          : unless you edit /etc/wsl.conf to enable systemd
sudo timedatectl set-timezone Australia/Melbourne
timedatectl --no-pager status 

source ~/.bashrc

## Add Microsoft Repos and Applications
## https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux?pivots=apt
if [ ! -f /etc/apt/keyrings/microsoft.gpg ] ; then
    ## make sure prereqs are installs
    ${CMD_INSTALL} apt-transport-https ca-certificates curl software-properties-common
    
    ## Create the keyring directory if not present
    sudo install -m 0755 -d /etc/apt/keyrings

    ## Download and convert Microsoft’s GPG key
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
    sudo install -o root -g root -m 644 microsoft.gpg /usr/share/keyrings
    rm microsoft.gpg
    gpg --show-keys /usr/share/keyrings/microsoft.gpg

    ## add a Microsoft repository 
    sudo sh -c 'echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" >> /etc/apt/sources.list.d/microsoft-ubuntu-$(lsb_release -cs)-prod.list'
    sudo apt update -y

    ## Microsoft Identity Broker (BIG package - around 350MB )
    #sudo apt install -y libx11-6 libc++1 libc++abi1 libsecret-1-0 libwebkit2gtk-4.0-37
    #sudo dnf install -y libx11-6 libc++1 libc++abi1 libsecret-1-0 libwebkit2gtk-4.0-37
    #sudo apt install -y microsoft-identity-broker
    #sudo dnf install -y microsoft-identity-broker
    
    ## Install WSL Utilities
    ## https://wslu.wedotstud.io/wslu/
    sudo apt-get install -y wslu
    #wslsys

    ## Microsoft Defender for Endpoint
    #sudo apt-get install -y mdatp
    #mdatp --version
    #sudo mdatp health
    #sudo mdatp health --field real_time_protection_enabled

    ## Install Microsoft fonts
    echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
    export ACCEPT_EULA=Y && sudo apt-get install -y ttf-mscorefonts-installer

    ## Install Azure Function Toolkit
    sudo apt-get install -y azure-functions-core-tools

    ## Install Microsoft SQL Server Command-Line Tools
    export ACCEPT_EULA=Y && sudo apt-get install -y mssql-tools18

    ## Install Powershell
    sudo apt-get install -y powershell
    if [ -f /etc/profile.d/microsoft-powershell.sh ] ; then sudo rm -f /etc/profile.d/microsoft-powershell.sh ; fi
    if (which -s pwsh) ; then 
        sudo sh -c 'echo   if \(which -s pwsh\) \; then > /etc/profile.d/microsoft-powershell.sh'
        sudo sh -c 'echo   echo \"PowerShell \(pwsh\) found!\"     >>  /etc/profile.d/microsoft-powershell.sh'
        sudo sh -c 'echo   fi >> /etc/profile.d/microsoft-powershell.sh'
    fi
    
    ## Install Java from Microsoft - but only if java not installed already
    if (! which java) ; then
        sudo apt-get install -y msopenjdk-17
        sudo apt-get install -y default-jre
        ## Adding a new alternative for "java".
        #sudo update-alternatives --install /usr/bin/java java /media/mydisk/jdk/bin/java 1
        ## Setting the new alternative as default for "java".
        #sudo update-alternatives --config java
    fi
fi

sudo apt install -y podman-remote
podman-remote system connection add winpodman ssh://user@localhost:62429/run/user/1000/podman/podman.sock
podman-remote system connection default winpodman
## Test
podman --connection winpodman ps

add_podman_win_ssh() {
  local alias="winpodman"
  local host="localhost"
  local port="2222"
  local user="core"
  local key="$HOME/.ssh/podman-machine-default"
  local cfg="$HOME/.ssh/config"

  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"

  # Remove existing block
  sed -i "/^Host $alias$/,/^$/d" "$cfg" 2>/dev/null || true

  cat >>"$cfg" <<EOF

Host $alias
    HostName $host
    Port $port
    User $user
    IdentityFile $key
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

  chmod 600 "$cfg"
  echo "SSH config entry '$alias' added/updated"
}

podman-remote system connection add myuser --identity ~/.ssh/id_ed25519 ssh://myuser@192.168.122.1/run/user/1000/podman/podman.sock
podman-remote system connection list
podman-remote info
podman-remote run --rm quay.io/podman/hello

#sudo sh -c "echo 'export WIN_PODMAN_PIPE=//./pipe/podman-machine-default' > /etc/profile.d/podman.sh"
#sudo sh -c "echo 'export CONTAINER_HOST=//./pipe/podman-machine-default' > /etc/profile.d/podman.sh"

## Azure IOTEdge
setup-iotedge() {
    if (true) ; then
        sudo apt-get -y update; sudo apt-get -y install moby-engine  
        if [ -f /etc/docker/daemon.json ] ; then
            sudo sh -c "{                                >  ~/config-docker-for-iotedge.sh"
            sudo sh -c "    \"log-driver\": \"local\"    >> ~/config-docker-for-iotedge.sh"
            sudo sh -c "}                                >> ~/config-docker-for-iotedge.sh"
        fi
        curl -ssl https://raw.githubusercontent.com/moby/moby/master/contrib/check-config.sh -o check-config.sh
        chmod +x check-config.sh
        ./check-config.sh

        #sudo apt-get -y install aziot-edge defender-iot-micro-agent-edge
        #sudo apt-get -y install aziot-edge defender-iot-micro-agent-edge

        sudo apt-get -y install aziot-edge aziot-identity-service
        ## sudo iotedge config mp --connection-string 'PASTE_DEVICE_CONNECTION_STRING_HERE'
        ## sudo iotedge config apply -c '/etc/aziot/config.toml'
        sudo iotedge system status
        sudo iotedge system logs
        sudo iotedge check
        sudo iotedge check --verbose
        sudo iotedge list
    fi
}

## install and config sysstat
apt-get install -y sysstat
sudo sh -c 'echo ENABLED="true" >  /etc/default/sysstat'
sudo systemctl --no-pager stop sysstat 
sudo systemctl --no-pager enable sysstat 
sudo systemctl --no-pager start sysstat 
sudo systemctl --no-pager status sysstat 
# sar -u

## sync the time automatically
sudo systemctl --no-pager enable systemd-timesyncd.service
sudo systemctl --no-pager status systemd-timesyncd.service

## install WASM
curl https://get.wasmer.io -sSfL | sh
## example
## source ~./bashrc
## wasmer run python/python -- -c "for x in range(999): print(f'{x} square: {x*x}')"

## Ensure git is install and then configure it 
${CMD_INSTALL} git
if [ -x /usr/bin/git ]; then
    git config --global color.ui true
    git config --global --add safe.directory '*'
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
    sudo apt-get install -y libaio1
    sudo apt-get install -y libaio1t64
    #apt-get install -y libaio2 
    apt-get install -y unzip
    if [ ! -f /usr/lib/x86_64-linux-gnu/libaio.so.1 ] ; then
        sudo ln -s /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1
    fi
    sudo ldconfig
    # Permanent Link (latest version) - Instant Client - Basic (x86 64 bit) - you need this for anything else to work
    # Note: there is no Instant Client for the ARM processor, Intel/AMD x86 only
    tmpdir=$(mktemp -d)
    sudo wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-basic-linuxx64.zip -nc --directory-prefix=${tmpdir}
    sudo wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-sqlplus-linuxx64.zip -nc --directory-prefix=${tmpdir}
    sudo wget https://download.oracle.com/otn_software/linux/instantclient/instantclient-tools-linuxx64.zip -nc --directory-prefix=${tmpdir}

    if [   -d /opt/oracle ] ; then sudo rm -rf /opt/oracle ; fi 
    if [ ! -d /opt/oracle ] ; then sudo mkdir -p /opt/oracle ; sudo chmod 755 /opt/oracle ; fi 
    echo "Extracting Oracle Instant client..."
    sudo unzip -qo ${tmpdir}/instantclient-basic*.zip -d /opt/oracle
    sudo unzip -qo ${tmpdir}/instantclient-sqlplus*.zip -d /opt/oracle
    sudo unzip -qo ${tmpdir}/instantclient-tools*.zip -d /opt/oracle

    # rm instantclient-basic*.zip
    set -- /opt/oracle/instantclient*
    export LD_LIBRARY_PATH=$1
    if [ -f /etc/profile.d/oracle-instantclient.sh ] ; then
        sudo rm /etc/profile.d/oracle-instantclient.sh 
    fi
    ### Environment variables for Oracle Instance Client
    ### https://docs.oracle.com/en/database/oracle/oracle-database/21/lacli/environment-variables-instant-client.html
    sudo sh -c "echo ##Oracle Instant Client Setup     >  /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo oracle-instantclient\(\) {        >  /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo   export LD_LIBRARY_PATH=$1       >> /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo   export PATH=$1:'\$PATH'         >> /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo }                                 >> /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo if [ -d /opt/oracle/instantclient\* ] \; then >> /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c 'echo   oracle-instantclient            >>  /etc/profile.d/oracle-instantclient.sh'
    sudo sh -c 'echo   echo \"Oracle Database Instant Client \(sqlplus\) found!\"     >>  /etc/profile.d/oracle-instantclient.sh'
    sudo sh -c "echo fi                                >>  /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo # example: sqlplus scott/tiger@//myhost.example.com:1521/myservice >>  /etc/profile.d/oracle-instantclient.sh"
    sudo sh -c "echo # use lld sqlplus to help resolve any dependencies >>  /etc/profile.d/oracle-instantclient.sh"
 
    ## Q: How do I ensure that my Oracle Net files like "tnsnames.ora" and "sqlnet.ora" are being used in Instant Client?
    ## A: Files like "tnsnames.ora", "sqlnet.ora" and "oraaccess.xml" will be located by Instant Client by setting the TNS_ADMIN environment variable
    ## or registry entry to the directory containing the files.
    ## Use the full directory path; do not include a file name. 
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
    if [[ -f "${OneDriveCommercial}/oracle/sqlnet.ora" ]] ; then
        echo "Found oracle tnsnames.ora, putting it inplace..."
        sudo cp   "${OneDriveCommercial}/oracle/sqlnet.ora" "${LD_LIBRARY_PATH}/network/admin"
        sudo chmod 444 ${LD_LIBRARY_PATH}/network/admin/sqlnet.ora
    fi
    
    ## use Oracle SQL statement to create CSV files you can export and import into some else (like sqllite)
    ## https://www.dba-oracle.com/t_export%20table_to_csv.htm
    # set heading off
    # spool myfile.csv
    # select col1|','||col2 from my_tables;
    # set colsep ','
    # select * from my_table;
    # spool off;
    
    return 0
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
# Install Oracle SQL Developer
oraclesqldeveloperinstall() {
    ## https://www.oracle.com/database/sqldeveloper/technologies/download/#license-lightbox
    echo 
}

# Join Active Directory - not really applicable for WSL (use on actual Linux installs) - but include here for completeness
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
    sudo apt-get install -y realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools
    #apt-get install -y cifs-utils
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

## Mount SMB Azure File Share on Linux - expects to already be logged in with az login
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
    
    ## This command assumes you have logged in with az login (azure cli needs to be installed)
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
apt-get install -y apt-transport-https ca-certificates software-properties-common screenfetch unzip git curl wget jq dos2unix gnupg2 python3 python3-pip

## build/development dependencies
if [ -d /usr/local/src ] ; then sudo rm -rf /usr/local/src ; fi
sudo mkdir -p /usr/local/src && sudo chown ${USER} /usr/local/src && chmod 744 /usr/local/src 
apt-get install -y build-essential pkg-config intltool libtool autoconf

install-sqlite() {
    ## sqllite
    apt-get install -y sqlite3 sqlite3-tools libsqlite3-dev
    if (which sqlite3 ) ; then
        ## Install browser (X11) for sqlite
        apt-get install -y sqlitebrowser
    fi
    if (which sqlitebrowserxxxx ) ; then
        ## Run SQLite browser (X11) for sqlite
        sqlitebrowser &
    fi
    ## Create
    ## create database test.db
    # sqlite test.db
    # sqlite3 -batch test.db "create table n (id INTEGER PRIMARY KEY,f TEXT,l TEXT);"
}
install-sqlite 

## Handle SSH Agent - at logon
sudo sh -c 'echo "## ssh-agent.sh - start ssh agent" > /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## The ssh-agent is a helper program that keeps track of user identity keys and their passphrases. " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## The agent can then use the keys to log into other servers without having the user type in a " >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "## password or passphrase again. This implements a form of single sign-on (SSO)." >> /etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo "" >>/etc/profile.d/ssh-agent.sh'
sudo sh -c 'echo SSH_ENV="$HOME/.ssh/agent-environment" >> /etc/profile.d/ssh-agent.sh'
## MORE HERE.. SOME DAY

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

sudo sh -c 'echo "# Improve output of less for binary files."          >> /etc/profile.d/bash.sh'
sudo sh -c 'echo [ -x /usr/bin/lesspipe ] \&\& eval "\$(SHELL=/bin/sh lesspipe)"   >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Alias to provide distribution name"                 >> /etc/profile.d/bash.sh'
sudo sh -c 'echo "alias distribution=\". /etc/os-release;echo \$ID\$VERSION_ID\"" >> /etc/profile.d/bash.sh'

## Azure environment
sudo sh -c 'echo "# Setup Azure environment up - if it exists"            >  /etc/profile.d/azure.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-azure.sh\" ] ; then " >> /etc/profile.d/azure.sh'
sudo sh -c 'echo "    echo \"Found GCP (Google) environment\""         >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-azure.sh\""   >> /etc/profile.d/azure.sh'
sudo sh -c 'echo "fi"                                                     >> /etc/profile.d/azure.sh'

## AWS environment
sudo sh -c 'echo "# Setup AWS environment up - if it exists"             > /etc/profile.d/aws.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-aws.sh\" ] ; then " >> /etc/profile.d/aws.sh'
sudo sh -c 'echo "    echo \"Found GCP (Google) environment\""         >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-aws.sh\""     >> /etc/profile.d/aws.sh'
sudo sh -c 'echo "fi"                                                    >> /etc/profile.d/aws.sh'

## Google Cloud environment
sudo sh -c 'echo "# Setup Google GCP environment up - if it exists"        >  /etc/profile.d/gcp.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-gcp.sh\" ] ; then " >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "    echo \"Found GCP (Google) environment\""             >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-gcp.sh\""        >> /etc/profile.d/gcp.sh'
sudo sh -c 'echo "fi"                                                      >> /etc/profile.d/gcp.sh'

sudo sh -c 'echo "if ! [ -x \~.go/bin/go ] ; then"                         >  /etc/profile.d/golang.sh'
sudo sh -c 'echo echo    \"Golang \(go\) found!\"                          >> /etc/profile.d/golang.sh'
sudo sh -c 'echo fi                                                        >> /etc/profile.d/golang.sh'

## shortcut to Windows home directory
#sudo sh -c 'echo "export WINHOME=\$(wslpath \"\$(wslvar USERPROFILE)\")"   > /etc/profile.d/winhome.sh'

## Install Node.js + npm
sudo apt install -y nodejs npm

if [ -f /etc/profile.d/nodejs.sh ] ; then sudo rm -f /etc/profile.d/nodejs.sh ; fi
if (which -s node) ; then 
    sudo sh -c 'echo if \(which -s node\) \; then           >  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo   echo \"Node JS \(node\) found -  use nvm/npx to manage!\"  >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo fi >>  /etc/profile.d/nodejs.sh'
fi
    
sudo apt-get install -y golang
#if ! [ -x ~.go/bin/go ] ; then
#    wget -q -O - https://git.io/vQhTU | bash
#fi

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
setup-oh-my-posh() {
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
}
#setup-oh-my-posh

setup-starship() {
    ## Starship - cross shell prompt
    ## https://starship.rs/
   
    sudo apt install -y fonts-firacode
   
    ## wants to be installed posis sh, not bash
    curl -fsSL https://starship.rs/install.sh | /bin/sh -s -- -y

    if [ -f /etc/profile.d/starship.sh ] ; then sudo rm -f /etc/profile.d/starship.sh ; fi
    sudo sh -c 'echo "# Starship Prompt"                       >  /etc/profile.d/starship.sh'
    sudo sh -c 'echo "if (which starship) ; then"              >>  /etc/profile.d/starship.sh'
    sudo sh -c 'echo "    eval \"\$(starship init bash)\" "    >>  /etc/profile.d/starship.sh'
    sudo sh -c 'echo "fi"                                      >>  /etc/profile.d/starship.sh' 

    # Detect shell
    USER_SHELL=$(basename "$SHELL")

    case "$USER_SHELL" in
        bash)
            SHELL_RC="$HOME/.bashrc"
            INIT_CMD='eval "$(starship init bash)"'
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            INIT_CMD='eval "$(starship init zsh)"'
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            INIT_CMD='starship init fish | source'
            ;;
        *)
        ;;
    esac

    ## Append the init command if not already present
    if ! grep -Fq "$INIT_CMD" "$SHELL_RC"; then
        echo "" >> "$SHELL_RC"
        echo "# Initialize Starship prompt" >> "$SHELL_RC"
        echo "$INIT_CMD" >> "$SHELL_RC"
        echo "Added Starship init command to $SHELL_RC"
    else
        echo "Starship init command already present in $SHELL_RC"
    fi
}
setup-starship

## Generate
## https://textkool.com/en/ascii-art-generator
## note: any ` needs to be escaped with \

sudo tee /etc/.logo >/dev/null <<'EOF'
                     _                   
     /\             | |                  
    /  \   _ __   __| |_ __ _____      __
   / /\ \ | '_ \ / _` | '__/ _ \ \ /\ / /
  / ____ \| | | | (_| | | |  __/\ V  V / 
 /_/    \_\_| |_|\__,_|_|  \___| \_/\_/  
                                         
 WSL Development Environment
EOF
sudo sh -c 'echo if [ -f  /etc/.logo ] \; then >  /etc/profile.d/zlogo.sh'
sudo sh -c 'echo    cat /etc/.logo >>  /etc/profile.d/zlogo.sh'
sudo sh -c 'echo fi >>  /etc/profile.d/zlogo.sh'

touch $HOME/.hushlogin

 

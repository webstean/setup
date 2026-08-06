#!/usr/bin/bash

## assume: we have network connectivity.

## Debug this script if in debug mode
[ "$DEBUG" == 'true' ] && set -x
# set +x to disable
set -x

sudo_cmd=""
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && sudo_cmd="sudo"
fi

install_pkg() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: install_pkg <package> [package...]" >&2
        return 1
    fi

    local sudo_cmd=""
    if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 && sudo_cmd="sudo"
    fi

    if command -v apt-get >/dev/null 2>&1; then
        $sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get update -y && \
        $sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            "$@"

    elif command -v dnf >/dev/null 2>&1; then
        $sudo_cmd dnf install -y --setopt=install_weak_deps=False "$@"

    elif command -v tdnf >/dev/null 2>&1; then
        # tdnf (Photon/Azure Linux) has no recommends/weak-deps concept to disable
        $sudo_cmd tdnf install -y "$@"

    elif command -v yum >/dev/null 2>&1; then
        # RHEL8+ yum is a dnf wrapper and understands this; classic yum (RHEL/CentOS 7) doesn't
        if ! $sudo_cmd yum install -y --setopt=install_weak_deps=False "$@" 2>/dev/null; then
            $sudo_cmd yum install -y "$@"
        fi

    elif command -v zypper >/dev/null 2>&1; then
        $sudo_cmd zypper --non-interactive install --no-recommends "$@"

    elif command -v apk >/dev/null 2>&1; then
        # Alpine has no interactive prompts or recommends concept
        $sudo_cmd apk add --no-cache "$@"

    elif command -v pacman >/dev/null 2>&1; then
        # --noconfirm is pacman's non-interactive equivalent
        $sudo_cmd pacman -Sy --noconfirm "$@"

    else
        echo "install_pkg: no supported package manager found" >&2
        return 1
    fi
}
sudo dpkg --configure -a

## start from scratch - normally no!
#if [   -d /opt ] ; then sudo rm -rf /opt ; fi 
#if [ ! -d /opt ] ; then sudo mkdir -p /opt ; sudo chmod 755 /opt ; fi 

## get everything upto date
install_pkg podman-remote
install_pkg systemd systemd-sysv

# Adds Microsoft's official Linux package repository (packages.microsoft.com)
# for the current Ubuntu release, auto-detecting version from /etc/os-release.
#
# Usage:
#   source add-microsoft-repo.sh
#   sudo add_microsoft_repo
#
# Optional: force a specific version (e.g. to work around a brand-new Ubuntu
# release not yet having Microsoft packages published — see the resolute/26.04
# gap this was written around):
#   sudo add_microsoft_repo --version-override 24.04
#
add_microsoft_repo() {
    local version_override=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version-override)
                version_override="$2"
                shift 2
                ;;
            *)
                echo "add_microsoft_repo: unknown argument '$1'" >&2
                return 1
                ;;
        esac
    done

    # NOTE: uses 'return', not 'exit' — this function is meant to be sourced
    # into an interactive shell or another script. 'exit' here would kill the
    # entire calling shell, not just this function.
    if [[ $EUID -ne 0 ]]; then
        echo "add_microsoft_repo: must be run as root (sudo)." >&2
        return 1
    fi

    if [[ ! -f /etc/os-release ]]; then
        echo "add_microsoft_repo: /etc/os-release not found — cannot detect distribution/version." >&2
        return 1
    fi

    # Deliberately not 'source /etc/os-release' directly into the function's
    # scope beyond what's needed — read only the fields we use, into local
    # variables, so this doesn't leak/overwrite unrelated variables in
    # whatever shell this function is sourced into.
    local os_id os_version_id os_pretty_name
    os_id="$(. /etc/os-release && echo "$ID")"
    os_version_id="$(. /etc/os-release && echo "$VERSION_ID")"
    os_pretty_name="$(. /etc/os-release && echo "$PRETTY_NAME")"

    if [[ "$os_id" != "ubuntu" ]]; then
        echo "add_microsoft_repo: Warning — detected distro ID '${os_id:-unknown}', not 'ubuntu'." >&2
        echo "Microsoft's repo paths are per-distro (e.g. /config/debian/... vs /config/ubuntu/...)." >&2
        echo "This function assumes Ubuntu-style paths and may not work correctly on derivatives" >&2
        echo "like Linux Mint, Pop!_OS, etc." >&2
    fi

    local target_version="${version_override:-$os_version_id}"
    if [[ -z "$target_version" ]]; then
        echo "add_microsoft_repo: VERSION_ID not found in /etc/os-release and no --version-override given." >&2
        return 1
    fi

    local config_url="https://packages.microsoft.com/config/${os_id}/${target_version}/packages-microsoft-prod.deb"
    local tmp_deb
    tmp_deb="$(mktemp --suffix=.deb)" || {
        echo "add_microsoft_repo: mktemp failed." >&2
        return 1
    }

    echo "Detected: ${os_pretty_name:-$os_id $os_version_id}"
    if [[ -n "$version_override" ]]; then
        echo "Using version override: ${version_override} (actual OS reports ${os_version_id})"
    fi
    echo "Config package URL: ${config_url}"

    # Local cleanup trap, scoped to this function only — RETURN trap fires
    # when the function returns by any path, without affecting any trap
    # already set in the calling shell.
    trap 'rm -f "$tmp_deb"' RETURN

    local http_status
    http_status="$(curl -s -o /dev/null -w '%{http_code}' "$config_url")"
    if [[ "$http_status" != "200" ]]; then
        echo "add_microsoft_repo: ${config_url} returned HTTP ${http_status}." >&2
        echo "Microsoft may not yet support ${os_id} ${target_version} in its package repo." >&2
        echo "Check https://packages.microsoft.com/config/${os_id}/ for supported versions," >&2
        echo "or retry with --version-override pointing at a supported LTS release." >&2
        return 1
    fi

    echo "Downloading Microsoft signing key + repo config..."
    if ! curl -sSL -o "$tmp_deb" "$config_url"; then
        echo "add_microsoft_repo: download failed." >&2
        return 1
    fi

    echo "Installing..."
    if ! dpkg -i "$tmp_deb"; then
        echo "add_microsoft_repo: dpkg -i failed — retrying after purging any partial prior install..." >&2
        dpkg --purge packages-microsoft-prod 2>/dev/null || true
        if ! dpkg -i "$tmp_deb"; then
            echo "add_microsoft_repo: dpkg -i failed again after purge — giving up." >&2
            return 1
        fi
    fi

    echo "Refreshing package lists..."
    if ! apt-get update; then
        echo "add_microsoft_repo: apt-get update failed after install — repo may be misconfigured." >&2
        return 1
    fi

    echo "Done. Microsoft repository added for ${os_pretty_name:-$os_id $os_version_id}."
    return 0
}
add_microsoft_repo

install_pkg apt-transport-https ca-certificates curl software-properties-common gpg

## Install WSL Utilities
## https://wslu.wedotstud.io/wslu/
install_pkg wslu
#wslsys

## Install Microsoft fonts
echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections
## sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ttf-mscorefonts-installer
install_pkg ttf-mscorefonts-installer
    
## Install Azure Function Toolkit
#install_pkg azure-functions-core-tools

## Install Microsoft SQL Server Command-Line Tools
export ACCEPT_EULA=Y && install_pkg mssql-tools18

## Install Powershell
install_pkg powershell
if [ -f /etc/profile.d/microsoft-powershell.sh ] ; then sudo rm -f /etc/profile.d/microsoft-powershell.sh ; fi
if (which -s pwsh) ; then 
    sudo sh -c 'echo if \(which -s pwsh\) \; then            >  /etc/profile.d/microsoft-powershell.sh'
    sudo sh -c 'echo    echo \"PowerShell \(pwsh\) found!\"  >> /etc/profile.d/microsoft-powershell.sh'
    sudo sh -c 'echo fi                                      >> /etc/profile.d/microsoft-powershell.sh'
fi

## Configure Podman
sudo tee /etc/profile.d/podman-remote.sh > /dev/null <<'EOF'
if [[ -n "$PODMAN_IDENTITY" && -n "$PODMAN_PORT" ]]; then
    if [ ! -d ~/.ssh ]; then
        mkdir -p ~/.ssh && chmod 700 ~/.ssh
    fi
    cp -f $PODMAN_IDENTITY  ~/.ssh/podman-machine-default
    chmod 600 ~/.ssh/podman-machine-default
    podman-remote system connection add --default winpodman --identity ~/.ssh/podman-machine-default "ssh://user@127.0.0.1:${PODMAN_PORT}/run/user/1000/podman/podman.sock"
    echo "podman is set to use Podman Desktop on Windows"
    #podman-remote run quay.io/podman/hello
    #podman system info
    alias podman=podman-remote
    export ASPIRE_CONTAINER_RUNTIME=podman
fi
EOF

sudo tee /etc/profile.d/dotnet-install.sh > /dev/null <<'EOF'
if ! command -v dotnet >/dev/null 2>&1 && [[ ! -x "$HOME/.dotnet/dotnet" ]]; then
    curl -sSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
else {
    echo "dotnet SDK was found!"
fi
alias dotnet='$HOME/.dotnet/dotnet'
#export PATH="$HOME/.dotnet:$PATH"
EOF

sudo tee /etc/profile.d/systemctl-config.sh > /dev/null <<'EOF'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
## systemctl list-units --type=service --all --no-pager
EOF


sudo tee /etc/profile.d/aspire.sh > /dev/null <<'EOF'
if ! command -v aspire >/dev/null 2>&1 && [[ ! -x "$HOME/.aspire/bin/aspire" ]]; then
    curl -sSL https://aspire.dev/install.sh | bash -s -- --skip-path
else {
    echo "aspire CLI was found!"
fi
export PATH="$HOME/.aspire/bin:$PATH"
EOF

## Install Java from Microsoft - but only if java not installed already
#sudo apt-get install -y default-jre
if (! which -s java) ; then
    install_pkg msopenjdk-17
    ## Adding a new alternative for "java".
    #sudo update-alternatives --install /usr/bin/java java /media/mydisk/jdk/bin/java 1
    ## Setting the new alternative as default for "java".
    #sudo update-alternatives --config java
fi

## Podman Remote - using Windows
setup-podman-remote() {
    podman_socket="$(find /mnt/wsl/podman-sockets -name '*.sock' | head -n 1)"
    if [ ! -S "$podman_socket" ]; then
      echo "Podman socket not found (Windows PODMAN not running VM?): $podman_socket" >&2
    else
      install_pkg podman-remote
      # Create/replace connection (idempotent-ish)
      podman-remote system connection remove winpodman >/dev/null 2>&1 || true
      podman-remote system connection add winpodman "unix://$podman_socket"
      podman-remote system connection default winpodman
      # Only do this if user isn't root, add user to uucp (permission for podman to work)
      if [ "$(id -u)" -ne 0 ]; then
        sudo usermod --append --groups 10 "$USER"
      fi
      podman-remote ps
      podman-remote info
      podman-remote run --rm quay.io/podman/hello
    fi
}

## Check if WSL2, - XWindows is supported (natively) - so install some GUI stuff and get sound working
if [[ $(grep -i WSL2 /proc/sys/kernel/osrelease) ]] ; then
    if ! [ -x /usr/bin/sqlitebrowser ] ; then
        sudo apt-get install -y x11-apps
        echo $DISPLAY
        ## Start xeyes to show X11 working - hopefully (now just works with WSL 2 plus GUI)
        xeyes &
    fi
    ## Tell podman to use Windows - Podman Desktop
    setup-podman-remote
    ## WSL Audio (via Pulse Audio) -- THIS IS NOT DONE AUTOMATIC by WSL
    ## https://github.com/mikeroyal/PipeWire-Guide
    sudo apt-get install -y pulseaudio pulseaudio-utils mpv
    #sudo apt-get install -y pipewire pipewire-audio-client-libraries pipewire-pulse pipewire-alsa wireplumber mpv
    #sudo mkdir -p /etc/pulse && sudo tee /etc/pulse/client-rt.conf >/dev/null <<'EOF'
#realtime-scheduling = yes
#realtime-priority = 5
#nice-level = -11
#EOF
    if ( !(LANG=C pactl info >/dev/null 2>&1 || echo "⚠ Pulse/PipeWire not running")) ; then
        LANG=C pactl info | grep "Server Name"
        LANG=C pactl info | grep "Server String"
        wget --https-only --no-verbose -O /tmp/jump.ogg https://commondatastorage.googleapis.com/codeskulptor-assets/jump.ogg
        #mpv --no-video /tmp/jump.ogg
    fi
else
    ## Not running under WSL, so we assume baremetal or full VM
    ## Note, WSL is not supported for Intune enrollment 

    ## Microsoft Defender for Endpoint
    install_pkg mdatp
    mdatp --version
    sudo mdatp health
    sudo mdatp health --field real_time_protection_enabled

    ## Microsoft Identity Broker (BIG package - around 350MB ) - need reboot
    #sudo apt install -y libx11-6 libc++1 libc++abi1 libsecret-1-0 libwebkit2gtk-4.0-37
    #sudo dnf install -y libx11-6 libc++1 libc++abi1 libsecret-1-0 libwebkit2gtk-4.0-37
    install_pkg intune-portal 
    #sudo apt install -y msft-broker msft-edge

    ## need reboot
    install_pkg microsoft-identity-broker
    ## dsreg --help
    dsreg --status
    #sudo apt install -y microsoft-identity-diagnostics ## only avialable on certin Linux distirbutions
    ## and need full desktop
    install_pkg ubuntu-desktop ## then startx
fi
    
## Set Timezone - includes keeping the machine to the right time but not sure how?
## WSL Error: System has not been booted with systemd as init system (PID 1). Can't operate.
##          : unless you edit /etc/wsl.conf to enable systemd
sudo timedatectl set-timezone Australia/Melbourne
timedatectl --no-pager status 

source ~/.bashrc

## install and config sysstat
install_pkg sysstat
sudo sh -c 'echo ENABLED="true" >  /etc/default/sysstat'
sudo systemctl --no-pager stop sysstat 
sudo systemctl --no-pager enable sysstat 
sudo systemctl --no-pager start sysstat 
sudo systemctl --no-pager status sysstat 
# sar -u

## sync the time automatically (NO LONGER required - WSL can keep time finally)
#sudo systemctl --no-pager enable systemd-timesyncd.service
#sudo systemctl --no-pager status systemd-timesyncd.service

## install WASM
curl https://get.wasmer.io -sSfL | sh
## example
## source ~./bashrc
## wasmer run python/python -- -c "for x in range(999): print(f'{x} square: {x*x}')"

## Ensure git is install and then configure it 
install_pkg git
if [ -x /usr/bin/git ]; then
    git config --global color.ui true
    git config --global --add safe.directory '*'
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
    install_pkg libaio1
    install_pkg libaio1t64
    #apt-get install -y libaio2 
    install_pkg unzip
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
    ### Environment variables for Oracle Instance Client
    ### https://docs.oracle.com/en/database/oracle/oracle-database/21/lacli/environment-variables-instant-client.html
    set -- /opt/oracle/instantclient*
    export LD_LIBRARY_PATH=$1
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
## dpkg --print-architecture ## amd64
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

## essentials
install_pkg apt-transport-https ca-certificates software-properties-common screenfetch unzip git curl wget jq dos2unix gnupg2 python3 python3-pip

## build/development dependencies
if [ -d /usr/local/src ] ; then sudo rm -rf /usr/local/src ; fi
sudo mkdir -p /usr/local/src && sudo chown ${USER} /usr/local/src && chmod 744 /usr/local/src 
install_pkg build-essential pkg-config intltool libtool autoconf

install-sqlite() {
    ## sqllite
    install_pkg sqlite3 sqlite3-tools libsqlite3-dev
    if (which -s sqlite3 ) ; then
        ## Install browser (X11) for sqlite
        install_pkg sqlitebrowser
    fi
    if (which -s sqlitebrowserxxxx ) ; then
        ## Run SQLite browser (X11) for sqlite
        sudo sqlitebrowser &
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

sudo sh -c 'echo "# Add a timestamp to each history entry."            >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTTIMEFORMAT=\"%Y/%m/%d %H:%M:%S:\"          >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Duplicate lines and lines starting with a space are not put into the history." >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo export HISTCONTROL=ignoreboth                         >>  /etc/profile.d/bash.sh'

sudo sh -c 'echo "# Append to the history file, dont overwrite it."    >>  /etc/profile.d/bash.sh'
sudo sh -c 'echo shopt -s histappend                                   >>  /etc/profile.d/bash.sh'

sudo tee /etc/profile.d/bash.sh >/dev/null <<'EOF'
# Improve output of less for binary files
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"
# Alias to provide distribution name"
alias distribution='. /etc/os-release; echo "$ID $VERSION_ID"'
EOF

if (which -s podman-remote) ; then
    sudo sh -c 'echo "# Alias for podman"                                >> /etc/profile.d/podman-remote.sh'
    sudo sh -c 'echo "alias podman='podman-remote'"                      >> /etc/profile.d/podman-remote.sh'
    sudo sh -c 'echo "#podman-remote system connection list"             >> /etc/profile.d/podman-remote.sh'
    sudo sh -c 'echo "echo \"Podman (podman-remote) found!\""            >> /etc/profile.d/podman-remote.sh'
fi

## Azure cloud environment
sudo sh -c 'echo "# Setup Azure environment up - if it exists"               >  /etc/profile.d/hyperscale-azure.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-azure.sh\" ] ; then " >> /etc/profile.d/hyperscale-azure.sh'
sudo sh -c 'echo "    echo \"Found Azure (Microsoft) environment\""          >> /etc/profile.d/hyperscale-azure.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-azure.sh\""        >> /etc/profile.d/hyperscale-azure.sh'
sudo sh -c 'echo "fi"                                                        >> /etc/profile.d/hyperscale-azure.sh'

## AWS cloud environment
sudo sh -c 'echo "# Setup AWS environment up - if it exists"               >  /etc/profile.d/hyperscale-aws.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-aws.sh\" ] ; then " >> /etc/profile.d/hyperscale-aws.sh'
sudo sh -c 'echo "    echo \"Found GCP (Google) environment\""             >> /etc/profile.d/hyperscale-aws.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-aws.sh\""        >> /etc/profile.d/hyperscale-aws.sh'
sudo sh -c 'echo "fi"                                                      >> /etc/profile.d/hyperscale-aws.sh'

## Google cloud environment
sudo sh -c 'echo "# Setup Google GCP environment up - if it exists"        >  /etc/profile.d/hyperscale-gcp.sh'
sudo sh -c 'echo "if [ -f \"\${OneDriveCommercial}/env-gcp.sh\" ] ; then " >> /etc/profile.d/hyperscale-gcp.sh'
sudo sh -c 'echo "    echo \"Found GCP (Google) environment\""             >> /etc/profile.d/hyperscale-gcp.sh'
sudo sh -c 'echo "    source \"\${OneDriveCommercial}/env-gcp.sh\""        >> /etc/profile.d/hyperscale-gcp.sh'
sudo sh -c 'echo "fi"                                                      >> /etc/profile.d/hyperscale-gcp.sh'

sudo sh -c 'echo "if ! [ -x \~.go/bin/go ] ; then"                         >  /etc/profile.d/golang.sh'
sudo sh -c 'echo echo    \"Golang \(go\) found!\"                          >> /etc/profile.d/golang.sh'
sudo sh -c 'echo fi                                                        >> /etc/profile.d/golang.sh'

## shortcut to Windows home directory
#sudo sh -c 'echo "export WINHOME=\$(wslpath \"\$(wslvar USERPROFILE)\")"   > /etc/profile.d/winhome.sh'

## Install Node.js + npm
install_pkg nodejs npm
if [ -f /etc/profile.d/nodejs.sh ] ; then sudo rm -f /etc/profile.d/nodejs.sh ; fi
if (which -s node) ; then 
    sudo sh -c 'echo if \(which -s node\) \; then           >  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo   echo \"Node JS \(node\) found -  use nvm/npx to manage!\"  >>  /etc/profile.d/nodejs.sh'
    sudo sh -c 'echo fi >>  /etc/profile.d/nodejs.sh'
fi
   
sudo apt-get install -y golang

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
   
    install_pkg fonts-firacode
   
    ## wants to be installed posis sh, not bash
    curl -fsSL https://starship.rs/install.sh | /bin/sh -s -- -y

    if [ -f /etc/profile.d/starship.sh ] ; then sudo rm -f /etc/profile.d/starship.sh ; fi
    sudo sh -c 'echo "# Starship Prompt"                          >   /etc/profile.d/starship.sh'
    sudo sh -c 'echo "if (which -s starship) ; then"                 >>  /etc/profile.d/starship.sh'
    sudo sh -c 'echo "    echo \"Starship (shell) found!\""       >> /etc/profile.d/bash.sh'
    sudo sh -c 'echo "    eval \"\$(starship init bash)\" "       >>  /etc/profile.d/starship.sh'
    sudo sh -c 'echo "fi"                                         >>  /etc/profile.d/starship.sh' 

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
#setup-starship

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

## systemctl enable --now apt-daily.service
if command -v apt >/dev/null 2>&1; then
  sudo apt autoremove -y
fi

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
    install_pkg realmd sssd krb5-workstation krb5-libs oddjob oddjob-mkhomedir samba-common-tools
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
    install_pkg cifs-utils
    install_pkg autofs
    
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

## Azure IOTEdge
setup-iotedge() {
    if (true) ; then
        install_pkg moby-engine  
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

        install_pkg aziot-edge aziot-identity-service
        ## sudo iotedge config mp --connection-string 'PASTE_DEVICE_CONNECTION_STRING_HERE'
        ## sudo iotedge config apply -c '/etc/aziot/config.toml'
        sudo iotedge system status
        sudo iotedge system logs
        sudo iotedge check
        sudo iotedge check --verbose
        sudo iotedge list
    fi
}
#setup-iotedge
exit 0




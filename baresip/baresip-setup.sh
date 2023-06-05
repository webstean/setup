
# Determine package manager for installing packages
DNF_CMD=$(which dnf) > /dev/null 2>&1
YUM_CMD=$(which yum) > /dev/null 2>&1
APT_CMD=$(which apt-get) > /dev/null 2>&1
APK_CMD=$(which apk) > /dev/null 2>&1
# ${CMD_INSTALL} package
if [[ ! -z $DNF_CMD ]] ; then
    export CMD_INSTALL="sudo dnf install -y"
    export CMD_UPGRADE="sudo dnf upgrade -y"
    export CMD_UPDATE="sudo dnf upgrade"
    export CMD_CLEAN=$"sudo dnf clean all && sudo rm -rf /tmp/* /var/tmp/*"
elif [[ ! -z $YUM_CMD ]] ; then
    export CMD_INSTALL="sudo yum install -y"
    export CMD_UPGRADE="sudo yum upgrade -y"
    export CMD_UPDATE="sudo yum update"
    export CMD_CLEAN=$"sudo yum clean all && sudo rm -rf /tmp/* /var/tmp/*"
elif [[ ! -z $APT_CMD ]] ; then
    export CMD_INSTALL="sudo apt-get install -y"
    export CMD_UPGRADE="sudo apt-get upgrade -y"
    export CMD_UPDATE="sudo apt-get update"
    export CMD_CLEAN=$"sudo apt-get clean && sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"
elif [[ ! -z $APK_CMD ]] ; then
    export CMD_INSTALL="sudo apk add -y"
    export CMD_UPGRADE="sudo apk upgrade -y"
    export CMD_UPDATE="sudo apk update"
    export CMD_CLEAN=$"sudo apk clean && sudo rm -rf /tmp/* /var/tmp/*"
else
  echo "error: can't find a package manager"
  exit 1;
fi
echo "Package Manager (Install) : ${CMD_INSTALL}"
echo "Package Manager (Update)  : ${CMD_UPDATE}"
echo "Package Manager (Upgrade) : ${CMD_UPGRADE}"

# build/development dependencies
if [ -d /usr/local/src ] ; then sudo rm -rf /usr/local/src ; fi
sudo mkdir -p /usr/local/src && sudo chown ${USER} /usr/local/src && chmod 744 /usr/local/src 
${INSTALL_CMD} build-essential pkg-config intltool libtool autoconf
# sqllite
${INSTALL_CMD} sqlite3 libsqlite3-dev
# create database
# sqlite test.db

# Essential packages
$INSTALL_CMD \
  vim-gtk \
  tmux \
  git \
  gpg \
  curl \
  rsync \
  unzip \
  htop \
  shellcheck \
  ripgrep \
  pass \
  python3-pip

# Build System Support 
$INSTALL_CMD vim tzdata openssh-server
$INSTALL_CMD build-essential git wget curl unzip dos2unix htop libcurl3
$INSTALL_CMD libxext-dev
$INSTALL_CMD gdb

# Linux (ALSA) Audio Support
$INSTALL_CMD libasound2-dev libasound2 libasound2-data module-init-tools libsndfile1-dev
sudo modprobe snd-dummy
sudo modprobe snd-aloop

if [ -d /usr/src ] ; them
  rm -rf /usr/src
fi

# An example of multi-repository C project that is updated regularly
${INSTALL_CMD} pkg-config alsa-utils libasound2-dev
# Gstreamer bits, so the baresip gstreamer module will be built
${INSTALL_CMD} gstreamer1.0-alsa gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-tools gstreamer1.0-x 
${INSTALL_CMD} libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev

if [ !( grep "/usr/local/lib" /etc/ld.so.conf.d/*.conf ) ] ; then
  echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/libc.conf
  sudo ldconfig
fi

# Clone baresip repositories
git clone https://github.com/baresip/baresip /usr/src/baresip/baresip
git clone https://github.com/baresip/re      /usr/src/baresip/re
git clone https://github.com/openssl/openssl /usr/src/openssl

# Build & Install openssl
cd /ur/src/openssl && make && sudo make install && sudo ldconfig

## baresip: debug build
cd /usr/src/baresip/baresip
## baresip static build
# cmake -B build -DSTATIC=ON
cmake -B build
## baresip: release build
#cmake -B build -DCMAKE_BUILD_TYPE=Release 
## release with modules
#cmake -B build -DMODULES="menu;account;g711"
cmake --build build -j
cmake --install build


# Install & Build Libre
cd ~/git/re && make && sudo make install && sudo ldconfig
# Install & Build Librem
cd ~/git/rem && make && sudo make install && sudo ldconfig
# Build baresip
cd ~/git/baresip && make RELEASE=1 && sudo make RELEASE=1 install && sudo ldconfig
# Test Baresip to initialize default config and Exit
# baresip -t -f $HOME/.baresip
# Install Configuration from baresip-docker
# git clone https://github.com/QXIP/baresip-docker.git ~/git/baresip-docker
#cp -R ~/git/baresip-docker $HOME/.baresip
#cp -R ~/git/baresip-docker/.asoundrc $HOME
# Run Baresip set the SIP account
#CMD baresip -d -f $HOME/.baresip && sleep 2 && curl http://127.0.0.1:8000/raw/?Rsip:root:root@127.0.0.1 && sleep 5 && curl http://127.0.0.1:8000/raw/?dbaresip@conference.sip2sip.info && sleep 60 && curl http://127.0.0.1:8000/raw/?bq



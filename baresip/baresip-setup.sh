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
# need more - to hear sound under WSL you need the pulse daemon running (on Windows)

rm -rf ~/git
mkdir ~/git
# An example of multi-repository C project that is updated regularly
$INSTALL_CMD pkg-config alsa-utils libasound2-dev
# Gstreamer bits, so the baresip gstreamer module will be built
$INSTALL_CMD gstreamer1.0-alsa gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-tools gstreamer1.0-x 
$INSTALL_CMD libgstreamer-plugins-base1.0-0 libgstreamer-plugins-base1.0-dev libgstreamer1.0-0 libgstreamer1.0-dev

## LIBRE
git clone https://github.com/baresip/re /usr/src/baresip/re

On some distributions, /usr/local/lib may not be included in ld.so.conf. You can check with grep "/usr/local/lib" /etc/ld.so.conf.d/*.conf and add if necessary:

$ echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/libc.conf
$ sudo ldconfig

git clone https://github.com/baresip/baresip /usr/src/baresip/baresip
git clone https://github.com/openssl/openssl /usr/src/openssl

cmake -B build
cmake --build build -j
sudo cmake --install build
sudo ldconfig






## debug
$ cmake -B build
$ cmake --build build -j
$ cmake --install build

## release
$ cmake -B build -DCMAKE_BUILD_TYPE=Release 
$ cmake --build build -j

## release with modules
cmake -B build -DMODULES="menu;account;g711"
$ cmake --build build -j

## static release
cmake -B build -DSTATIC=ON
$ cmake --build build -j

# Install & Build Libre
cd ~/git/openssl && make && sudo make install && sudo ldconfig
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



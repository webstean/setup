#!/bin/bash

# Check if we are running as the root user
if [[ $(id -u) -eq 0 ]] ; then echo "Don't run as root - but as normal user with full sudo access - exiting" ; exit 1 ; fi

# Check if this is a Raspberry Pi
if ( ! cat /proc/cpuinfo | grep Model | grep "Raspberry" ) > /dev/null ; then echo "This is not a Raspberry Pi - exiting" ; exit 1 ; fi

# Enable sudo for users member of sudo group
if ! (sudo id | grep -q root) ; then 
    bash -c "echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' | sudo EDITOR='tee -a' visudo"
fi

# Install some essentials
sudo apt-get install -y ufw dos2unix vim apt-transport-https ca-certificates software-properties-common git curl wget sngrep 

# Setup some basic dev stuff
sudo apt-get install -y git curl
git config --global color.ui true
git config --global user.name "Andrew Webster"
git config --global user.email "webstean@gmail.com"
git config --list

# Firewall
sudo ufw status verbose
# sudo ufw enable
sudo ufw status
### Note: ufw won't be enabled until you enabled it
# install firewall tarpits etc..
sudo apt-get install -y xtables-addons-common iptables-persistent

# Turn off Swapping - to preserve the SD card
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove
sudo systemctl disable dphys-swapfile

# Set Timezone
sudo timedatectl set-timezone Australia/Melbourne
timedatectl

# Set Locale
sudo update-locale LANG=en_AU.UTF-8 LANGUAGE= LC_MESSAGES= LC_COLLATE= LC_CTYPE=
# need reboot to show up properly - it will update /etc/default/locale

# Move Pi loging to RAM to preserve SD card
if [ ! -d ~/log2ram ]; then
    git clone https://github.com/azlux/log2ram.git ~/log2ram
    chmod +x ~/log2ram/install.sh
    pushd ~/log2ram && sudo ./install.sh && popd
fi

# Latest updates
sudo apt update -y && sudo apt full-upgrade -y
sudo rpi-eeprom-update -a
sudo apt autoremove -y

# Unattended Upgrades
sudo apt-get install -y unattended-upgrades
sudo unattended-upgrade -d -v --dry-run
sudo dpkg-reconfigure --priority=low unattended-upgrades

exit 0

# 3CX Session Border Controller
# wget https://downloads-global.3cx.com/downloads/misc/d10pi.zip; sudo bash d10pi.zip .

# Check Power Supply
sudo apt-get install -y sysbench
wget https://gist.githubusercontent.com/maxme/d5f000c84a4313aa531288c35c3a8887/raw/fc355cd96e5e18e69df06ee4c34f50b7cd9a4a2a/raspberry-power-supply-check.sh
chmod +x raspberry-power-supply-check.sh
# sudo ./raspberry-power-supply-check.sh

# Install IOTstack
sudo bash -c '[ $(egrep -c "^allowinterfaces eth0,wlan0" /etc/dhcpcd.conf) -eq 0 ] && echo "allowinterfaces eth0,wlan0" >> /etc/dhcpcd.conf'
sudo apt install -y git curl
# Install docker for $USER (usually pi user)
git clone https://github.com/SensorsIot/IOTstack.git ~/IOTstack 
curl -fsSL https://get.docker.com | sh
sudo usermod -G docker -a $USER
sudo usermod -G bluetooth -a $USER
sudo apt install -y python3-pip python3-dev
sudo pip3 install -U docker-compose
sudo pip3 install -U ruamel.yaml==0.16.12 blessed

exit 0

sudo reboot
cd ~/IOTstack
./menu.sh
docker-compose up -d

exit 0

# Get Docker
sudo apt-get install -y apt-transport-https ca-certificates software-properties-common git curl
sudo curl -fsSL get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker pi
sudo curl https://download.docker.com/linux/raspbian/gpg
sudo systemctl enable docker.service
sudo systemctl start docker.service
sudo docker run hello-world
sudo docker images hello-world

# Get IOTstack
if [ ! -d ~/IOTstack ]; then
    git clone https://github.com/SensorsIot/IOTstack.git IOTstack
    cd ~/IOTstack
    git pull origin master
    git checkout master
    ### git checkout experimental
    docker-compose down
    ./menu.sh
    docker-compose up -d
    cd ..
    ## to remove
    # cd ~/IOTstack
    # sudo git clean -d -x -f
fi



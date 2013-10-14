#!/bin/bash
## Install LXC and Vagrant-LXC inside an Ubuntu VM
## Create two LXC VMs running in this environment


## references:
# http://taoofmac.com/space/HOWTO/Vagrant
# http://docs.vagrantup.com/v2/multi-machine/index.html
# https://github.com/fgrehm/vagrant-lxc/blob/master/BOXES.md

## requirements:
# Ubuntu 13.10 (maybe 12.04)
# 
# On this (host) VM
# eth0 is a NAT or bridged interface to get outside 
# eth1 is host-only network adapter
#
# use sudo to run this script
#
# project_root should be where you local git repos are stored

## NOTE:
# Beware if some hard-coding based on versions of Ubuntu and vagrant-lxc


function usage {
  echo -e "usage:\n$ sudo ./$0 [project_root]"
  exit
}

function create_vms {
  # grab (http://downloads.vagrantup.com) and install vagrant
  # `apt-get install vagrant` will try to install all sorts of shite you don't want
  # make sure the sudo user owns the things download and .vagrant dir created
  cd /home/$SUDO_USER
  wget http://files.vagrantup.com/packages/0ac2a87388419b989c3c0d0318cc97df3b0ed27d/vagrant_1.3.4_x86_64.deb
  dpkg -i vagrant_1.3.4_x86_64.deb
  rm vagrant_1.3.4_x86_64.deb
  sudo -u $SUDO_USER vagrant plugin install vagrant-lxc

  cd /home/$SUDO_USER/.vagrant.d/boxes
  if [ ! -f build-ubuntu-box.sh ]; then
    sudo -u $SUDO_USER wget https://raw.github.com/fgrehm/vagrant-lxc/master/boxes/build-ubuntu-box.sh

    # The script, when I donwloaded it has a path bug around the common dir
    VAGRANT_LXC=`find /home/${SUDO_USER}/.vagrant.d/gems/gems/ -maxdepth 1 -name "vagrant-lxc*" -type d | sort -r | head -1 | sed 's|\.|\\\.|g' | sed 's|\/|\\\/|g'`
    sed -i "s|\.\/common|${VAGRANT_LXC}\/boxes\/common|" build-ubuntu-box.sh
    sed -i "s|\${CWD}\/common|${VAGRANT_LXC}\/boxes\/common|" build-ubuntu-box.sh
    # ... and apt-add-repository is needed for install-salt
    sed -i 's/\(PACKAGES=(\)/\1python-software-properties /' build-ubuntu-box.sh
  fi

  SALT=1 bash build-ubuntu-box.sh precise amd64

  # watch it work flawlessly...
  #
  # create a 'box' and call it precise64
  sudo -u $SUDO_USER vagrant box add precise64 output/vagrant-lxc-precise-amd64-`date +'%Y-%m-%d'`.box
  #
  # Configure two lxc machines to create from this box
  cd /home/$SUDO_USER/$PROJECT_ROOT
  sudo -u $SUDO_USER cat > Vagrantfile <<VFILE
Vagrant.configure("2") do |config|

  config.vm.define "head0" do |head0|
    head0.vm.box = "precise64"
    head0.vm.hostname = "head0"
  end

  config.vm.define "head1" do |head1|
    head1.vm.box = "precise64"
    head1.vm.hostname = "head1"
  end

end
VFILE

  cat <<MSG
# boot the two machines
  vagrant up --provider=lxc
  vagrant ssh head0 # or head1
# /vagrant on your lxc VMs maps to your gerrit repos
# now read this: http://docs.vagrantup.com/v2/multi-machine/index.html
MSG
}

if [ ! $SUDO_USER ]; then
  usage
fi

PROJECT_ROOT=$1
if [ -n $PROJECT_ROOT ] && [ ! -d /home/$SUDO_USER/$PROJECT_ROOT ]; then
  echo "/home/$SUDO_USER/$PROJECT_ROOT is not a directory."
  usage
fi

sudo apt-get update 
sudo apt-get dist-upgrade

# grab the basics we need to get stuff done
sudo apt-get install -y openssh-server vim tmux htop ufw denyhosts build-essential

# grab vagrant-lxc dependencies
sudo apt-get install -y lxc redir

# the easy way to ssh in
sudo apt-get install -y avahi-daemon

# help our sshd
if [ -f /etc/ssh/sshd_config ] && [ ! `grep UseDNS\=no /etc/ssh/sshd_config` ]; then
  cat >> /etc/ssh/sshd_config <<NODNS

#Reverse lookups are not useful in a local VM, so let's lower connection time.
UseDNS=no
NODNS

  restart ssh
fi

# configure the two network adapters
cat > /etc/network/interfaces <<ETHN
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet dhcp
ETHN

# Mac people might want to use Bonjour
if [ ! -f /etc/avahi/services/ssh.service ]; then
  cat > /etc/avahi/services/ssh.service <<BONJOUR
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->                       
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">                        
<service-group>                                                            
    <name replace-wildcards="yes">%h</name>                                
    <service>                                                              
        <type>_ssh._tcp</type>                                             
        <port>22</port>                                                    
    </service>                                                             
</service-group>
BONJOUR

  sed -i 's/\(#allow-interfaces=eth0\)/\1\nallow-interfaces=eth1/' /etc/avahi/avahi-daemon.conf
  sed -i 's/\(#enable-dbus=yes\)/\1\nenable-dbus=yes/' /etc/avahi/avahi-daemon.conf

  # bring up the network interfaces too
  restart network-manager
  restart avahi-daemon
fi

# if you use ufw...
#ufw allow in on lxcbr0
#ufw allow out on lxcbr0
#sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw

if [ $PROJECT_ROOT ]; then
  create_vms
fi

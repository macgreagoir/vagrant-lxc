#!/bin/bash
## Install LXC and Vagrant-LXC inside an Ubuntu VM
## Create two LXC VMs running in this environment


## references:
# http://taoofmac.com/space/HOWTO/Vagrant
# http://docs.vagrantup.com/v2/multi-machine/index.html
# https://github.com/fgrehm/vagrant-lxc/blob/master/BOXES.md

## requirements:
# Ubuntu 13.04
# * works on 13.10 and should on 12.04
# * kernel for containers will be hosts, obviously
# 
# On this (host) VM
# eth0 is a NAT or bridged interface to get outside 
#
# Use sudo to run this script
#
# Assuming you wanto to use these LXC containers ot test code, projects_root
# should be where you local code repos are stored

## NOTE: Hard-coded versions of Ubuntu and Vagrant

cd ${0%/*}
SCRIPT_DIR=$PWD
cd $OLDPWD

function usage {
  echo -e "usage:\n$ sudo $0 [projects_root]"
  exit
}

function create_containers {
  # grab (http://downloads.vagrantup.com) and install vagrant
  # `apt-get install vagrant` will try to install all sorts of shite you don't want
  # make sure the sudo user owns the things download and .vagrant dir created
  if [ "`apt-cache policy vagrant | awk '/Installed/ {print $2}'`" != "1:1.3.5" ]; then
    wget http://files.vagrantup.com/packages/a40522f5fabccb9ddabad03d836e120ff5d14093/vagrant_1.3.5_x86_64.deb
    dpkg -i vagrant_1.3.5_x86_64.deb
    rm vagrant_*.deb
  fi
  sudo -u $SUDO_USER vagrant plugin install vagrant-lxc

  cd /home/$SUDO_USER/.vagrant.d/boxes
  # grab our own build script for a precise amd64 box
  cp $SCRIPT_DIR/build-ubuntu-box.sh . && chmod 0750 build-ubuntu-box.sh
  ./build-ubuntu-box.sh

  # create a 'box' and call it precise64
  sudo -u $SUDO_USER vagrant box add precise64 output/vagrant-lxc-precise-amd64-`date +'%Y-%m-%d'`.box

  # Configure two lxc containers to create from this box
  cd /home/$SUDO_USER/$PROJECT_ROOT
  sudo -u $SUDO_USER cat > Vagrantfile <<VFILE
Vagrant.configure("2") do |config|

  config.vm.define "container0" do |container0|
    container0.vm.box = "precise64"
    container0.vm.hostname = "container0"
  end

  config.vm.define "container1" do |container1|
    container1.vm.box = "precise64"
    container1.vm.hostname = "container1"
  end

end
VFILE

  cat <<MSG
###########################################################################
#
# boot the two containers
  cd <projects_root>
  vagrant up --provider=lxc
  vagrant ssh container0 # or container1
#
# /vagrant on the lxc containers mounts projects_root, as passed the script
# now read this: http://docs.vagrantup.com/v2/multi-machine/index.html
#
###########################################################################
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

# help our sshd
if [ -f /etc/ssh/sshd_config ] && [ ! `grep UseDNS\=no /etc/ssh/sshd_config` ]; then
  cat >> /etc/ssh/sshd_config <<NODNS

#Reverse lookups are not useful in a local VM, so let's lower connection time.
UseDNS=no
NODNS

  restart ssh
fi

if [ -z "`ufw status | grep inactive`" ]; then
  ufw allow in on lxcbr0
  ufw allow out on lxcbr0
  sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
fi

# this is really what you came here for
if [ $PROJECT_ROOT ]; then
  create_containers
fi

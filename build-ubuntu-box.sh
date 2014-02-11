#!/bin/bash
#
# borrowed from
# https://raw.github.com/fgrehm/vagrant-lxc/master/boxes/build-ubuntu-box.sh
set -e

# Script used to build Ubuntu base vagrant-lxc containers
#
# USAGE:
#   $ cd ~/.vagrant.d/boxes && sudo ./build-ubuntu-box.sh

##################################################################################
# 0 - Initial setup and sanity checks

TODAY=$(date -u +"%Y-%m-%d")
NOW=$(date -u)
RELEASE=precise
ARCH=amd64
PKG=vagrant-lxc-${RELEASE}-${ARCH}-${TODAY}.box
WORKING_DIR=/tmp/vagrant-lxc-${RELEASE}
VAGRANT_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key"
ROOTFS=/var/lib/lxc/${RELEASE}-base/rootfs

# Path to files bundled with the box
CWD=$PWD
LXC_PLUGIN_DIR=`find ${CWD}/../gems/gems/ -maxdepth 1 -name "vagrant-lxc*" -type d 2> /dev/null | sort -r | head -1`

if [ -z "$LXC_PLUGIN_DIR" ]; then
  echo "Could not find the vagrant-lxc plugin"
  echo "usage: cd ~/.vagrant.d/boxes && sudo ./build-ubuntu-box.sh"
  exit 1
fi

LXC_TEMPLATE=${LXC_PLUGIN_DIR}/boxes/common/lxc-template
LXC_CONF=${LXC_PLUGIN_DIR}/boxes/common/lxc.conf
METATADA_JSON=${LXC_PLUGIN_DIR}/boxes/common/metadata.json

# Set up a working dir
mkdir -p $WORKING_DIR

if [ -f "${WORKING_DIR}/${PKG}" ]; then
  echo "Found a box on ${WORKING_DIR}/${PKG} already!"
  exit 1
fi

##################################################################################
# 1 - Create the base container

if $(lxc-ls | grep -q "${RELEASE}-base"); then
  echo "Base container already exists, please remove it with \`lxc-destroy -n ${RELEASE}-base\`!"
  exit 1
else
  lxc-create -n ${RELEASE}-base -t ubuntu -- --release ${RELEASE} --arch ${ARCH}
fi

# Fixes some networking issues
# See https://github.com/fgrehm/vagrant-lxc/issues/91 for more info
echo 'ff02::3 ip6-allhosts' >> ${ROOTFS}/etc/hosts


##################################################################################
# 2 - Prepare vagrant user

mv ${ROOTFS}/home/{ubuntu,vagrant}
chroot ${ROOTFS} usermod -l vagrant -d /home/vagrant ubuntu
chroot ${ROOTFS} groupmod -n vagrant ubuntu

echo -n 'vagrant:vagrant' | chroot ${ROOTFS} chpasswd


##################################################################################
# 3 - Setup SSH access and passwordless sudo

# Configure SSH access
mkdir -p ${ROOTFS}/home/vagrant/.ssh
echo $VAGRANT_KEY > ${ROOTFS}/home/vagrant/.ssh/authorized_keys
chroot ${ROOTFS} chown -R vagrant: /home/vagrant/.ssh

# Enable passwordless sudo for users under the "sudo" group
cp ${ROOTFS}/etc/sudoers{,.orig}
sed -i -e \
      's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' \
      ${ROOTFS}/etc/sudoers


##################################################################################
# 4 - Add some goodies and update packages

PACKAGES=(vim curl wget man-db bash-completion)
chroot ${ROOTFS} apt-get update
chroot ${ROOTFS} apt-get upgrade -y --force-yes
chroot ${ROOTFS} apt-get install ${PACKAGES[*]} -y --force-yes


##################################################################################
# 5 - Free up some disk space

rm -rf ${ROOTFS}/tmp/*
chroot ${ROOTFS} apt-get clean


##################################################################################
# 6 - Build box package

# Compress container's rootfs
cd $(dirname $ROOTFS)
tar --numeric-owner -czf /tmp/vagrant-lxc-${RELEASE}/rootfs.tar.gz ./rootfs/*

# Prepare package contents
cd $WORKING_DIR
cp $LXC_TEMPLATE .
cp $LXC_CONF .
cp $METATADA_JSON .
chmod +x lxc-template
sed -i "s/<TODAY>/${NOW}/" metadata.json

# Vagrant box!
tar -czf $PKG ./*

chmod +rw ${WORKING_DIR}/${PKG}
mkdir -p ${CWD}/output
mv ${WORKING_DIR}/${PKG} ${CWD}/output

# Clean up after ourselves
rm -rf ${WORKING_DIR}
lxc-destroy -n ${RELEASE}-base

echo "The base box was built successfully to ${CWD}/output/${PKG}"

vagrant-lxc
===========

Install Vagrant with LXC in an Ubuntu VM.

This is a horrible theft of other people's hardwork, that, when run in an 
Ubuntu 13.04 VM in VirtualBox, should download, install and configure all you 
need to run Vagrant LXC VMs inside your Ubuntu VM.

It presumes to reconfigure the VM's network interfaces.

It can also create a couple of new LXC VMs using your own Ubuntu Precise amd64 
Vagrant box, and will include what they need to use SaltStack.

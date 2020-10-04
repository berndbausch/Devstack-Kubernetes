
Setting up a single-server Devstack cloud as a Kubernetes platform
==================================================================

The Devstack server
-------------------

Install the server version of Ubuntu 18.04 on a computer with these
properties:

- RAM about 15GB
- Storage around 50GB
- A few CPUs (minimum 2, the more the better)
- A single NIC that can reach the internet and that can be reached from
  outside.

This computer, henceforth named Devstack server, can be a physical computer
in your lab or at a public provider, or a virtual machine running in your 
lab or a public cloud.

In case the Devstack server is a VM, ensure that nested virtualization is 
possible and enabled. Otherwise, many actions will be painfully slow, e.g. 
count an hour or more for installing software on the OpenStack instances.

This should not be a problem for VMs in public clouds (but it's best to
check). In case you, like I, opt for a VM in your lab, use a hypervisor that
allows nested virtualization. I use KVM; recent versions of Virtualbox seem to 
support nested virtualization as well, as does Xen.

To enable nested virtualization on a Linux host, add kvm-intel.nested=1 or
kvm-amd.nested=1 to the kernel parameters, or create a modprobe.conf.d file
that loads the corresponding kernel module kvm_adm or kvm_intel with the
nested=1 parameter.

Here is my setup: Physical Linux computer running a VM where Devstack is 
installed. The Devstack VM contains a K8s cluster running on nested VMs. br-ex
is an Openvswitch bridge that connects all OpenStack VMs to the outside world;
this is the Devstack default.

     +---------------- Physical host -----------------+
     |                                                |
     |                                                |
     | +------ Devstack server (a KVM VM) ----------+ |
     | |                                            | |
     | |  +------------+          +------------+    | |
     | |  | K8s master |          | K8s worker |    | |
     | |  +------\-----+          +------/-----+    | |
     | |          \                     /           | |
     | |           -----\     /---------            | |
     | |                 |   |                      | |
     | |               /-------\                    | |
     | |               | br-ex |                    | |
     | |               \-------/                    | |
     | |                   |                        | |
     | +------------- Virtual NIC ------------------+ |
     |                     |                          |
     |              /-------------\                   |
     |              | Linuxbridge |                   |
     |              \-------------/                   |
     |                     |                          |
     +-----------------Physical NIC-------------------+
                           | 
  _____ External Network __|______________________________________

Thanks to the bridges, the Devstack server and the K8s masters and workers
can get IP addresses from the external network. This is desirable, as it
allows exposing services that run on the K8s cluster to the outside world.

However, in order to allow access to K8s services from the external network, 
the hypervisor that hosts the Devstack server must pass traffic to the K8s 
cluster nodes. In my experience, Virtualbox and Xen block such traffic (I am
a Xen newbie and don't know if this can be made to work). 
In case you implement the Devstack server on Virtualbox or Xen, you need to be
aware that you can access the K8s cluster from the Devstack server, but not
from any device outside of the Devstack server.
I have not tried out Vmware or Hyper-V.

Preparing the Devstack server and deploying the cloud
-----------------------------------------------------

You need a default Ubuntu installation with SSH access and correct DNS
resolution. Before setting up Devstack:

- configure a static IP address (DHCP probably works as well, but static is
  safer)
- create a user *stack* with password-less sudo. For example:

        useradd -m stack
        usermod -aG sudo stack
        sudo sed -i '/^%sudo/s/ALL$/NOPASSWD: ALL/' /tmp/sudoers  

- I had problems with Ubuntu's default DNS resolution, which was magically
  destroyed during cloud deployment. While I don't know precisely why this
  happened, I solved the problem by linking /etc/resolv.conf as follows:

        ln -s /run/systemd/resolve/resolv.conf /etc

After these preparations, log on as the stack user and clone Devstack. 
You may want to read about Devstack installation and configuration on
http://docs.openstack.org/devstack, but its documentation has gaps and is not 
that well organized.

    git clone https://opendev.org/openstack/devstack -b stable/ussuri

This creates the $HOME/devstack directory and copies the Ussuri version of
Devstack to it. Feel free to analyze its contents; Devstack is a collection of 
Bash scripts.

Devstack has a single configuration file named local.conf. Adapt the
local.conf template from this repo and copy it to the devstack directory.
Then launch the cloud:
    
    cd $HOME/devstack
    ./stack.sh

This will generate a lot of output, which is also written to
/opt/stack/logs/stack.sh.log. The deployment process installs Ubuntu and
Python packages from the internet and obtains VM images - installation time
depends to a large extent on your internet bandwidth but also your disks. 
Count one to two hours.

Many causes for failure are possible, including

- apt or dpkg are running in the background, perhaps because Ubuntu is
  currently looking for updates. Try again when apt/dpkg are quiet.
- access to some packages fails due to network problems. Try again after a 
  few minutes.
- incompatibilities among Python packages. This requires a fix either from the
  package maintainers or the Devstack team. Count 24 hours.
- problems with your Devstack server: Network breaks down, not enough space,
  ...

A successful deployment is indicated by

	=========================
	DevStack Component Timing
	 (times are in seconds)
	=========================
	run_process           39
	test_with_retry        4
	apt-get-update         5
	osc                  437
	wait_for_service      18
	git_timed            260
	dbsync               422
	pip_install          455
	apt-get              898
	-------------------------
	Unaccounted time     2074
	=========================
	Total runtime        4612



	This is your host IP address: 192.168.1.200
	This is your host IPv6 address: ::1
	Horizon is now available at http://192.168.1.200/dashboard
	Keystone is serving at http://192.168.1.200/identity/
	The default users are: admin and demo
	The password: pw

	WARNING:
	Using lib/neutron-legacy is deprecated, and it will be removed in the future


	Services are running under systemd unit files.
	For more information see:
	https://docs.openstack.org/devstack/latest/systemd.html

	DevStack Version: ussuri
	Change: f482957e89d1ee938da679529aa10f13b2d07631 Bionic: Enable Train UCA for updated QEMU and libvirt 2020-09-18 09:10:58 +0100
	OS Version: Ubuntu 18.04 bionic

Configuring your cloud
----------------------

The cloud's GUI is accessed by directing a browser to the Devstack server's 
IP address. Command line access is possible from a shell on the Devstack
server. 

These instructions require a certain amount of cloud configuration: A project
and user, a network, a security group, a keypair, and a Centos image.

Obtain a Centos 7 cloud image in qcow2 format (see instructions at
https://docs.openstack.org/image-guide/obtain-images.html#centos), name it
centos7.qcow2 and copy it to the stack user's home directory. Then run the
preparation script. It performs the following steps:

- It uploads the Centos 7 image to the OpenStack image store.

- It creates a project named *kube*, a user named *kube* and give this user the
  roles *member* and *load-balancer_member*

- It creates a network named *kubenet* and a router named *kuberouter*, which
  connects *kubenet* to the external network *public*.

- It creates a security group named *kubesg*, which opens the network ports 
  necessary for running a K8s cluster.

- It creates an SSH keypair and a corresponding OpenStack keypair. The key
  is required to SSH into the K8s nodes.

- It allocates two floating IPs. These are IP addresses on the external
  network that will allow you to access the K8s nodes.

- It launches two Centos-based cluster node *master1* and *worker1*, and
  assigns the security group and floating IPs to them.

All this can also be done on the GUI, though manually.

Optionally: Test if load balancing works
----------------------------------------

Based on
https://docs.openstack.org/devstack/latest/guides/devstack-with-lbaas-v2.html.

This is not really required, but if you are interested in the setup of a load
balancer in an OpenStack cloud, you may benefit from this.

Use the Openstack kube identity. Launch two Cirros instances.

    source ~/devstack/openrc kube kube
    openstack server create --image cirros --network kubenet --flavor 1 \
                            --key-name kubekey --min 2 --max 2 c

This launches two instances named c-1 and c-2. Add them to the kubesg security
group (this opens their firewall for ICMP and network ports 22 and 80) and 
associate floating IP addresses with them.

    openstack floating ip create public
    openstack floating ip create public   # you need two of them
    openstack server add security group c-1 kubesg
    openstack server add security group c-2 kubesg
    openstack server add floating IP c-1 FLOATING-IP-1
    openstack server add floating IP c-2 FLOATING-IP-2

Access them and install a rudimentary HTTP server.

    ssh -i kubekey cirros@FLOATING-IP-1
    $ while true
         do echo -e "HTTP/1.0 200 OK\r\n\r\nWelcome to server 1" | 
         sudo nc -l -p 80 
    done &
    $ exit

This short script returns "Welcome to server 1" when the server receives an
HTTP request. Do the same for the other instance.

    ssh -i kubekey cirros@FLOATING-IP-2
    $ while true
         do echo -e "HTTP/1.0 200 OK\r\n\r\nThis is server 2" | 
         sudo nc -l -p 80 
    done &
    $ exit

Test this.

    curl FLOATING-IP-1
    curl FLOATING-IP-2

Now create a load balancer with these two instances as backends. You need to
create the load balancer, a listener, a pool for that listener, and add the
two instances as pool members. This is quite easy to do from the GUI. Here are
the CLI instructions, almost verbatim from
https://docs.openstack.org/devstack/latest/guides/devstack-with-lbaas-v2.html#phase-2-create-your-load-balancer.

    # Obtain fixed IP addresses from the Cirros instances
    FIXED-IP-1=$(openstack server show c-1 -c addresses -f value | sed -e 's/kubenet=//' -e 's/,.*//')
    FIXED-IP-2=$(openstack server show c-2 -c addresses -f value | sed -e 's/kubenet=//' -e 's/,.*//')

    openstack loadbalancer create --name testlb --vip-subnet-id kubesubnet
    openstack loadbalancer show testlb  
    # Repeat the above command until the provisioning_status turns ACTIVE.

    openstack loadbalancer listener create --protocol HTTP --protocol-port
    80 --name testlistener testlb
    openstack loadbalancer pool create --lb-algorithm ROUND_ROBIN
    --listener testlistener --protocol HTTP --name testpool
    openstack loadbalancer member create --subnet-id kubesubnet --address $FIXED-IP-1 --protocol-port 80 testpool
    openstack loadbalancer member create --subnet-id kubesubnet --address $FIXED-IP-2 --protocol-port 80 testpool


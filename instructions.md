
Setting up a single-server Devstack cloud as a Kubernetes platform
==================================================================

The Devstack server
-------------------

Install the server version of Ubuntu 18.04 on a computer with these
properties:

- RAM about 15GB for comfortable operation. You will run at least two Kubernetes nodes
  (4GB each) and a loadbalancer instance in addition to the cloud overhead.
- Storage around 50GB
- A few CPUs (minimum 2, the more the better)
- A single NIC that can reach the internet and that can be reached from
  outside

This computer, henceforth named Devstack server, can be a physical computer
in your lab or at a public provider, or a virtual machine running in your 
lab or a public cloud. 

Should you opt for running the Devstack server in a VM in your lab, ensure that the
hypervisor supports **nested virtualization** and allows network traffic to flow to the
nested VMs. KVM fulfills both conditions. In my experience, VirtualBox and Xen block
traffic to the nested VMs, perhaps because they refuse to talk to unknown IP addresses
(I am a Xen newbie; there might be a configuration setting that changes this behaviour).
I have not tried Vmware, Hyper-V or WSL.

Without nested virtualization, many actions will be painfully slow, e.g. 
an hour or more for installing software on nested VMs. 

To enable nested virtualization on KVM, add 
`kvm-intel.nested=1` or `kvm-amd.nested=1` to the Linux kernel parameters. Alternatively, 
create a `modprobe.conf.d` file that loads the corresponding kernel module 
`kvm_adm` or `kvm_intel` with the `nested=1` parameter.

Here is my setup: The Devstack server runs in a KVM virtual machine that is connected to 
the external network via a Linuxbridge. The K8s cluster nodes (master and worker) are 
OpenStack instances running inside the Devstack server. *br-ex* is an Openvswitch bridge 
that connects all OpenStack instances to the outside world. The Devstack server's single
NIC is plugged into br-ex.

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
    _______________________|_________External Network_______________

Thanks to the bridges, the Devstack server and the K8s nodes
can get IP addresses from the external network. This is desirable, as it
allows to expose K8s cluster services to the outside world.

Preparing the Devstack server and deploying the cloud
-----------------------------------------------------

The Devstack documentation site has instructions for 
[deploying Devstack](https://docs.openstack.org/devstack) and for 
[enabling the loadbalancer](https://docs.openstack.org/devstack/latest/guides/devstack-with-lbaas-v2.html). 
These instructions don't cover everything; for example, how to connect the cloud to the 
external network or how to enable the loadbalancer's GUI. The steps below worked for me.

Start with a default Ubuntu 18.04 installation with SSH access. 
Before setting up Devstack:

- configure a static IP address (DHCP probably works as well, but static is
  safer)
- create a user *stack* with password-less sudo as shown on the Devstack site.
- I had problems with Ubuntu's default DNS resolution, which was magically
  destroyed during cloud deployment. While I don't know precisely why this
  happened, I solved the problem by linking /etc/resolv.conf as follows:

        ln -s /run/systemd/resolve/resolv.conf /etc

After these preparations, log on as the *stack* user and clone the Ussuri version of 
Devstack.

    git clone https://opendev.org/openstack/devstack -b stable/ussuri

This creates the $HOME/devstack directory and copies Devstack to it. Devstack is a 
collection of Bash scripts, and it's instructive to analyze them.

Devstack has a single configuration file named *local.conf*. Adapt the
[local.conf template from this repo](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/local.conf) and copy it to the devstack directory.
Then launch the cloud:
    
    cd $HOME/devstack
    ./stack.sh

This will generate a lot of output, which is also written to
`/opt/stack/logs/stack.sh.log`. The deployment process installs Ubuntu and
Python packages from the internet and obtains VM images. For this reason, installation 
time depends to a large extent on your internet bandwidth but also the speed of your
harddisk(s). Rough estimation: One to two hours.

Deployment can fail for many reasons, including:

- `apt` or `dpkg` are running in the background, perhaps because Ubuntu is
  currently looking for updates. Try again when apt/dpkg are quiet.
- access to some packages fails due to network problems. Try again after a 
  few minutes.
- incompatibilities among Python packages. This requires a fix either from the
  package maintainers or the Devstack team. Count 24 hours minimum.
- problems with your Devstack server: Network breaks down, not enough space,
  ...

It should be possible to re-run an unsuccessful deployment as long as you don't change
*local.conf*. Deploying a modified *local.conf* may require installation from scratch.

You know that the deployment was successful when it ends with messages similar to this:

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

To access the cloud's GUI, direct a browser to the Devstack server's 
IP address. For command line access, use a shell on the Devstack server. 

Before installing a Kubernetes cluster, add the following to the cloud: A project and 
user, a network, a security group, a keypair, and a Centos image. Run the [preparation
script]((https://github.com/berndbausch/Devstack-Kubernetes/blob/main/preparation.sh) 
to create all these cloud resources.

If you need to reboot the Devstack server
-----------------------------------------

Devstack is not designed for getting restarted. Some of the configuration created when
deploying a cloud is non-persistent. If you plan to switch the Devstack server off, you 
need to make it restart-proof.

The *br-ex* bridge must be configured with the Devstack server's IP address. This can be
done with a [netplan configuration file](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/00-installer-config.yaml). 
Copy it to `/etc/netplan`.

Much of the remaining configuration settings could also be made persistent with
configuration files, but a script does the job as well. Run [restore-devstack.sh](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/restore-devstack.sh) after each
reboot.

Optionally: Test if load balancing works
----------------------------------------

Based on the [Devstack loadbalancer guide](https://docs.openstack.org/devstack/latest/guides/devstack-with-lbaas-v2.html).

This is not really required, but if you are interested in the setup of a load
balancer in an OpenStack cloud, you may benefit from this.

Do this when the cloud is set up. Use the Openstack kube identity. Start by launching
two Cirros instances.

    source ~/devstack/openrc kube kube
    openstack server create --image cirros --network kubenet --flavor 1 \
                            --key-name kubekey --min 2 --max 2 c

This launches two instances named *c-1* and *c-2*. Add them to the *kubesg* security
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

This short script responds with "Welcome to server 1" when the server receives an
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
two instances as pool members. The GUI allows you to do this intuitively. Here are
the CLI instructions, almost verbatim from the [Devstack guide](https://docs.openstack.org/devstack/latest/guides/devstack-with-lbaas-v2.html#phase-2-create-your-load-balancer) 
with additions from the [Basic Load Balancing Cookbook](https://docs.openstack.org/octavia/latest/user/guides/basic-cookbook.html#deploy-a-basic-http-load-balancer-using-a-floating-ip).

    # Obtain fixed IP addresses from the Cirros instances
    FIXED-IP-1=$(openstack server show c-1 -c addresses -f value | sed -e 's/kubenet=//' -e 's/,.*//')
    FIXED-IP-2=$(openstack server show c-2 -c addresses -f value | sed -e 's/kubenet=//' -e 's/,.*//')

    openstack loadbalancer create --name testlb --vip-subnet-id kubesubnet
    openstack loadbalancer show testlb  
    # Repeat the above `show` command until the provisioning status turns ACTIVE.

    openstack loadbalancer listener create --protocol HTTP --protocol-port
    80 --name testlistener testlb
    openstack loadbalancer pool create --lb-algorithm ROUND_ROBIN
    --listener testlistener --protocol HTTP --name testpool
    openstack loadbalancer member create --subnet-id kubesubnet --address $FIXED-IP-1 --protocol-port 80 testpool
    openstack loadbalancer member create --subnet-id kubesubnet --address $FIXED-IP-2 --protocol-port 80 testpool

The loadbalancer is in place. As the final step, add a floating IP so that it can be
reached from outside the cloud. This is a bit involved.

Obtain the loadbalancer's ID

    LB_ID=$(openstack loadbalancer show testlb -c id -f value)

Obtain the Neutron port that carries the loadbalancer's virtual IP

    PORT_ID=$(openstack port list --device-id lb-$LB_ID -c ID -f value)

Create a new floating IP and save its ID

    FLOATINGIP_ID=$(openstack floating ip create public -c id -f value)

Associate this floating IP with the loadbalancer's VIP port

    openstack floating ip set --port $PORT_ID $FLOATINGIP_ID


# Use the OpenStack admin identity
source ~/devstack/openrc admin admin

# Download the latest Centos 7 cloud image and add it to the OpenStack image catalog.
# The xz command is CPU intensive and will be extremely slow without nested
# virtualization. Download the non-compressed image if in doubt.
wget https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2.xz -O - | xz -d >centos7.qcow2
openstack image create --file ../centos7.qcow2 --disk-format qcow2 --public centos7

# Create the kube project and user, and add necessary roles to the user.
openstack project create kube
openstack user create kube --password pw
openstack role add --user kube --project kube member
openstack role add --user kube --project kube load-balancer_member

# Switch to the kube user/project identity
source ~/devstack/openrc kube kube

# Create the network for the K8s cluster nodes and connect it to *public*, the external network
openstack network create kubenet
openstack subnet create --subnet-range 172.16.0.0/24 --network kubenet --dns-nameserver 192.168.1.16 kubesubnet
openstack router create kuberouter
openstack router set --external-gateway public kuberouter
openstack router add subnet kuberouter kubesubnet

# Create the security group for K8s cluster nodes
openstack security group create kubesg
openstack security group rule create kubesg --proto icmp

# Open network ports in *kubesg*.
# This is based on
# https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm/
# Calico and Weave ports can probably be removed from the list below.
# ssh and http ports were added to the list.
while read proto ports description
do
    openstack security group rule create kubesg --proto $proto --dst-port $ports --description "$description"
    echo openstack security group rule create kubesg --proto $proto --dst-port $ports --description "$description"
done << EOF
TCP     22      SSH
TCP     80      HTTP for testing
TCP     6443    Kubernetes API Server
TCP     2379:2380       etcd server client API
TCP     10250   Kubelet API
TCP     10251   kube-scheduler
TCP     10252   kube-controller-manager
TCP     10255   Read-only Kubelet API
TCP     30000:32767     NodePort Services
TCP     179     Calico BGP network
TCP     9099    Calico felix (health check)
UDP     8285    Flannel
UDP     8472    Flannel
TCP     6781:6784       Weave Net
UDP     6783:6784       Weave Net
EOF

# Create an SSH keypair.
# Alternatively, an existing keypair can be used.
ssh-keygen -f kubekey -P ""

# Add the public key to OpenStack
openstack keypair create --public-key kubekey.pub kubekey

# Launch two Centos images. They will be used to install the K8s cluster.
openstack server create --image centos7 --network kubenet --flavor d4 --key-name kubekey master1
openstack server create --image centos7 --network kubenet --flavor d4 --key-name kubekey worker1

# Obtain two floating IPs for the cluster nodes
IPMASTER=$(openstack floating ip create public -f value -c name)
IPWORKER=$(openstack floating ip create public -f value -c name)

# Add *kubesg* and the floating IPs to the cluster nodes
openstack server add security group master1 kubesg
openstack server add security group worker1 kubesg
openstack server add floating ip master1 $IPMASTER
openstack server add floating ip worker1 $IPWORKER


##############################################################
#
# MUST BE RUN AS ROOT
#
##############################################################

####################### Install Docker CE ####################

## Set up the repository
### Install required packages.

yum install -y yum-utils device-mapper-persistent-data lvm2

### Add Docker repository.

yum-config-manager \
  --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo

## Install Docker CE.

yum update -y && yum install -y docker-ce-18.06.2.ce

## Create /etc/docker directory.

mkdir /etc/docker

# Configure the Docker daemon

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart Docker
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

######################  Install Kubernetes #####################

# configure the Kubernetes repo

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Set SELinux in permissive mode (effectively disabling it)
# Caveat: In a production environment you may not want to disable SELinux, 
# please refer to Kubernetes documents about SELinux

setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Install the tools required to set up a cluster
# and enable and start the kubelet

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
systemctl enable --now kubelet

# Allow Netfilter rules on Linuxbridges 
# These parameters are probably set already, but it doesn't hurt to
# configure them explicitly.
# The parameters configure the br_netfilter module below.

cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

# br_netfilter enables Netfilter rules on bridges. Most likely, it is already
# loaded.
modprobe br_netfilter

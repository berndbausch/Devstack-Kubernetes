
A Kubernetes cluster with OpenStack cloud provider and Cinder plugin
====================================================================

We will use *kubeadm* to launch a Kubernetes cluster on a master and a worker 
instance, then install the OpenStack cloud provider and the Cinder plugin. This
will enable us to launch Kubernetes LoadBalancer services and use Cinder
volumes as Persistent Volumes.

This documents creates the Kubernetes cluster in three parts: Installation of 
Docker and Kubernetes, installation of the OpenStack cloud provider, and 
installation of the CSI plugin for Cinder. It is based on a kubernetes.io 
[blog entry](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm/) for part 1 and the official [OpenStack-Kubernetes 
software documentation](https://github.com/kubernetes/cloud-provider-openstack/tree/master/docs) for parts 2 to 4.

1. [Installing Kubernetes](#kubernetes)
2. [Building the Kubernetes cluster](#cluster)
3. [Installing the OpenStack Cloud Provider](#cloud-provider)
4. [Installing the CSI Cinder plugin](#cinder)

Installing Kubernetes <a name="kubernetes">
---------------------

As a first step, log on to the master and worker nodes and set their hostnames 
to the respective OpenStack instance name. 

On the Devstack server, list the instances:

	$ source ~/devstack/openrc kube kube
	$ openstack server list
	+--------+---------+--------+-------------------------------------+---------+---------+
	| ID     | Name    | Status | Networks                            | Image   | Flavor  |
	+--------+---------+--------+-------------------------------------+---------+---------+
	| 32d... | worker1 | ACTIVE | kubenet=172.16.0.99, 192.168.1.228  | centos7 | ds4G    |
	| cf8... | master1 | ACTIVE | kubenet=172.16.0.169, 192.168.1.221 | centos7 | ds4G    |
	+--------+---------+--------+-------------------------------------+---------+---------+

To log on to an instance, you need its IP address and its SSH key. The second IP 
address of each instance in the above output is its floating IP. 
If you used or followed the [preparation script](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/preparation.sh) on the Devstack server, 
the key is $HOME/kubekey.

Log on to the servers and fix their hostname. Also add the hostnames to
/etc/hosts.

    $ ssh -i kubekey centos@192.168.1.221
	$ sudo hostnamectl set-hostname master1
	$ echo 192.168.1.221 master1 | sudo tee -a /etc/hosts
	$ echo 192.168.1.228 worker1 | sudo tee -a /etc/hosts
	$ exit
    $ ssh -i kubekey centos@192.168.1.228
	$ sudo hostnamectl set-hostname worker1
	$ echo 192.168.1.221 master1 | sudo tee -a /etc/hosts
	$ echo 192.168.1.228 worker1 | sudo tee -a /etc/hosts
	$ exit

Next, install Docker and Kubernetes software on **both nodes**, master and worker. You can do that in parallel.

The easiest method is running the [install-node](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/install-node.sh) script. This script is taken verbatim from the
kubernetes.io [blog post](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm/#install-docker-and-kubernetes). In case you want to execute the steps manually, stop after `modprobe br_netfilter`.


Building the Kubernetes cluster<a name="cluster" />
-------------------------------

The following instructions are slightly adapted from official 
[OpenStack Cloud Provider](https://github.com/kubernetes/cloud-provider-openstack/blob/release-1.19/docs/using-openstack-cloud-controller-manager.md) 
documentation.

On the master, build a simple cluster with kubeadm using 
[kubeadm-config-os.yaml](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/manifests/kubeadm-config-os.yaml). The kubeadm command **must be run as root**.

    $ sudo kubeadm init --config kubeadm-config-os.yaml

This should take a few minutes. During this time, have a look at the kubeadm
config file. It configures an external cloud provider and defines a pod
subnet of 10.244.0.0/16. 

When *kubeadm* completes, it tells you how to create a *.kube*
configuration directory and how to add other nodes to the cluster:

	Your Kubernetes control-plane has initialized successfully!

	To start using your cluster, you need to run the following as a regular user:

	  mkdir -p $HOME/.kube
	  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	  sudo chown $(id -u):$(id -g) $HOME/.kube/config

	You should now deploy a pod network to the cluster.
	Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
	  https://kubernetes.io/docs/concepts/cluster-administration/addons/

	Then you can join any number of worker nodes by running the following on each as root:

	kubeadm join 172.16.0.152:6443 --token arr5on.ecrqdbjpt9vqr44z \
		--discovery-token-ca-cert-hash sha256:8c9cae87374f82f18be7ca1bad17c77c30ff1f58b920d37e6d6e5956badc1114

Create *.kube/config* as instructed. Make a note of the *kubeadm join* command
but don't execute it yet.

Add the network plugin. To install Flannel, for example, run *kubectl* as the 
**non-privileged centos user**.

    $ kubectl apply -f https://github.com/coreos/flannel/raw/master/Documentation/kube-flannel.yml

Check if the Docker and Kubernetes installation on the worker node is complete.
Once it is, run the above *kubeadm* command **as root on the worker node**.

When done, **on the master**, check the result with 

    $ kubectl get nodes
	NAME      STATUS   ROLES    AGE     VERSION
	master1   Ready    master   7m37s   v1.19.2
	worker1   Ready    <none>   58s     v1.19.2
	
If *worker1* is not ready, repeat the command a few seconds later.

You now have a working Kubernetes cluster. Feel free to explore it with a few
*kubectl get* commands or to deploy an application on it.

	$ kubectl get pods -n kube-system
	NAME                              READY   STATUS    RESTARTS   AGE
	coredns-f9fd979d6-hwmpf           1/1     Running   0          9m12s
	coredns-f9fd979d6-kht96           1/1     Running   0          9m12s
	etcd-master1                      1/1     Running   0          9m19s
	kube-apiserver-master1            1/1     Running   0          9m19s
	kube-controller-manager-master1   1/1     Running   0          9m19s
	kube-flannel-ds-c27nb             1/1     Running   0          2m53s
	kube-flannel-ds-zpbkr             1/1     Running   0          3m43s
	kube-proxy-dxnck                  1/1     Running   0          9m12s
	kube-proxy-hl62l                  1/1     Running   0          2m53s
	kube-scheduler-master1            1/1     Running   0          9m19s


Installing the OpenStack Cloud Provider<a name="cloud-provider" />
---------------------------------------




Installing the CSI Cinder plugin<a name="cinder" />)
--------------------------------


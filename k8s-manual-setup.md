
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

Next, follow the instructions for installing Docker and Kubernetes from the
kubernetes.io [blog post](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm/#install-docker-and-kubernetes). Stop after 
`modprobe br_netfilter`.
If you are not interested in the details, run the
[install_master](http://tobedone) script.


Building the Kubernetes cluster<a name="cluster" />
-------------------------------



Installing the OpenStack Cloud Provider<a name="cloud-provider" />
---------------------------------------




Installing the CSI Cinder plugin<a name="cinder" />)
--------------------------------


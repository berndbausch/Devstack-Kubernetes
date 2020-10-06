
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

On the master, build a simple cluster with *kubeadm* using 
[kubeadm-config-os.yaml](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/manifests/kubeadm-config-os.yaml). The kubeadm command **must be run as root**.

    $ sudo kubeadm init --config kubeadm-config-os.yaml

This should take a few minutes. During this time, have a look at *kubeadm-config-os.yaml*. It configures an external cloud provider and defines a pod
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
Once it is, run the above *kubeadm join* command **as root on the worker node**.

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

The OpenStack cloud provider enables a Kubernetes cluster to manage nodes that
are implemented on OpenStack instances and to use the OpenStack load balancer.

To install and configure it, the following ingredients are needed:
1. cloud authentication details
2. other cloud details such as the network to which the load balancer is connected
3. a cloud controller manager
4. RBAC roles for the cloud controller manager

The following template contains the cloud details (points 1 and 2):

	[Global]
	region=RegionOne
	username=kube
	password=pw
	auth-url=http://<<DEVSTACK-SERVER-IP/identity/v3>>
	tenant-id=<<KUBE-PROJECT-ID>>
	domain-id=default

	[LoadBalancer]
	network-id=<<ID-OF-KUBENET-NETWORK>> 

	[Networking]
	public-network-name=public

To obtain the `KUBE-PROJECT-ID` and `ID-OF-KUBENET-NETWORK`, run these commands
**on the Devstack server**:

	$ source ~/devstack/openrc kube kube
	$ openstack project show kube -c id
	+-------+----------------------------------+
	| Field | Value                            |
	+-------+----------------------------------+
	| id    | 7a099eff1fb1479b89fa721da3e1a018 |
	+-------+----------------------------------+

	$ openstack network list -c ID -c Name
	+--------------------------------------+---------+
	| ID                                   | Name    |
	+--------------------------------------+---------+
	| 0e80607f-7cd1-4fe5-a782-3459fa447202 | public  |
	| dd07c40e-5e6d-4f4c-bb66-cfdcee6dbc70 | kubenet |
	| e9bbe2fc-daa3-4cdf-aaf3-4c65c8a1a321 | shared  |
	+--------------------------------------+---------+

**On the master node**, copy the template to a file named *cloud.conf* 
and replace the two IDs as well as the Devstack server's IP address. Since
this configuration contains a password, it must be turned into a
secret:

    $ kubectl create secret -n kube-system generic cloud-config --from-file=cloud.conf

Use the unchanged manifests from the OpenStack cloud provider repo to create RBAC
resources and launch the controller (points 3 and 4).

	kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/master/cluster/addons/rbac/cloud-controller-manager-roles.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/master/cluster/addons/rbac/cloud-controller-manager-role-bindings.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/master/manifests/controller-manager/openstack-cloud-controller-manager-ds.yaml

While the controller manager launches, it might be instructive to explore its
manifest. The cloud controller is implemented as a daemonset with a single
container. Have a look at the command in the container and its options.
Analyze how the secret is used: It is mounted as a volume named
*cloud-config-volume*.

The launch will take a few seconds to complete. Check its success with

	$ kubectl -n kube-system get daemonset,pv,pod
	NAME                                                DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR                     AGE
	daemonset.apps/kube-flannel-ds                      2         2         2       2            2           <none>                            38m
	daemonset.apps/kube-proxy                           2         2         2       2            2           kubernetes.io/os=linux            44m
	daemonset.apps/openstack-cloud-controller-manager   1         1         0       1            0           node-role.kubernetes.io/master=   34s

	NAME                                           READY   STATUS    RESTARTS   AGE
	pod/coredns-f9fd979d6-hwmpf                    1/1     Running   0          44m
	pod/coredns-f9fd979d6-kht96                    1/1     Running   0          44m
	pod/etcd-master1                               1/1     Running   0          44m
	pod/kube-apiserver-master1                     1/1     Running   0          44m
	pod/kube-controller-manager-master1            1/1     Running   0          44m
	pod/kube-flannel-ds-c27nb                      1/1     Running   0          38m
	pod/kube-flannel-ds-zpbkr                      1/1     Running   0          38m
	pod/kube-proxy-dxnck                           1/1     Running   0          44m
	pod/kube-proxy-hl62l                           1/1     Running   0          38m
	pod/kube-scheduler-master1                     1/1     Running   0          44m
	pod/openstack-cloud-controller-manager-9c2pp   0/1     Error     1          34s
		
(this launched obviously failed).

When the launch succeeds, you can test it by creating a LoadBalancer service.
Alternatively, install the [Cinder CSI plugin](#cinder).

### Troubleshooting tips

In case the cloud controller manager pod is not in state *Running* after a short
while, you need to find out what's wrong. 
*cloud.conf* might be incorrect, the secret name might be inconsistent with the cloud controller manaager manifest, the cloud controller manager might have trouble connecting
to the cloud or authenticating with it. For more information, check the
pod's logs.

    $ kubectl -n kube-system logs pod/openstack-cloud-controller-manager-9c2pp
	...
	... openstack.go:300] failed to read config: 10:11: illegal character U+003A ':'
	... controllermanager.go:131] Cloud provider could not be initialized: could not init cloud provider "openstack": 10:11: illegal character U+003A ':'
	
In this example, *cloud.conf* contained a colon instead of an equal sign
in line 10. This was fixed by removing the secret, correcting *cloud.conf*,
recreating the secret and starting a new daemonset:

    $ kubectl -n kube-system delete secret cloud-config
	$ kubectl create secret -n kube-system generic cloud-config --from-file=cloud.conf
	$ kubectl -n kube-system delete daemonset.apps/openstack-cloud-controller-manager
	# wait a moment for this to settle...
	$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/cloud-provider-openstack/master/manifests/controller-manager/openstack-cloud-controller-manager-ds.yaml

Should the logs not have sufficient information, increase the log level. This is
done with the *--v* option in the daemonset manifest. A verbosity level of 6
includes details of the requests made to the OpenStack cloud and is very useful
in case authentication or other cloud operations fail. Copy the manifest to the
master, replace *--v=1* with *--v=6* and reapply the manifest.

Installing the CSI Cinder plugin<a name="cinder" />)
--------------------------------

The CSI (cloud storage interface) for Cinder allows creating persistent volumes and persistent 
volume claims backed by Cinder volumes. The following instructions are based on the 
[OpenStack Cloud Provider documentation](https://github.com/kubernetes/cloud-provider-openstack/blob/master/docs/using-cinder-csi-plugin.md#using-the-manifests).

Copy the original [Cinder CSI manifests](https://github.com/kubernetes/cloud-provider-openstack/tree/release-1.19/manifests/cinder-csi-plugin) 
to a directory **on the master**. You can either download file by file or, perhaps better, simply 
download the entire repo as a ZIP file (about 0.5MB) or by cloning it. 

Don't copy `csi-secret-cinderplugin.yaml` (or remove it), 
since the cloud config secret exists already.

    $ cd
    $ mkdir manifests
    $ wget https://github.com/kubernetes/cloud-provider-openstack/archive/release-1.19.zip
    $ unzip release-1.19.zip
    $ cd cloud-provider-openstack-release-1.19/manifests/cinder-csi-plugin
    $ cp cinder* csi-cinder-driver.yaml ~/manifests/

Go to that directory.
If you want to increase containers' logging level, add the *--v=6* option to all containers in the 
controllerplugin and nodeplugin manifests. This option generates a lot of log 
messages, including details of the APIs that the plugin issues to the OpenStack cloud.

Apply all manifests. This will create the necessary RBAC roles and launch 
the controller plugin, node plugin and Cinder driver.

    $ cd ~/manifests
    $ kubectl apply -f .

Confirm that all pods are up and running. In case they are not, see the 
troubleshooting section above.

	$ kubectl get pod -n kube-system
	NAME                                       READY   STATUS    RESTARTS   AGE
	coredns-f9fd979d6-hwmpf                    1/1     Running   0          6h13m
	coredns-f9fd979d6-kht96                    1/1     Running   0          6h13m
	csi-cinder-controllerplugin-0              5/5     Running   0          7m12s
	csi-cinder-nodeplugin-vrczm                2/2     Running   0          7m11s
	etcd-master1                               1/1     Running   0          6h14m
	kube-apiserver-master1                     1/1     Running   0          6h14m
	kube-controller-manager-master1            1/1     Running   0          6h14m
	kube-flannel-ds-c27nb                      1/1     Running   0          6h7m
	kube-flannel-ds-zpbkr                      1/1     Running   0          6h8m
	kube-proxy-dxnck                           1/1     Running   0          6h13m
	kube-proxy-hl62l                           1/1     Running   0          6h7m
	kube-scheduler-master1                     1/1     Running   0          6h14m
	openstack-cloud-controller-manager-t8kfj   1/1     Running   0          5h10m
		

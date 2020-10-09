Deploying applications to test the OpenStack plugins
====================================================

You have set up a Devstack cloud, created two instances (*master* and *worker*)
and deployed a Kubernetes cluster on them. You then added the OpenStack cloud 
provider and the Cinder CSI plugin to that cloud.

It's time to use the cluster. You will:
- [create a simple app that uses Cinder volumes](#volumes)
- [create a simple app that uses the load balancer](#lb)
- [create a slightly more complex app that uses both Openstack services](#complex)

Creating a simple app that uses Cinder volumes<a name="volumes" />
----------------------------------------------
To use Cinder volumes, you need to define a storage class that maps to Cinder.
This is done by referencing the Cinder CSI driver as provider in the storage
class definition.

What is the name of the Cinder CSI driver? It is defined in the
csi-cinder-driver manifest:

	$ cat csi-cinder-driver.yaml
	apiVersion: storage.k8s.io/v1
	kind: CSIDriver
	metadata:
	  name: cinder.csi.openstack.org
	spec:
	  attachRequired: true
	  podInfoOnMount: true
	  volumeLifecycleModes:
	  - Persistent
	  - Ephemeral

The driver is named cinder.csi.openstack.org.

You can also check the currently installed CSI drivers:

	$ kubectl get csidrivers.storage.k8s.io
	NAME                       ATTACHREQUIRED   PODINFOONMOUNT   MODES                  AGE
	cinder.csi.openstack.org   true             true             Persistent,Ephemeral   2d20h

Three manifests, almost unchanged from the [Kubernetes
blog](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm/#deploy-cinder-csi), define the test application: A storageclass definition, a PVC, and NGINX. The storage class is linked to the CSI driver via its *provisioner* key:

	$ cat cinder-storageclass.yaml
	apiVersion: storage.k8s.io/v1
	kind: StorageClass
	metadata:
	  name: csi-sc-cinderplugin
	provisioner: cinder.csi.openstack.org

Copy the three manifests to a directory. First, apply the two storage
manifests.

    $ kubectl apply -f cinder-storageclass.yaml
    $ kubectl apply -f cinder-pvc-claim1.yaml

If everything is configured correctly, the PVC should be backed by a Cinder
volume. On the Devstack server, check the volumes.

	$ source ~/devstack/openrc kube kube
	$ openstack volume list -f yaml
	- Attached to: []
	  ID: 1edb1b91-6fdc-4f20-8ead-283aaf878390
	  Name: pvc-a0c8e55f-f766-44bd-80a5-ff2832e4365f
	  Size: 1
	  Status: available

The PVC corresponds to a Cinder volume that is currently available, i.e. not
attached to any server.

Go back to *master1* and launch the application.

	$ kubectl apply -f example-pod.yaml
	$ kubectl get rc,pod,pvc
	NAME                           DESIRED   CURRENT   READY   AGE
	replicationcontroller/server   4         4         4       106s

	NAME               READY   STATUS    RESTARTS   AGE
	pod/server-bnwd7   1/1     Running   0          105s
	pod/server-jklpp   1/1     Running   0          105s
	pod/server-kj26p   1/1     Running   0          106s
	pod/server-r4mqd   1/1     Running   0          105s

	NAME                           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS          AGE
	persistentvolumeclaim/claim1   Bound    pvc-a0c8e55f-f766-44bd-80a5-ff2832e4365f   1Gi        RWO            csi-sc-cinderplugin   7m48s
		
**On the Devstack server**, list the volume again. You will find that the
volume status has changed from *available* to *in-use*, and that it is attached to the *worker1* instance. 

**On the worker1 server**, verify that the volume is attached and mounted.

	[centos@worker1 ~]$ lsblk --ascii
	NAME   MAJ:MIN RM SIZE RO TYPE MOUNTPOINT
	vda    252:0    0  20G  0 disk
	`-vda1 252:1    0  20G  0 part /
	vdb    252:16   0   1G  0 disk /var/lib/kubelet/pods/de103e52-227b-4117-b1b6-647c68507127/volumes/kubernetes.io~cs
	[centos@worker1 ~]$ sudo blkid
	/dev/vda1: UUID="6cd50e51-cfc6-40b9-9ec5-f32fa2e4ff02" TYPE="xfs"
	/dev/vdb: UUID="028085bf-2dd1-47c0-ab2a-e925a4150c36" TYPE="ext4"

The volume is known as vdb and mounted to a kubelet directory.

Multi-attach volumes<a name="#multiattach" />
--------------------

By default, Cinder volumes can only be attached to one OpenStack instance. Right now, the PVC is attached to worker1. This
section explores what happens if pods run on other instances, and how we can ensure that volumes can be mounted to more
than one Kubernetes node.

### Remove the NoSchedule taint from master1

The master1 node's NoSchedule taint prevents it from running pods:

    $ kubectl describe no master1 
    ...
    Taints:             node-role.kubernetes.io/master:NoSchedule
    ...

Remove this taint so that pods can be scheduled there.

    $ kubectl taint nodes master1 node-role.kubernetes.io/master:NoSchedule-

The dash at the end of the command is significant. Use `kubectl describe` again 
to double-check that the taint has been removed.

### Add pods and check their health

In example-pod.yaml, set the replica number from 4 to 8, 
then apply the updated manifest. List the pods.

$ kubectl get pods -o wide
NAME           READY   STATUS              RESTARTS   AGE     IP            NODE      NOMINATED NODE   READINESS GATES
server-8swjk   0/1     ContainerCreating   0          7s      <none>        master1   <none>           <none>
server-bnwd7   1/1     Running             0          3h21m   10.244.1.30   worker1   <none>           <none>
server-j8mnp   0/1     ContainerCreating   0          7s      <none>        master1   <none>           <none>

After a minute or so, check again. You will find that the status for the new pods remains *ContainerCreating*.
When you describe one of these pods, you will find that their creation can't be completed because the volume can't be
attached and therefore not mounted:

	$ kubectl describe pod server-vl8cl
	...
	Events:
	  Type     Reason              Age                  From                     Message
	  ----     ------              ----                 ----                     -------
	  Normal   Scheduled           15m                  default-scheduler        Successfully assigned default/server-vl8cl to master1
	  Warning  FailedAttachVolume  15m                  attachdetach-controller  Multi-Attach error for volume "pvc-a0c8e55f-f766-44bd-80a5-ff2832e4365f" Volume is already used by pod(s) server-bnwd7, server-jklpp, server-kj26p, server-r4mqd
	  Warning  FailedMount         2m16s (x6 over 13m)  kubelet                  Unable to attach or mount volumes: unmounted volumes=[cinderpvc], unattached volumes=[cinderpvc default-token-9tnjm]: timed out waiting for the condition

This is so because Cinder doesn't allow *master1* to attach a volume that is already attached to *worker1*. To attach a
Cinder volume to several instances, its *multiattach* flag must be set. The Cinder CSI driver achieves this by an option
in the storage class.

Delete the replicaset, PVC and storage class. 

### Multi-attach storage class

To attach a Cinder volume to more than one instance, it must have a multi-attach volume type. No such type exists right
now, so that you have to create one first. See the [Cinder admin guide](https://docs.openstack.org/cinder/latest/admin/blockstorage-volume-multiattach.html) for more information.

**On the Devstack server**:

    $ source ~/devstack/openrc admin admin
	$ openstack volume type create multiattach-type --property multiattach="<is> True"

The T in True must be upper-case. 

Then, **on the master1 server**, modify the storage class manifest by adding 
the new volume type as a parameter:

	apiVersion: storage.k8s.io/v1
	kind: StorageClass
	metadata:
	  name: csi-sc-cinderplugin
	provisioner: cinder.csi.openstack.org
	parameters:
	  type: multiattach-type

Also set the accessMode in the cinder-pvc-claim1.yaml manifest to *ReadWriteMany*.

Create the storage class and the PVC.

    $ kubectl apply -f cinder-storageclass.yaml
    $ kubectl apply -f cinder-pvc-claim1.yaml

**On the Devstack server**, verify that a Cinder volume has been created 
and that it has the multiattach flag.

    $ openstack volume list --all-projects
	+--------------------------------------+------------------------------------------+-----------+------+-------------+
	| ID                                   | Name                                     | Status    | Size | Attached to |
	+--------------------------------------+------------------------------------------+-----------+------+-------------+
	| 73c3e003-c535-42e1-8c4a-a1f9379ffba6 | pvc-6d770b8d-fc35-4f8d-800d-0ec8925f58d6 | available |    1 |             |
	+--------------------------------------+------------------------------------------+-----------+------+-------------+
	$ openstack volume show 73c3e003-c535-42e1-8c4a-a1f9379ffba6 | grep multi
	| multiattach                  | True                                          |
	| type                         | multiattach-type                              |
    
### Run the pods and check their health

$ kubectl apply -f example-pod.yaml
replicationcontroller/server created
$ kubectl get pod -o wide
NAME           READY   STATUS              RESTARTS   AGE   IP       NODE      NOMINATED NODE   READINESS GATES
server-5m8bg   0/1     ContainerCreating   0          13s   <none>   master1   <none>           <none>
server-9djx2   0/1     ContainerCreating   0          13s   <none>   master1   <none>           <none>
...

When you repeat the command after a while, all pods should be in status Running.

**On the Devstack server**, list the volumes.

	$ openstack volume list --fit-width
	+----------------------+----------------------+--------+------+-----------------------+
	| ID                   | Name                 | Status | Size | Attached to           |
	+----------------------+----------------------+--------+------+-----------------------+
	| 66ea38fd-4d08-4afa-  | pvc-37ab30fb-c27c-4e | in-use |    1 | Attached to worker1   |
	| ae3b-fa477cf4b26a    | 86-a067-81b0e0353fe1 |        |      | on /dev/vdb Attached  |
	|                      |                      |        |      | to master1 on         |
	|                      |                      |        |      | /dev/vdb              |
	+----------------------+----------------------+--------+------+-----------------------+

The *Attached to* column shows that the Cinder volume is attached to the two nodes.

Creating a simple app that uses load balancing<a name="lb" />
----------------------------------------------


Creating a complex app that uses the OpenStack Load Balancer and Cinder volumes<a name="complex" />
-------------------------------------------------------------------------------



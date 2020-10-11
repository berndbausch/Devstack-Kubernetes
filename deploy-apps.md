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

By default, Cinder volumes can only be attached to one OpenStack instance. 
Right now, the PVC is attached to worker1 only. 

This section explores pods on multiple instances sharing a volume, 
and what changes are necessary for this to work. We will:

1. allow pods to be scheduled on the controller
2. fail deploying pods on both nodes
3. add a Cinder volume type
4. change the storage class manifest 
5. make the PVC *ReadWriteMany*.
6. succeed deploying pods on both nodes

### 1. Remove the NoSchedule taint from master1

We want to run pods on the master1 node, but right now its NoSchedule taint 
makes this impossible:

    $ kubectl describe no master1 
    ...
    Taints:             node-role.kubernetes.io/master:NoSchedule
    ...

Remove this taint so that pods can be scheduled there.

    $ kubectl taint nodes master1 node-role.kubernetes.io/master:NoSchedule-

The dash at the end of the command is significant. Use `kubectl describe` again 
to double-check that the taint has been removed.

### 2. Add pods to the controller and check their health

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

This is so because *master1* can't attach a volume that is already attached 
to *worker1*. To attach a
Cinder volume to several instances, its *multiattach* flag must be set. 

Before setting up a storage class that allows multi-attachment, 
delete the replicaset, PVC and storage class. 

### 3. Create a Cinder volume type that allows multi-attachment

To attach a Cinder volume to more than one instance, it must have a 
multi-attach volume type. No such type exists right
now, so that you have to create one first. See the [Cinder admin guide](https://docs.openstack.org/cinder/latest/admin/blockstorage-volume-multiattach.html) for more information.

**On the Devstack server**:

    $ source ~/devstack/openrc admin admin
	$ openstack volume type create multiattach-type --property multiattach="<is> True"

The T in True must be upper-case. 

### 4. Add the new volume type to the Kubernetes storage class

**On the master1 server**, modify the **storage class** manifest by adding 
the new volume type as a parameter:

	apiVersion: storage.k8s.io/v1
	kind: StorageClass
	metadata:
	  name: csi-sc-cinderplugin
	provisioner: cinder.csi.openstack.org
	parameters:
	  type: multiattach-type

### 5. Change the PVC's access mode and recreate the PVC

Also modify the **PVC manifest** and set its accessMode to *ReadWriteMany*.

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
    
### 6. Run the pods and check their health

	$ kubectl apply -f example-pod.yaml
	replicationcontroller/server created
	$ kubectl get pod -o wide
	NAME           READY   STATUS              RESTARTS   AGE   IP       NODE      NOMINATED NODE   READINESS GATES
	server-5m8bg   0/1     ContainerCreating   0          13s   <none>   master1   <none>           <none>
	server-9djx2   0/1     ContainerCreating   0          13s   <none>   master1   <none>           <none>
	...

When you repeat the command after a while, all pods should be in status 
*Running*.

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

To demonstrate load balancing, pods need to run at two or more nodes. 
See the [instructions](#multiattach) in the
previous section for enabling pod scheduling on the controller.

### Create new manifests

Create a **new replication controller manifest** that uses container-local
storage instead of a volume:

	$ cat example-pod-lb.yaml
	apiVersion: v1
	kind: ReplicationController
	metadata:
	  name: lbserver
	spec:
	  replicas: 8
	  selector:
		role: server
	  template:
		metadata:
		  labels:
			role: server
			app: lbserver
		spec:
		  containers:
		  - name: server
			image: nginx

This manifest differs from the original in two points: Pods have an additional label 
`app: lbserver`, and there is no volume.

Create a **service manifest** named *service.yaml*. 
Ensure that its selector refers to the replication controller via the above label:

	kind: Service
	apiVersion: v1
	metadata:
	  name: lb-webserver
	spec:
	  selector:
		app: lbserver
	  type: LoadBalancer
	  ports:
	  - name: http
		port: 80
		targetPort: 80

Apply the two manifests. 

### Explore OpenStack resources

The OpenStack cloud provider will create a
load balancer, which may take a few minutes. Most of that time will be spend launching a new
instance, which runs the load balancing code. **On the Devstack server**, explore the OpenStack 
load balancer. The following command uses YAML as output format for prettier output.

	$ openstack loadbalancer list -f yaml
	- id: 474f2c35-1d45-4b49-99ba-d745082e9d33
	  name: kube_service_kubernetes_default_lb-webserver
	  operating_status: OFFLINE
	  project_id: 7a099eff1fb1479b89fa721da3e1a018
	  provider: amphora
	  provisioning_status: PENDING_CREATE
	  vip_address: 172.16.0.134

The provisioning status will become ACTIVE when the load balancer instance is up and running.
You can view the load balancer instance after changing your identity to admin:

    $ source ~/devstack/openrc admin admin
	$ openstack server list

A useful command for load balancer details is 
`openstack loadbalancer status show <LOADBALANCER-ID>`.

The cloud provider associates a floating IP with the load balancer's VIP address. 
You can view it with
`openstack floating ip list | grep 172.16.0.134`, where 172.16.0.134 is the VIP address.

### Test the loadbalancer

**On master1**, the floating IP is used as the service's external IP:

	$ kubectl get service
	NAME           TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)        AGE
	kubernetes     ClusterIP      10.96.0.1     <none>          443/TCP        4d2h
	lb-webserver   LoadBalancer   10.97.192.7   192.168.1.225   80:30007/TCP   34m

The pods you just launched contain an NGINX web server with a default index.html page. You can
access the web server with curl <EXTERNAL-IP>, but this doesn't prove to you that more than one
pod is used. 

Create a different index.html for each pod. For example:

	$ for pod in $LIST_OF_PODS
	do 
		kubectl exec $i -- /bin/bash -c "echo Server $server > /usr/share/nginx/html/index.html"; server=$((server+1))
	done

This script replaces index.html in each pod with a customized string.

Test this by repeatedly running the above curl command. You should see how the different pods
respond.

    $ curl 192.168.1.225
	Server 7
    $ curl 192.168.1.225
	Server 5
    $ curl 192.168.1.225
	Server 4
    $ curl 192.168.1.225
	Server 4
    $ curl 192.168.1.225
	Server 5

Creating a complex app that uses the OpenStack Load Balancer and Cinder volumes<a name="complex" />
-------------------------------------------------------------------------------



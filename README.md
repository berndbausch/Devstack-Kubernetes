Running a Kubernetes cluster on Devstack
========================================

[Devstack](http://docs.openstack.org/devstack) is a simple OpenStack deployment tool. 
Its main purpose is setting up testing 
platforms in OpenStack's CI environment, but it is also very popular as a comparatively simple 
method for creating proof-of-concept clouds, or clouds for experimenting with OpenStack. 
Devstack can create comparatively lean clouds that don't require tens of gigabytes of RAM 
and storage.

This repo is a collection of instructions, scripts and configuration files for creating 
a single-server Devstack cloud that demonstrates Kubernetes clusters on OpenStack. 

It covers two methods of deploying a cluster: Manual via kubeadm, and semiautomatic via 
OpenStack Magnum. Apart from the standard
OpenStack services, it deploys OpenStack's loadbalancer service Octavia, the Kubernetes 
cluster manager Magnum, and the Octavia and Magnum GUIs.
By default, Devstack clouds use an isolated network, and Devstack servers are not meant to be 
rebooted. These instructions connect the cloud to the external network in your home or lab 
and include a script that permits rebooting the server.

The instructions are structured as follows:

1. [Setting up Devstack](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/devstack-setup.md)
2. [Creating a Kubernetes cluster with OpenStack cloud provider and the CSI Cinder plugin](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/k8s-manual-setup.md)
3. [Deploying a load-balanced application with Cinder volumes on the cluster](https://github.com/berndbausch/Devstack-Kubernetes/blob/main/deploy-apps.md)
4. Creating a Kubernetes cluster using the OpenStack Magnum service
5. Deploying an application on the Magnum-managed Kubernetes cluster
	
The first three steps are based on the official 
[K8s OpenStack cloud provider documentation](https://github.com/kubernetes/cloud-provider-openstack) 
and a [blog entry on kubernetes.io](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm) 
that covers K8s-OpenStack integration.

Instructions, configurations and manifests were tested on a moderately sized Devstack server 
running Ubuntu 18.04, with 15GB of RAM and six virtual CPUs. It should be feasible on less 
RAM (12GB perhaps?), and half the CPUs should not be a problem.

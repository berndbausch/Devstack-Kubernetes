# Devstack-Kubernetes
## Making Devstack ready for running Kubernetes clusters.

Devstack main role is to be a testing platform in OpenStack's CI environment. It is also very popular as a comparatively simple OpenStack cloud deployment tool and can be used to create fairly lean clouds that don't required tens of gigabytes of RAM and storage.

Unfortunately, it is not well documented and is not meant to be rebooted. This repo is a collection of scripts and configuration files for creating a single-server Devstack cloud that demonstrates Kubernetes clusters on OpenStack. OpenStack services include Octavia, Magnum, and the Octavia and Magnum GUIs. Thanks to a Netplan configuration file and a script, the cloud can be made ready after rebooting the server. 

This cloud can then be used to create **Kubernetes clusters with Magnum**. The repo has configurations and commands for setting up such clusters, and for running containerized applications behind LoadBalancer services.

The repo also includes instructions for **manually setting up and testing a Kubernetes cluster** including **Cinder plugin** and **LoadBalancer services**, as well as the Kubernetes manifests that are required. Instructions are based on the official [K8s OpenStack cloud provider documentation](https://github.com/kubernetes/cloud-provider-openstack) and a [blog entry on kubernetes.io](https://kubernetes.io/blog/2020/02/07/deploying-external-openstack-cloud-provider-with-kubeadm) that covers K8s-OpenStack integration.

Instructions, configurations and manifests were tested on a moderately sized Devstack server running Ubuntu 18.04, with 15GB of RAM and six virtual CPUs. It should be feasible on less RAM (12GB perhaps?), and half the CPUs should not be a problem.

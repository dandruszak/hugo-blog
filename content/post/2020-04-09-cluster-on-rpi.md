---
title: "Building a Kubernetes cluster of Raspberry Pi running Ubuntu server"
date: 2020-04-09
draft: false 
hero: "./images/post/2020-04/k8s-rpi-1.jpeg"
authors:
  - Jakub Czaplinski
tags:
  - Kubernetes
  - Raspberry Pi
  - Ubuntu
  - Edge Computing
  - Tutorial
---

In this article I will show how to set up a small Kubernetes cluster running on one or more Raspberry Pi 3/4 running Ubuntu 18.04. I chose Ubuntu server because it comes with 64bit and 32bit versions and I needed both type of nodes for my home cluster.

## Why should anyone bother?

With low-energy consumption, Raspberry Pi is a perfect candidate for a machine that will run 24/7. When learning or developing for Kubernetes sometimes a persistent environment is a time saver. K3s, on the other hand, is a smaller, easier to set up flavor of Kubernetes that is fully compatible, but stripped down from unneeded features that are behind feature gates and by default disabled on most of the installations.

## Who is it for?

This tutorial does not require any practical experience with Kubernetes or its installation process. It is written in a way that someone who is starting their adventure with Kubernetes should be able to deploy it and start learning.

## What do we need

To do everything shown in this tutorial you will need:

- 1 or 2 Raspberry Pi (version 3 or 4)
- 1 or 2 micro SD cards — the faster the better
- Power supplies for the Raspberry Pi
- Software for writing disk images — more information can be found [here](https://ubuntu.com/tutorials/tutorial-create-a-usb-stick-on-ubuntu#1-overview)
- Ubuntu Raspberry Pi images found [here](https://ubuntu.com/download/raspberry-pi)
- K3sup — a great tool for simplifying installation of K3s — you can find it [here](https://github.com/alexellis/k3sup)
- 30 minutes of your precious time
- Coffee or other drink

## Plan

What we will do — with optional steps:

- Prepare SD cards and SSH keys
- Setup Ubuntu server 18.04 for K3s installation
- Disable unnecessary services (optional)
- Bootstrap K3s cluster
- Join second node (optional)
- Test K3s cluster
- Dance the “victory dance” (optional)

## Preparing for the installation
{{<post_image src="./images/post/2020-04/k8s-rpi-2.jpeg" caption="Installing Ubuntu server on SD card">}}

Before we begin the installation we need two things. First, we need to prepare SD cards with Ubuntu server 18.04. The images can be downloaded from here. Instructions on how to prepare a bootable SD card from those images can be found [here](https://ubuntu.com/tutorials/tutorial-create-a-usb-stick-on-ubuntu#1-overview).

Next, we need to create SSH keys for k3sup, so we’ll be able to install K3s on a Raspberry Pi node. If you have your own SSH keys, you can skip this step. To create SSH keys run the following:

```shell script
ssh-keygen -t rsa -b 4096 -f ~/.ssh/rpi -P ""
```

and add it to ssh key agent

```shell script
ssh-add ~/.ssh/rpi
```

## Installation
{{<post_image src="./images/post/2020-04/k8s-rpi-3.jpeg" caption="Installing stuff on Raspberry Pi">}}

After booting up your Raspberry Pi with the fresh Ubuntu installation, you have to check its IP address. You can do that by logging to your router and checking the DHCP settings for a new lease for a hostname “ubuntu”. You can also do it the old fashion way — connect keyboard and monitor to your Raspberry Pi and log into the machine. Both the username and login is **ubuntu** — after logging in you will have to immediately change your password and log once again. Once you’re there run

```shell script
ip addr show eth0
```

And you should see something like this:

```shell script
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether dc:a6:32:76:1b:91 brd ff:ff:ff:ff:ff:ff
    inet 192.168.0.238/24 brd 192.168.0.255 scope global dynamic eth0
       valid_lft 329sec preferred_lft 329sec
    inet6 fe80::dea6:32ff:fe76:1b91/64 scope link 
       valid_lft forever preferred_lft forev
```

OK, from now we can remotely log in to the machine and the keyboard and monitor won’t be necessary.

Let’s log into the machine by running

```shell script
ssh ubuntu@192.168.0.238
```

If you did not log in before you will have to change your password.

Let’s log out and copy the SSH keys, so we won’t have to use the password for every login — also for **k3sup** to be able to deploy the Kubernetes cluster. To copy the SSH keys to the machine run the following

```shell script
ssh-copy-id -i .ssh/rpi ubuntu@192.168.0.238
```

You should be prompted for password and after successful login you should see something like this

```shell script
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: ".ssh/rpi.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
ubuntu@192.168.0.238's password: Number of key(s) added: 1Now try logging into the machine, with:   "ssh 'ubuntu@192.168.0.238'"
and check to make sure that only the key(s) you wanted were added.
```

Now we can SSH into the Raspberry Pi and finish the system installation.

Let’s check how much resources are used by the system

```shell script
ubuntu@ubuntu:~$ free -m 
              total        used        free      shared  buff/cache   available
Mem:           3791         183        2369           6        1238        3552
Swap:             0           0           0
ubuntu@ubuntu:~$ vmstat 1
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  0      0 2426232  77056 1191676    0    0    81   261  182  192 10  5 84  2  0
 0  0      0 2426232  77056 1191704    0    0     0     0   53   48  0  0 100  0  0
 0  0      0 2426232  77056 1191704    0    0     0     0   46   44  0  0 100  0  0
 0  0      0 2426232  77056 1191704    0    0     0     0   57   59  0  0 100  0  0
 0  0      0 2426232  77064 1191696    0    0     0    28   62   70  0  0 100  0  0
 0  0      0 2426264  77064 1191712    0    0     0     0   53   57  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0     0   64   75  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0     0   49   47  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0     0   48   47  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0    20   48   49  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0     0   71   73  0  0 100  0  0
 0  0      0 2426232  77064 1191712    0    0     0     0   48   48  0  0 100  0  0
```

As we can see, the base resource utilization is very low and the Raspberry Pi has quite a bit to offer :)

Let’s do a quick system update and then make one necessary change so that Kubernetes will work on this machine.

```shell script
sudo apt-get update
sudo apt-get upgrade -y
```

Now let’s edit the boot options **/boot/firmware/nobtcmd.txt** and add **cgroup_memory=1 cgroup_enable=memory** to the end of the line so that file will look like this

```shell script
ubuntu@ubuntu:~$ cat /boot/firmware/nobtcmd.txt 
net.ifnames=0 dwc_otg.lpm_enable=0 console=ttyAMA0,115200 console=tty1 root=LABEL=writable rootfstype=ext4 elevator=deadline rootwait fixrtc cgroup_memory=1 cgroup_enable=memory
```

If you skip this part. K3s will fail after bootstrapping the cluster and you will be able to find something along those lines in the logs:

```shell script
Apr  4 20:22:27 rpi-master k3s[2204]: time="2020-04-04T20:22:27.635180523Z" level=error msg="Failed to find memory cgroup, you may need to add \\"cgroup_memory=1 cgroup_enable=memory\\" to your linux cmdline (/boot/cmdline.txt on a Raspberry Pi)"

```

however, on ubuntu it’s actually the **nobtmcd.txt** file.

Now, we need to ensure that the Raspberry Pi has a static IP. This is important for both the master and all the additional nodes. If you have access and know how, you can just set the IP on your router to be static, so that after every reboot the machine will always get the same IP. Alternatively, we can set up our Ubuntu to have a static IP. To do this, we need to edit the file **/etc/netplan/50-cloud-init.yaml** to look like this:

```shell script
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
     dhcp4: no
     addresses: [192.168.0.120/24]
     gateway4: 192.168.0.1
     nameservers:
       addresses: [8.8.8.8,8.8.4.4]

```

More information about this topic can be found [here](https://linuxconfig.org/how-to-configure-static-ip-address-on-ubuntu-18-04-bionic-beaver-linux)

Last thing to do — set up a unique and friendly hostname, as “ubuntu” will be too generic — especially when we will have more than 1 node. To do so, edit the **/etc/hostname** and set the name to your liking. I chose **rpi-master** for my master node.

This is it for the installation, you can repeat this process on a second node. I’ve set up my second Raspberry Pi with the IP **192.168.0.121** and hostname **rpi-worker-1**

## Optimizations (optional)

As I dislike having anything unnecessary running in my system — and also I will run many tests and benchmarks on my cluster — I prefer not to have time-based actions or system updates done automatically. Because of that, I prefer to remove almost every service from the system.

To disable all the services that are not needed for running k3s run the following

```shell script
# no WIFI for the server
sudo systemctl disable wpa_supplicant.service
# no time based tasks executed
sudo systemctl disable atd.service
sudo systemctl disable cron
# no restart of services and auto updates - I prefer to run updates myself
sudo systemctl disable unattended-upgrades.service
```

reboot and….

```shell script
ubuntu@rpi-master:~$ free -m 
              total        used        free      shared  buff/cache   available
Mem:           3791         169        3423           6         198        3566
Swap:             0           0           0
```

OK, so we gained 14 MB, and we can be sure that nothing will suddenly run in the background while running tests. As I love to min/max things, I’m happy with the result!


## Bootstrapping the cluster
{{<post_image src="./images/post/2020-04/k8s-rpi-4.jpeg" caption="Bootstrapping the cluster">}}

To bootstrap the K3s cluster run the following command

```shell script
k3sup install --user ubuntu --sudo --ip 192.168.0.120 --ssh-key ~/.ssh/rpi
```

and validate by running

```shell script
export KUBECONFIG=/home/upgrade/kubeconfig
```

Wait 1–5 minutes, depending on your network bandwidth and you should be able to run the same commands and have similar output

```shell script
upgrade@ZeroOne ~ $ kubectl get pod -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   local-path-provisioner-58fb86bdfd-hmcbr   1/1     Running     0          104s
kube-system   metrics-server-6d684c7b5-dl27c            1/1     Running     0          104s
kube-system   coredns-d798c9dd-zhht7                    1/1     Running     0          104s
kube-system   helm-install-traefik-s2hzn                0/1     Completed   2          104s
kube-system   svclb-traefik-4cwg9                       2/2     Running     0          29s
kube-system   traefik-6787cddb4b-kcj9j                  1/1     Running     0          30s
upgrade@ZeroOne ~ $ kubectl  cluster-info 
Kubernetes master is running at <https://192.168.0.120:6443>
CoreDNS is running at <https://192.168.0.120:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy>
Metrics-server is running at <https://192.168.0.120:6443/api/v1/namespaces/kube-system/services/https:metrics-server:/proxy>To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

And the cluster is up and running!

If this is your only cluster, copy the config file to **~/.kube/config** for convenience. You won’t have to export the environment variable **KUBECONFIG** to access this cluster.

As we can see the load on our master node jumped up a bit

```shell script
ubuntu@rpi-master:~$ vmstat 1
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  0      0 2218940  29752 873468    0    0    82   614  978 1593 10  9 76  6  0
 0  0      0 2218688  29752 873496    0    0     0     0 2855 5331  2  3 95  0  0
 0  0      0 2218688  29760 873496    0    0     0    32 2463 4605  1  2 97  0  0
 2  0      0 2217132  29760 873496    0    0     0     0 5417 9919  5 12 83  0  0
 0  0      0 2217964  29760 873496    0    0     0     0 3459 5780  1 20 78  0  0
 0  0      0 2217664  29760 873496    0    0     0     0 3194 5897  3  4 94  0  0
 0  0      0 2218924  29760 873496    0    0     0     0 4327 7566  4 13 83  0  0
 0  0      0 2218672  29768 873496    0    0     0    24 3040 5547  2  3 95  0  0
 1  0      0 2218672  29768 873496    0    0     0     4 2758 5124  2  3 95  0  0
 4  0      0 2218672  29768 873496    0    0     0     0 3057 5681  2  3 95  0  0
 0  0      0 2218704  29768 873496    0    0     0     0 3480 6466  3  3 94  0  0
 0  0      0 2218704  29768 873496    0    0     0     0 3130 5789  2  2 95  0  0
```

But there is still plenty of resources for our apps to use.

We can also verify if Traefik and the service load balancer (which emulates cloud load balancers) are working, by trying to connect to the IP of the cluster master through the browser or by running the following

```shell script
upgrade@ZeroOne ~ $ curl http://192.168.0.120
404 page not found
```

We got a response, so that means the ingress is also working correctly. We just don’t have anything deployed yet, so Traefik does not serve anything.

## Join the node

```shell script
k3sup join --user ubuntu --sudo  --ssh-key ~/.ssh/upgnet/rpi  --server-ip 192.168.0.120  --ip 192.168.0.121
```

wait a couple of seconds and … TADAM!

```shell script
upgrade@ZeroOne ~ $ kubectl get node
NAME           STATUS   ROLES    AGE   VERSION
rpi-master     Ready    master   21m   v1.17.2+k3s1
rpi-worker-1   Ready    <none>   17s   v1.17.2+k3s1
upgrade@ZeroOne ~ $ kubectl top node
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
rpi-master     367m         9%     712Mi           18%       
rpi-worker-1   51m          1%     221Mi           5%
```

If you SSH into the node and run

```shell script
ubuntu@rpi-worker-1:~$ free -m 
              total        used        free      shared  buff/cache   available
Mem:           3822         227        3222          10         372        3546
Swap:             0           0           0
ubuntu@rpi-worker-1:~$ vmstat 1
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 2  0      0 3299888  19420 361952    0    0   193   256  289  390  4  5 90  2  0
 0  0      0 3299660  19420 361980    0    0     0     0  614 1029  1  1 98  0  0
 1  0      0 3299660  19420 361980    0    0     0    16  578  994  1  0 99  0  0
 1  0      0 3299628  19420 361980    0    0     0     0  544  951  0  1 99  0  0
 1  0      0 3299628  19420 361980    0    0     0     0  346  582  0  0 100  0  0
 0  0      0 3299504  19428 361980    0    0     0    12  597 1013  1  1 99  0  0
 0  0      0 3299472  19428 361996    0    0     0     0  530  893  1  0 99  0  0
 0  0      0 3299472  19428 361996    0    0     0     0  986 1721  1  1 98  0  0
 1  0      0 3299220  19428 361996    0    0     0     0 1138 1940  1  2 97  0  0
 1  0      0 3299220  19428 361996    0    0     0     0  718 1249  0  1 99  0  0
 1  0      0 3298968  19428 361996    0    0     0     0  507  844  0  1 99  0  0
```

you will see that the performance hit is mostly on the master. The worker node still has almost all resources available — which is also reflected by the output of the **kubectl top node** command.

## It wasn’t that bad, was it?

Cool! So now we have our Kubernetes cluster with Traefik as Ingress controller, metrics service and a local storage provisioner. And the whole preparation took way longer than the cluster setup itself. Now it’s time to explore Kubernetes with all its glory!

## And for all you UI lovers

If you like UI, especially the console ones, I strongly recommend using K9s that you can find here

Here is the state of the cluster shown in K9s

{{<post_image src="./images/post/2020-04/k8s-rpi-5.png" caption="List of pods in the K9s UI">}}

{{<post_image src="./images/post/2020-04/k8s-rpi-6.png" caption="List of nodes in the K9s UI">}}

## Where do we go from here?

So now you have a complete running Kubernetes cluster, with one or two nodes. Traefik ingress controller is set up so you can deploy any application and use its built-in option to obtain SSL certificates to run it securely even in your home. The metrics service is there, so initial monitoring of your applications is enabled and you can learn a lot about their behaviour in the cluster. You can also start learning Kubernetes and training for the CKAD and CKA certification if you fancy, as you can practice almost everything apart from setting up cluster on this cluster ;) As for me, I’m planning to deploy IceCI to the cluster and start building more applications for the ARM architecture.


Readout:

— Traefik: https://docs.traefik.io/

— K3s: https://k3s.io/

— K3sup: https://github.com/alexellis/k3sup

— K9s: https://github.com/derailed/k9s

— Kubernetes documentation: https://kubernetes.io/docs/setup/

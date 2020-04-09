---
title: "New in Kubernetes 1.18 - kubectl alpha debug"
date: 2020-03-31
draft: false 
hero: "./images/post/2020-03/kubernetes-1.18.png"
excerpt: Is it useful? What problems can it help solve?
authors:
  - Dominik Andruszak
tags:
  - Kubernetes
  - Kubectl
  - Devops
  - Minikube
  - Containers
---

Kubernetes 1.18 has just landed and, as always, a couple of existing features got stabilized and a couple of new ones have been introduced. Let's take gander at one of the newest additions - `kubectl alpha debug`. This nifty `kubectl` feature gives you an additional tool for debugging pods when `kubectl exec` just doesn't cut it. Most probably your application-hosting containers won't have all the necessary debugging tools - they might not even have a shell. The `kubectl alpha debug` feature allows you to create a temporary container inside your pod - and that container can contain all the tools that you need.

## So.. how does it work?

`kubectl alpha debug` utilizes ephemeral containers - a kind of temporary container that can be added while the pod is running. Ephemeral containers are built for debugging purposes only - they have a stripped down spec compared to base pod containers and they're not really suitable for hosting applications. The feature is still in alpha and has to be enabled through a feature gate. You can read more about ephemeral containers in the Kubernetes [documentation](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers).

## How do I get in?

First, we have to make sure that we have version 1.18 for both the Kubernetes server and client. Even though ephemeral containers were introduced in Kubernetes 1.16, using `kubectl` 1.18 with Kubernetes 1.16 didn't seem to work properly in my cluster.

```shell script
$ kubectl version
Client Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.0", GitCommit:"9e991415386e4cf155a24b1da15becaa390438d8", GitTreeState:"clean", BuildDate:"2020-03-25T14:58:59Z", GoVersion:"go1.13.8", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"18", GitVersion:"v1.18.0", GitCommit:"9e991415386e4cf155a24b1da15becaa390438d8", GitTreeState:"clean", BuildDate:"2020-03-25T14:50:46Z", GoVersion:"go1.13.8", Compiler:"gc", Platform:"linux/amd64"}
```

We also have to enable ephemeral containers through a feature gate - in my examples, I'll be using Minikube.

```shell script
$ minikube config set feature-gates EphemeralContainers=true
❗  These changes will take effect upon a minikube delete and then a minikube start
```

Once the Minikube cluster is recreated, we're pretty much good to go. Let's create a simple pod and see what can we do.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: simple
spec:
  containers:
  - image: alpine
    name: simple
    command:
    - "/bin/sh"
    - "-c"
    - "sleep 5000"
```

Save the file as `simple.yaml` and create the pod inside the cluster.

```shell script
$ kubectl apply -f simple.yaml 
pod/simple created
```

Once the pod is up and running we can hop into it using the debug command. Please remember that the container image might have to download and the whole command might seem stuck for a while (there's no visible indication of the download happening)

```shell script
$ kubectl alpha debug -it simple --image=ubuntu --target=simple --container=debug 
If you don't see a command prompt, try pressing enter. 
root@simple:/#
```

Let's go through the parameters that we've passed to this command:
- `-it` might look familliar and for a good reason - those two parameters are responsible for keeping the stdin open and allocating a TTY
- `--image` is the name of an image for the ephemeral container - it doesn't have to match the main container's image; in this example we're using `ubuntu` even though the main container is running `alpine`
- `--container` is the name of the ephemeral container itself
- `--target` lets the ephemeral container share a process namespace with a container inside the pod - we'll get back to that in a second

Those params are also reflected in the updated spec of the simple pod in the cluster (the output is trimmed to just show the interesting part)

```shell script
$ kubectl get pod simple -o yaml
```

```yaml
ephemeralContainers:
  - image: ubuntu
    imagePullPolicy: IfNotPresent
    name: debug
    resources: {}
    stdin: true
    targetContainerName: simple
    terminationMessagePolicy: File
    tty: true
```

## What's in the box?

Since we're attached to the debug container, let's have a look around.

```shell script
root@simple:/# pwd
/

root@simple:/# ls
bin   dev  home  lib64  mnt  proc  run   srv  tmp  var
boot  etc  lib   media  opt  root  sbin  sys  usr

root@simple:/# whoami
root

root@simple:/# cat /etc/*-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=18.04
DISTRIB_CODENAME=bionic
DISTRIB_DESCRIPTION="Ubuntu 18.04.4 LTS"
NAME="Ubuntu"
VERSION="18.04.4 LTS (Bionic Beaver)"
ID=ubuntu
ID_LIKE=debian
PRETTY_NAME="Ubuntu 18.04.4 LTS"
VERSION_ID="18.04"
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
VERSION_CODENAME=bionic
UBUNTU_CODENAME=bionic
```

We've added a new `ubuntu` container to an existing pod (which was already running an `alpine` container) on the fly, pretty neat! So what can we do now? Well, for example, we can install and use tools like `nslookup` to debug and verify the pod networking and network policies.

```shell script
root@simple:/# apt-get update && apt-get install dnsutils

(...)

root@simple:/# nslookup google.com 
Server:  10.96.0.10 Address: 10.96.0.10#53
Non-authoritative answer:
Name:	google.com
Address: 172.217.16.14
Name:	google.com
Address: 2a00:1450:401b:804::200e
```

What's a bit more interesting - remember that `--target` parameter that we've passed to `kubectl alpha debug`? If we set its value to the name of our main container, it will share its [process namespace](https://kubernetes.io/docs/tasks/configure-pod-container/share-process-namespace/) with the ephemeral container. This means that our `debug` container sees all processes created by `simple`.

```shell script
root@simple:/# ps aux 
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND 
root         1  0.0  0.0   1568     4 ?        Ss   08:47   0:00 sleep 5000 
root         6  0.0  0.0  18504  3500 pts/0    Ss   08:48   0:00 /bin/bash 
root       467  0.0  0.0  34400  2904 pts/0    R+   08:54   0:00 ps aux

root@simple:/# head -n 3 /proc/1/status 
Name: sleep 
Umask: 0022 
State: S (sleeping)
```

Let's try a different pod - a bit more complex this time around.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: complex
spec:
  containers:
  - image: alpine
    name: complex
    env:
    - name: ENV_FIRST
      value: first
    - name: ENV_SECOND
      value: second
    volumeMounts:
    - name: my-volume
      mountPath: /tmp/fromVolume
    command:
    - "/bin/sh"
    - "-c"
    - "echo \"Hello world\" > /tmp/echoed && echo \"Hello volume\" > /tmp/fromVolume/echoed && sleep 5000"
  volumes:
  - name: my-volume
    emptyDir: {}
```

Save it as `complex.yaml` - once it's created, let's jump right into the pod with a new debug container. As before, we can check out the main container processes.

```shell script
$ kubectl apply -f complex.yaml 
pod/complex created

$ kubectl alpha debug -it complex --image=ubuntu --target=complex --container=debug
If you don't see a command prompt, try pressing enter.
root@complex:/# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0   1568     4 ?        Ss   09:06   0:00 sleep 5000
root         6  0.1  0.0  18504  3388 pts/0    Ss   09:06   0:00 /bin/bash
root        16  0.0  0.0  34400  2792 pts/0    R+   09:06   0:00 ps aux
```

We can peek some of the resources used by that process as well, like files - both those created on the container's ephemeral storage, as well as those created on a volume.

```shell script
root@complex:/# head /proc/1/root/tmp/echoed 
Hello world

root@complex:/# head /proc/1/root/tmp/fromVolume/echoed 
Hello volume
```

We can also check out the environment variables - the original output isn't too human-friendly, I've reformatted it here for clarity.

```shell script
root@complex:/# head /proc/1/environ 
KUBERNETES_PORT=tcp://10.96.0.1:443
KUBERNETES_SERVICE_PORT=443
HOSTNAME=complex
ENV_SECOND=second
SHLVL=1
HOME=/root
KUBERNETES_PORT_443_TCP_ADDR=10.96.0.1
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
KUBERNETES_PORT_443_TCP_PORT=443
KUBERNETES_PORT_443_TCP_PROTO=tcp
ENV_FIRST=first
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_PORT_443_TCP=tcp://10.96.0.1:443
KUBERNETES_SERVICE_HOST=10.96.0.1
PWD=/
```

Finally, let's see what happens when the main container inside the pod keeps crashing and restarting - let's simulate this with a simple pod.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: crash
spec:
  containers:
  - image: alpine
    name: crash
    command:
    - "/bin/sh"
    - "-c"
    - "sleep 3 && whatisthis"
```

Save this as `crash.yaml` and create it in the cluster - when we try to attach to the pod inside the container, the command seems to be stuck.

```shell script
$ kubectl apply -f crash.yaml 
pod/crash created

$ kubectl alpha debug -it crash --image ubuntu --target=crash --container=debug
```

That's actually true, a quick look into the pod describe reveals that our debug container cannot be created, becase the main container isn't running. Does that mean that it's not possible to debug the pod? Au contraire, we can still do it - just without the `--target` parameter. This still allows us to debug pod networking, for example.

```shell script
$ kubectl alpha debug -it crash --image ubuntu --container=debug-no-target 
If you don't see a command prompt, try pressing enter. 
root@crash:/# ps aux 
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND 
root         1  0.2  0.0  18504  3300 pts/0    Ss   09:19   0:00 /bin/bash 
root        10  0.0  0.0  34400  2900 pts/0    R+   09:19   0:00 ps aux
```

## Final thoughts

While still in it's early stage, `kubectl alpha debug` shapes up to be a useful and potentially very powerful tool. There are a couple use cases in which it might become really handy. Many of the containers running applications might not even have a shell, which renders `kubectl exec` unusable - the new debug feature allows for jumping into the pod without needing to change its manifest and recreating it. Even if a shell is available, the application containers most probably don't have all the tools necessary for debugging - and we might not want to install them manually inside a running container. With `kubectl alpha debug` we can create an kind of a "tool belt" image containing all the utilities that we use for debugging - and then simple create an ephemeral container in pods that have issues. Possibly it might even be used for attaching remote debuggers to applications running in pods.
All in all, `kubectl alpha debug` is a very interesting feature, looking forward to see how it evolves in future releases.

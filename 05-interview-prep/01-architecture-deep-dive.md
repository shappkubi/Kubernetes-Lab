# Architecture Deep Dive

The single most useful thing you can do for K8s interviews: be able to draw and narrate the architecture diagram from memory in 90 seconds. This page is the source of truth for that diagram.

## The diagram you should be able to redraw

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              CONTROL PLANE                                      │
│                                                                                  │
│     ┌────────────┐    ┌─────────────────┐    ┌──────────────┐                  │
│     │ kubectl /  │───►│  kube-apiserver │◄──►│     etcd     │                  │
│     │ clients    │    │  (REST + watch) │    │ (key/value,  │                  │
│     └────────────┘    │                 │    │  Raft)       │                  │
│                       └────┬────────┬───┘    └──────────────┘                  │
│                            │        │                                            │
│                            │        │                                            │
│                ┌───────────▼─┐  ┌───▼───────────────┐  ┌────────────────────┐   │
│                │  scheduler  │  │ controller-manager│  │ cloud-controller-  │   │
│                │  (binds Pod │  │ (Deployment, RS,  │  │ manager (LB, route,│   │
│                │   to Node)  │  │  Node, Endpoints, │  │  node lifecycle)   │   │
│                │             │  │  ServiceAccount,  │  │                    │   │
│                │             │  │  ...30+ loops)    │  │                    │   │
│                └─────────────┘  └───────────────────┘  └────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────┘
                                       ▲
                                       │   (everyone watches the apiserver)
                                       │
┌──────────────────────────────────────┼─────────────────────────────────────────┐
│                                  WORKER NODE                                    │
│                                       │                                          │
│         ┌─────────────┐               │              ┌──────────────┐           │
│         │   kubelet   │◄──────────────┘              │  kube-proxy  │           │
│         │  (manages   │  (watches assigned Pods)     │  (Service    │           │
│         │   Pods on   │                              │   datapath:  │           │
│         │   this node)│                              │   iptables   │           │
│         │             │                              │   or IPVS)   │           │
│         └──────┬──────┘                              └──────────────┘           │
│                │                                                                  │
│                ▼                                                                  │
│         ┌──────────────┐         ┌──────────────┐                               │
│         │ container    │────────►│   Pod        │                               │
│         │ runtime      │         │  ┌────────┐  │                               │
│         │ (containerd, │         │  │ pause  │  │  ◄── network namespace owner  │
│         │   CRI-O)     │         │  ├────────┤  │                               │
│         └──────────────┘         │  │ app    │  │                               │
│                                   │  │ container │                              │
│                ┌──────────────┐  │  └────────┘  │                               │
│                │   CNI agent  │  │              │                               │
│                │ (flannel,    │  └──────────────┘                               │
│                │  Calico,     │                                                   │
│                │  Cilium)     │                                                   │
│                └──────────────┘                                                   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Component-by-component narration (90 seconds, this order)

**etcd.** The brain. A consistent, distributed key-value store, replicated across (typically 3 or 5) nodes using Raft consensus. Stores every API object — every Deployment, Pod, Secret. If etcd is gone, the cluster's source of truth is gone.

**kube-apiserver.** The only component that talks to etcd. Stateless, horizontally scalable. All other components interact with state through it via REST and watch streams. Authn → Authz → Admission → write to etcd.

**scheduler.** Watches for Pods with no `spec.nodeName`. For each, runs filtering (which nodes meet the requirements?) and scoring (which is best?). Writes the bind: that's the only mutation it makes.

**controller-manager.** Hosts dozens of control loops: Deployment, ReplicaSet, Node, Job, ServiceAccount, Endpoints/EndpointSlices, ResourceQuota, etc. Each watches the apiserver and makes the world match the spec.

**cloud-controller-manager.** The cloud-specific parts split out: provisioning load balancers for `Service: LoadBalancer`, syncing node lifecycle with cloud VM lifecycle, route table management for some CNI/cloud combos.

**kubelet (per node).** Watches the apiserver for Pods bound to its node. Talks to the container runtime (containerd, CRI-O) via CRI to start/stop containers. Mounts volumes via CSI. Reports node and pod status back. **Doesn't deal with networking — that's CNI.**

**kube-proxy (per node).** Implements the Service abstraction. Watches Services and EndpointSlices, programs iptables (or IPVS) rules so that a packet to a Service's ClusterIP is DNAT'd to a randomly-chosen pod IP from the EndpointSlice.

**container runtime (per node).** containerd or CRI-O typically. Pulls images, manages container lifecycle, exposes the CRI API to the kubelet.

**CNI agent (per node).** Flannel / Calico / Cilium / kindnet / etc. Configures the network for each pod's veth pair, the node-level routing/encapsulation, and (often) NetworkPolicy enforcement.

**The pause container.** Per pod, holds the network namespace open so all other containers in the pod can share it. Tiny, almost always running, easy to miss.

## What lives where (for the "where do Secrets go?" follow-ups)

| Object | Lives in |
|---|---|
| Pod spec | etcd |
| Pod runtime status | etcd (status subresource), reported by kubelet |
| Secret data | etcd, base64-encoded (encrypted if encryption-at-rest configured) |
| ConfigMap data | etcd |
| Endpoints / EndpointSlice | etcd, materialized by Endpoints controller |
| Logs | Node disk, NOT in etcd or apiserver |
| Metrics (current) | metrics-server in-memory cache, NOT etcd |
| Audit log | wherever apiserver is configured to write it |

## Common follow-up: "what happens when I run kubectl apply -f deploy.yaml?"

Verbal walkthrough an interviewer expects:

1. **Client side.** kubectl reads the YAML, talks to the apiserver. Authentication uses the kubeconfig (cert / token).
2. **Authn** at the apiserver. The cert's CN is the user, the O is groups.
3. **Authz** via RBAC. User has permission to `create deployments` in this namespace?
4. **Admission.** Mutating webhooks may inject sidecars / labels. Validating webhooks may reject. Built-in admission may fill in defaults.
5. **Write to etcd.** The Deployment object now exists.
6. **Deployment controller** sees the new Deployment via watch. Computes desired ReplicaSet and creates it.
7. **ReplicaSet controller** sees the new RS. Creates Pod objects (one per replica).
8. **Scheduler** sees Pods with empty `nodeName`. Filters/scores nodes. Writes binding.
9. **kubelet** on the chosen node sees a Pod assigned. Calls container runtime via CRI to pull image, start container.
10. **CNI** assigns a pod IP, creates veth pair.
11. **kube-proxy** sees a new EndpointSlice (if the Pod matches a Service selector). Updates iptables.
12. **kubelet** marks the Pod Ready when readiness probe succeeds.

If you can rattle this off — naming each component and what it does — you've already cleared the architecture portion of most interviews.

## The critical-paths question

"What components MUST be running for new pods to start?"

- API server (needed for scheduling write).
- etcd (needed for API server).
- scheduler (needed to assign pods to nodes).
- kubelet on the target node (needed to actually start the container).
- CNI on the target node (needed for the pod to have a network).
- Container runtime on the target node.

What can be down without affecting new pod creation?
- controller-manager — *some* loops will fall behind, but already-extant Deployments mostly keep working from cached state.
- kube-proxy — pods come up but Services don't route correctly to/from them. New endpoints aren't programmed into iptables.
- DNS — pods come up but can't resolve names.
- Cloud-controller-manager — pods come up; new LoadBalancer Services don't get cloud LBs.

## What's "stateful" in the control plane?

**Only etcd.** Everything else is stateless, watching etcd for state. That's why you can have multiple apiservers/schedulers/controller-managers behind a load balancer or with leader election. It's also why etcd is the precious thing to back up.

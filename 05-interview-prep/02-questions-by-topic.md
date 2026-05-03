# Interview Q&A by Topic

Read the question, give your answer out loud, then check. The answers here are interview-strong: tight, structured, with a "why" beyond the surface fact. Aim to cover at least 80% of the points in each.

---

## Architecture

**Q1. What does etcd store and why does it use Raft?**

Stores every K8s API object — Pods, Deployments, Secrets, ConfigMaps, RBAC, CRDs and their data — as protobuf in a key-value store keyed by `/registry/<resource>/<namespace>/<name>`. Raft gives strong consistency across replicas (typically 3 or 5) so that a write is either visible to all members or to none, even with crashes and network partitions. K8s relies on linearizable reads for the "list and watch" semantics that controllers depend on; eventual consistency would break the reconcile loop.

**Q2. What's the difference between the scheduler and the kubelet?**

Scheduler runs on the control plane and decides *where* a pod runs. Kubelet runs on every node and *executes* the pod that's been assigned. Scheduler is global, stateless, observes all nodes. Kubelet is local, knows only its own node, talks to the container runtime.

**Q3. Why is there a "pause" container in every pod?**

It owns the pod's network and IPC namespaces. Every other container in the pod joins those namespaces. The pause container does almost nothing (sleeps), so its lifecycle is the lifecycle of the pod's namespace. If your app container restarts, the pod's IP doesn't change because the pause container is still holding the namespace.

**Q4. What's the controller pattern in one sentence?**

Watch the API server for a desired state, observe the actual state, take actions to converge them, repeat — forever.

**Q5. What's the difference between a Deployment and a ReplicaSet?**

A ReplicaSet ensures N pods are running with a given pod template. A Deployment manages ReplicaSets to support rolling updates and rollbacks — one ReplicaSet per spec hash. The Deployment controller scales the new RS up and the old RS down per `maxSurge`/`maxUnavailable`.

**Q6. What components must be running for a new pod to start?**

apiserver, etcd, scheduler, plus on the target node: kubelet, container runtime, CNI agent. controller-manager and kube-proxy can be down briefly without blocking pod creation (though controllers fall behind and Service routing breaks).

---

## Workloads

**Q7. When do you reach for a StatefulSet vs a Deployment?**

StatefulSet for workloads with stable identity, stable storage, or ordered start/stop semantics — databases, message queues, anything with replica-specific roles like leader. Deployment for stateless workloads where any pod is interchangeable. StatefulSet pods get predictable names (web-0, web-1) and persistent volume claims that survive rescheduling.

**Q8. Difference between init containers and sidecars?**

Init containers run **sequentially to completion** before main containers start. Used for setup tasks (waiting for dependencies, running migrations, fetching config). Sidecars are full peers in the pod that run alongside main containers — log shippers, service mesh proxies, file watchers. K8s 1.29+ formalized "native sidecar containers" via `initContainers` with `restartPolicy: Always`, which is the recommended way to run a sidecar that the lifecycle controller respects (e.g. terminates after the main container, allows main to complete first for Jobs).

**Q9. What happens when you delete a pod that's part of a Deployment?**

The pod gets a `DeletionTimestamp`, kubelet sends SIGTERM and waits `terminationGracePeriodSeconds`, then SIGKILL. The ReplicaSet controller notices the missing replica and creates a new one. The Deployment is unchanged.

**Q10. Difference between Job and CronJob?**

Job runs pods to completion once, used for batch workloads. CronJob creates Jobs on a schedule (cron syntax). CronJob has gotchas: missed runs, concurrency policy (Allow/Forbid/Replace), and job history limits — all common interview follow-ups.

---

## Networking & Services

**Q11. The four rules of K8s networking?**

1. Every pod has its own IP. 2. Pods can communicate across nodes without NAT. 3. Nodes can reach pods without NAT. 4. The IP a pod sees itself as is the IP others see it as. The CNI is what makes (1)–(4) true.

**Q12. What does kube-proxy actually do?**

Watches Services and EndpointSlices on the apiserver. For each Service, programs iptables (default mode) or IPVS rules on its node so packets destined for the Service's ClusterIP get DNAT'd to one of the backing pod IPs. It's a control plane for the Service datapath; it doesn't sit in the data path.

**Q13. ClusterIP vs NodePort vs LoadBalancer vs headless?**

- **ClusterIP:** virtual IP only reachable inside the cluster.
- **NodePort:** also opens a port on every node (range 30000–32767).
- **LoadBalancer:** asks the cloud-controller-manager for a cloud LB and points it at the NodePort.
- **Headless** (`clusterIP: None`): no virtual IP; DNS returns the list of pod IPs. Used by StatefulSets for per-pod DNS.

**Q14. EndpointSlice vs Endpoints?**

Endpoints is the original API: one Endpoints object per Service listing all pod IPs. Doesn't scale — every kube-proxy on every node receives every update. EndpointSlices split the same data across multiple smaller objects (default 100 endpoints per slice), which scales to tens of thousands of pods. Both are auto-managed by controllers.

**Q15. What is a CNI's job?**

When a pod is created on a node, the kubelet calls the CNI binary, which: assigns a pod IP from a pool, creates the veth pair (one end inside the pod's network namespace, one in the node's), programs node-level routing or encapsulation so the pod IP is reachable from other nodes. Some CNIs (Calico, Cilium) also enforce NetworkPolicy.

**Q16. Why doesn't `ping` work to a Service ClusterIP but TCP does?**

The ClusterIP is virtual — it's not bound to any interface, it's only an iptables/IPVS rule that DNATs incoming packets to a real pod. ICMP isn't matched by those rules (Service rules are for TCP/UDP ports). Packets to a ClusterIP via ping have no destination interface and get dropped.

**Q17. What does CoreDNS do, and what's `ndots:5`?**

CoreDNS is the in-cluster DNS server, deployed as a Deployment in `kube-system`. Resolves Service and Pod names. `ndots:5` in `/etc/resolv.conf` means "if the name has fewer than 5 dots, try the search list first". So `nslookup foo` becomes `foo.default.svc.cluster.local`, then `foo.svc.cluster.local`, then `foo.cluster.local`, then `foo`. This is convenient for short names but causes DNS volume amplification — a known cause of CoreDNS overload.

---

## Storage

**Q18. Walk me through how a PVC becomes a usable mounted volume.**

1. User creates a PVC with size, accessMode, and storageClassName.
2. The provisioner watching that StorageClass creates a PV (cloud disk, NFS export, etc.) and binds it to the PVC.
3. Pod mounts the PVC by name. Scheduler picks a node respecting topology (for `WaitForFirstConsumer`).
4. kubelet calls CSI driver to attach (cloud-block) and mount the volume into the pod's filesystem namespace.

**Q19. Three access modes?**

- **ReadWriteOnce** — one node mounts R/W. Most cloud block storage.
- **ReadWriteMany** — many nodes mount R/W. NFS, EFS, CephFS, Longhorn.
- **ReadOnlyMany** — many nodes read only.
- (Newer) **ReadWriteOncePod** — even stricter than RWO, scoped to a single pod.

**Q20. WaitForFirstConsumer vs Immediate volume binding?**

`Immediate` provisions and binds as soon as the PVC is created, picking a zone arbitrarily. `WaitForFirstConsumer` waits for a pod to use the PVC, then provisions in the right zone for that pod. Default for cloud block storage in modern K8s — avoids "PV is in zone-a, pod needs zone-b" deadlocks.

**Q21. What's the difference between Delete and Retain reclaim policies?**

When the PVC is deleted: `Delete` also deletes the underlying PV and storage. `Retain` leaves the PV in `Released` state — you must manually clean it up. Production: use `Retain` for anything you can't afford to lose to a typo.

---

## Scheduling

**Q22. What's the difference between a taint and an affinity?**

Taints repel pods that don't tolerate them — node-side. Affinity attracts pods to nodes (or pods to other pods) — pod-side. Combined: GPU nodes have a `gpu=true:NoSchedule` taint, GPU workloads have a matching toleration AND a node affinity for `node-type: gpu`. Taint says "don't put non-GPU pods here", affinity says "do put GPU pods here".

**Q23. Required vs preferred scheduling rules?**

`requiredDuringSchedulingIgnoredDuringExecution` is a hard constraint — Pending if not satisfied. `preferredDuringSchedulingIgnoredDuringExecution` is a hint with a weight — scheduler tries but won't block. The "IgnoredDuringExecution" half means: if a node label changes after scheduling, the running pod isn't evicted. Ergo K8s has no `RequiredDuringExecution` (yet) — that's a feature gate in progress.

**Q24. Topology spread constraints in one sentence?**

Distributes pods evenly across topology domains (zones, hostnames, racks) within a configurable skew, so a single zone failure doesn't take you out.

**Q25. Why is my pod Pending?**

Run `kubectl describe pod`. The Events line tells you. Top causes: insufficient CPU/memory, no node matches affinity/selector, untolerated taint, hostPort conflict, PVC not bound. Each maps to a specific fix.

---

## Resources, Autoscaling, Probes

**Q26. QoS classes?**

- **Guaranteed** — every container has request == limit for both CPU and memory. Last to be evicted.
- **Burstable** — at least one container has a request, but request != limit. Mid-tier.
- **BestEffort** — no requests or limits. First to be evicted.

**Q27. What does OOMKilled mean and what's the difference between OOMKilled and Evicted?**

OOMKilled: the container's memory hit its limit, kernel cgroup OOM killer killed the process, kubelet restarted it according to restartPolicy. Pod stays on the node. Evicted: the *node* is under memory pressure and kubelet evicted lower-QoS pods to free memory. Pod goes to `Failed` state with reason `Evicted` and is rescheduled by its controller.

**Q28. Should I set a CPU limit?**

Controversial. Mainstream view: set CPU requests for guaranteed share, skip CPU limits unless enforcing multi-tenant fairness. Limits cause CFS throttling on bursty workloads with non-obvious latency consequences. Always set memory limits to catch leaks.

**Q29. HPA scaling on what?**

CPU or memory utilization (vs request) by default. Custom metrics from Prometheus Adapter. External metrics (queue depth, RPS) via External Metrics API or KEDA. Behavior fields (`autoscaling/v2`) tune speed: `stabilizationWindowSeconds: 0` for fast scale-up, longer for stable scale-down.

**Q30. Liveness vs readiness vs startup probe?**

- **Startup:** "is the app done starting?" Failure = restart container. Use for slow-starting apps so liveness doesn't kill mid-startup.
- **Liveness:** "is the app still alive?" Failure = restart container. Should check process health, *not* downstream dependencies.
- **Readiness:** "should I get traffic?" Failure = remove from Service endpoints, no kill. May check dependencies.

The classic mistake: liveness checks the DB. DB hiccup → every replica restarts simultaneously → cascading outage.

---

## Security & RBAC

**Q31. Walk me through the path of an authenticated kubectl request.**

Authn (cert/token/OIDC/webhook → user + groups) → Authz (RBAC: does this user/group have permission for this verb on this resource in this namespace?) → Admission (mutating webhooks may rewrite, validating webhooks may reject) → write to etcd → respond.

**Q32. RBAC: Role vs ClusterRole?**

Role is namespaced — rules apply only within one namespace. ClusterRole is cluster-scoped — usable cluster-wide via ClusterRoleBinding, OR usable within one namespace via RoleBinding (same rules, scoped to that namespace). Used for cluster-scoped resources (Nodes, PVs) and for sharing rule definitions across namespaces.

**Q33. ServiceAccounts vs Users?**

Users are external (humans, CI systems) — K8s itself doesn't store user objects. ServiceAccounts are namespaced K8s objects that pods authenticate as. Each pod gets a projected SA token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/`. Use SAs for least-privilege per-workload identity.

**Q34. What's wrong with mounting Secrets as env vars?**

Env vars are inherited by child processes, may leak via crash dumps and `/proc/self/environ`, often appear in container logs and `ps`. Files are auditable, mode-restricted, and only readable by the process. Production preference: secrets as files via volume mount.

**Q35. Pod Security Admission — the three levels?**

`privileged` (anything), `baseline` (no obvious privilege escalation), `restricted` (force runAsNonRoot, drop ALL capabilities, readOnly root fs, seccomp default). Apply per-namespace via labels: `pod-security.kubernetes.io/enforce=restricted`. There's also `audit` and `warn` modes that log instead of blocking — a great staged-rollout tool.

**Q36. NetworkPolicy — what enforces it?**

The CNI. Vanilla flannel doesn't enforce; Calico, Cilium, kube-router do. Without an enforcing CNI, NetworkPolicy objects are accepted by the API but have no effect. Common gotcha.

---

## Failure & Operations

**Q37. What happens when a node dies suddenly?**

After `node-monitor-grace-period` (default 40s), the node is marked NotReady. After `--default-unreachable-toleration-seconds` (default 5min via taint-based eviction), the kubelet's pods are marked for eviction. New pods are scheduled on other nodes. Stateful pods with PVCs face a longer recovery — the PV may need to be detached from the dead node before another can attach (cloud-dependent timeouts).

**Q38. What's a PodDisruptionBudget?**

A constraint on voluntary disruptions: "at least N replicas must be available at all times" or "at most N can be disrupted simultaneously". Honored by `kubectl drain`, the cluster autoscaler, and manual evictions. NOT honored by involuntary disruptions (node power loss).

**Q39. How do you upgrade a cluster?**

kubeadm: upgrade the first control-plane node (`kubeadm upgrade plan` + `apply`), then kubelet on it. Repeat per other CP nodes (`kubeadm upgrade node`). Then per worker: drain, install new kubeadm/kubelet, `kubeadm upgrade node`, restart kubelet, uncordon. Always one minor version at a time. Pre-flight: backup etcd, run `kubent` for deprecated APIs, verify CNI/CSI/ingress versions support the target.

**Q40. How do you back up etcd?**

`etcdctl snapshot save`. Restore: stop etcd, `etcdctl snapshot restore` to a new data dir, point etcd config at the new dir, start etcd. Cluster comes back to the snapshot's state — recent changes after the snapshot are lost (RPO = snapshot frequency).

**Q41. What's GitOps and how does it help DR?**

GitOps means cluster state is reconciled from git by a controller in the cluster (Argo CD, Flux). It pulls instead of CI pushing. For DR: spin up a new cluster, point Argo at the same git repo, the cluster rebuilds itself. Combine with Velero for in-cluster state (PVs, Job statuses) that isn't in git.

---

## Observability

**Q42. Three commands to debug any pod issue?**

`kubectl describe pod <name>` (events + last state), `kubectl logs <name> --previous` (last container's logs), `kubectl get events --sort-by=.lastTimestamp` (cluster-wide signal).

**Q43. Where do K8s metrics come from?**

`kubelet --> cAdvisor` exposes per-container resource metrics via the kubelet's Summary API. metrics-server scrapes those across the cluster, exposes via the Metrics API (used by HPA and `kubectl top`). For deep metrics, kube-state-metrics exposes object-level metrics (Deployment status, Pod state) via Prometheus, which scrapes via service discovery.

**Q44. Where do K8s logs go?**

Container stdout/stderr is captured by the container runtime, written to JSON files on the node, and exposed by `kubectl logs`. Logs are NOT in etcd. For retention beyond the pod's life, an agent (Fluent Bit, Vector, Promtail) tails the files and ships to a central system (Loki, ELK, Datadog).

---

## Production Patterns

**Q45. Helm vs Kustomize?**

Helm packages and templates — strong for distributing software (charts on Artifact Hub). Kustomize patches base YAML for environment-specific overlays — strong for managing your own apps across dev/staging/prod. Common production pattern: Helm for vendored apps, Kustomize for in-house apps. Both can also coexist (Helm chart with Kustomize overlay).

**Q46. What's an Operator?**

A custom controller that reconciles a CRD, encoding domain expertise that a human operator would otherwise apply. Examples: Postgres Operator handling failover and backups; Cassandra Operator handling rolling upgrades and rebalancing. Pattern is just controller-pattern + CRD applied to your domain.

**Q47. When do you reach for a service mesh?**

When you have many services (>20–30) and need consistent retry/timeout/circuit-breaker policy without changing each app, or hard mTLS requirements between every pair, or you want progressive delivery (Argo Rollouts works far better with a mesh). For small clusters, NetworkPolicies + a good HTTP client cover most needs at far less complexity.

**Q48. Multi-tenancy: namespaces enough?**

Soft tenancy: yes, with ResourceQuota + LimitRange + NetworkPolicy + PSA + RBAC. Hard tenancy (mutually distrusting users): no. Cluster-scoped resources leak; CRDs are global; privileged DaemonSets touch everything. For hard tenancy: virtual clusters (vcluster) or separate clusters.

**Q49. Canary deployment without a service mesh?**

Manual canary with two Deployments + one Service whose selector matches both via a shared label. Replica counts approximate traffic split (80/20 = 8 stable, 2 canary). Imperfect because real traffic may not balance evenly. With a mesh or ingress that supports header/percentage routing (NGINX with annotations, Istio VirtualService), you get true percentage-based routing and weighted abort.

**Q50. What's progressive delivery and what does it need?**

Progressive delivery = canary or blue/green deployments + automated metric analysis + automated rollback on regression. Requires (a) a way to split traffic (mesh, ingress), (b) reliable per-version metrics (error rate, latency), (c) a tool that orchestrates the steps (Argo Rollouts, Flagger). Lives at the intersection of CI/CD and observability.

---

## Bonus deep cuts

**Q51. What's the difference between containerd and Docker?**

containerd is a low-level container runtime that K8s talks to via CRI. Docker (the daemon, dockerd) was a higher-level wrapper around containerd. K8s removed Docker support (the dockershim) in 1.24 because it was redundant — kubelet now talks containerd or CRI-O directly. The image format is unchanged; "Docker images" still work.

**Q52. What's a finalizer and why might a delete hang?**

Finalizers are strings on `metadata.finalizers` that prevent deletion. Controllers add them when they need to do cleanup before the object goes away (e.g. Cloud-controller removes a load balancer when a `Service: LoadBalancer` is deleted). If the controller responsible for a finalizer is broken or gone, the object hangs in `Terminating` forever. Force-delete: `kubectl patch ... --type=merge -p '{"metadata":{"finalizers":[]}}'` — but only after understanding what should have been cleaned up.

**Q53. How does a Job know it's done?**

A Job spec has `completions` (default 1) and `parallelism`. A pod from a Job that exits 0 increments the success count; Job is `Complete` when success count == completions. Failed pods are retried up to `backoffLimit` (default 6) before the Job goes `Failed`.

**Q54. What's the API server's "Priority and Fairness" feature?**

APF (replaces older max-inflight settings) classifies incoming requests into flow schemas (e.g. "system controllers", "global default", "leader election") and assigns each a priority level. Each level has a queue. Lower-priority requests are throttled first when the apiserver is overloaded, preventing one greedy client from starving the rest. Production-critical for stability.

**Q55. Difference between MutatingAdmissionWebhook and ValidatingAdmissionWebhook?**

Mutating webhooks run first; they can change the request (add labels, inject sidecars). Validating webhooks run after mutating, just before the persist; they can only accept or reject. Both can be used for things like "reject pods without resource requests" (validating) or "auto-add the team-name label from a namespace annotation" (mutating).

**Q56. ValidatingAdmissionPolicy — what is it?**

K8s 1.30 GA'd a new built-in policy mechanism using CEL (Common Expression Language) for many cases that previously needed a webhook. Cheaper, no out-of-cluster dependency, no webhook latency. Replaces a lot of OPA Gatekeeper / Kyverno use cases for simple validation rules.

**Q57. What are EndpointSlices and why did they replace Endpoints?**

EndpointSlice splits a Service's endpoints across multiple smaller objects so kube-proxy and other watchers don't get a full update on every pod change. Critical at scale: the original Endpoints object scales O(pods × watchers) on every change. EndpointSlice keeps it O(slice). Default since K8s 1.21.

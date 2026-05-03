# Week 5 Labs — Failure, Upgrades, Disaster Recovery

This is the production-experience week. Several labs run on **Killercoda** (browser, free) — they need destructive operations or a multi-node control plane that doesn't fit on a disk-constrained laptop. Each Killercoda lab takes ~30 min and resets between sessions.

---

## Lab 25 — Drain, Cordon, PodDisruptionBudget

**Goal:** simulate a node-maintenance window without dropping availability.

Cluster: k3d `lab` (you can do this with 1 server + 1 agent — drain the agent).

### 25.1 Setup an app with replicas + PDB

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 3
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: c
          image: nginx
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 2
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: web-pdb }
spec:
  minAvailable: 2
  selector: { matchLabels: { app: web } }
```

`minAvailable: 2` says: "at any time during voluntary disruption, at least 2 of the 3 must be Ready." Voluntary = drain, evict, autoscaler scale-in. Involuntary = node power loss, kernel panic — PDB doesn't help there.

### 25.2 Cordon a node

```
$ kubectl get nodes
$ kubectl cordon <agent-node>
$ kubectl get nodes               # SchedulingDisabled
```

Existing pods stay; no new ones land here. Common preface to drain.

### 25.3 Drain it

```
$ kubectl drain <agent-node> --ignore-daemonsets --delete-emptydir-data
```

Watch it work pod-by-pod, respecting the PDB. If you drop `replicas` to 2, drain will *block* — there's no way to evict another web pod without violating the PDB.

### 25.4 Bring it back

```
$ kubectl uncordon <agent-node>
```

### 25.5 Reflect

Voluntary vs involuntary disruption is the fault line for SLO design. PDBs make voluntary disruptions safe. For involuntary, you need replicas spread across failure domains and fast pod recovery.

---

## Lab 26 — etcd: Backup & Restore (Killercoda)

**Goal:** speak fluently about the data plane of the control plane.

### 26.1 Why a real cluster

This needs a kubeadm-style cluster with etcd as a separate process — k3d's k3s collapses etcd into kine + sqlite, so the etcdctl flow doesn't apply directly.

> Run: **Killercoda → "Backup and Restore Etcd"** (search "etcd backup" on killercoda.com). Free, in-browser, ~20 min.

### 26.2 What you'll do there

```
# On the control-plane node:
$ ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /tmp/etcd.db

$ etcdctl snapshot status /tmp/etcd.db --write-out=table
```

To restore (different process; you stop etcd, restore to a new data dir, point etcd at it):

```
$ ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd.db --data-dir=/var/lib/etcd-restored
# update etcd static pod manifest to use --data-dir=/var/lib/etcd-restored
# kubelet restarts the etcd pod
```

### 26.3 What gets stored in etcd

Everything. All API objects, including Secrets, ConfigMaps, RBAC, CRDs and their data. Recovering etcd recovers the cluster (minus running pod state, which the kubelet will reconcile from etcd's spec).

### 26.4 Reflect

If your etcd is gone and you have no backup but you have all your YAML in git, can you "restore" by reapplying everything? (Mostly yes — that's the GitOps disaster-recovery argument. Caveats: any non-git state — Job statuses, autoscaler state, etcd-only objects, dynamically-issued certs — is lost. PVs survive only if their underlying storage is independent of K8s.)

---

## Lab 27 — Cluster Upgrade (Killercoda)

**Goal:** know the upgrade pattern cold — control plane first, workers next, drain in the middle.

> Run: **Killercoda → "Upgrade a Kubernetes cluster"** (free, ~30 min).

### 27.1 The mental model

```
1. kubeadm upgrade plan                          # which versions are available
2. kubeadm upgrade apply v1.30.x                 # ON FIRST CONTROL PLANE — upgrades kube-apiserver/scheduler/controller-manager + etcd
3. apt install kubelet=...                       # then upgrade kubelet on this node
4. systemctl restart kubelet
5. (For each additional control plane) kubeadm upgrade node
6. (For each worker) kubectl drain <n> --ignore-daemonsets
                     apt install kubelet=...; systemctl restart kubelet
                     kubectl uncordon <n>
```

Order matters: apiserver first (and only one minor version ahead of kubelets), then kubelets. Skipping minor versions is unsupported (1.28 → 1.30 must go via 1.29).

### 27.2 What can go wrong

- API deprecations: a removed API on the new version (e.g. `policy/v1beta1 PodDisruptionBudget`) breaks your manifests. Fix: `kubectl convert` or rewrite YAML before upgrading.
- CNI / CSI version pinning: third-party DaemonSets must support the new K8s minor.
- Webhooks: validating/mutating webhooks have to be reachable during the upgrade — if their pod is on the node you're draining, careful ordering.
- Workloads: a few pods restart during worker drain — PDBs save you here.

### 27.3 Reflect

Why is it useful to upgrade only one minor at a time even though some versions appear "skippable"? (Compatibility is officially supported only N → N+1 for kubelet vs control plane. Tools and CRDs have a similar window. Skipping is one of those things that *seems* to work right up until it doesn't.)

---

## Lab 28 — Production Incidents Tour

Walk every section of `03-troubleshooting/PLAYBOOK.md`. For each, deliberately break a workload, then run the listed diagnosis steps. Take notes in your own words on what the symptom was, what you saw in `describe`/`logs`/`events`, and how you fixed it.

This is the lab interviewers love.

---

## Lab 29 — Disaster Recovery Patterns

**Goal:** know three layers of DR and choose deliberately.

### 29.1 Application-state DR (Velero)

Velero backs up:
- Cluster API objects (Deployments, Services, etc.)
- Volume snapshots (via CSI snapshot APIs or restic)

Backup target is object storage (S3, GCS, Azure Blob). Restore can be cluster-wide, namespace-scoped, or selective.

You can install Velero on k3d to play, but it'll add ~200 MB. **Concept-level for disk constraints**:

```
velero backup create nightly --include-namespaces prod
velero schedule create nightly --schedule="0 2 * * *" --include-namespaces prod
velero restore create --from-backup nightly --namespace-mappings prod:prod-restored
```

### 29.2 GitOps-as-DR

If every cluster object is reconciled from git (Argo CD / Flux), losing a cluster mostly means: provision a new cluster, point Argo at the same git repo, wait. Combine with PV snapshots from cloud storage for stateful workloads.

### 29.3 Control-plane DR

For self-managed clusters: etcd backups are the pivot point (Lab 26). For managed (EKS/GKE/AKS), the cloud provider handles control-plane DR; you focus on workload DR.

### 29.4 Reflect — what's your RPO/RTO?

- RPO (Recovery Point Objective): how much data can you afford to lose? (etcd snapshot every 6h ⇒ RPO ≤ 6h for cluster state).
- RTO (Recovery Time Objective): how fast must you be back?
- These numbers determine the pattern. "Re-apply YAML from git" might be RTO=1h. "Velero restore with PVs" might be RTO=15m. "Hot standby cluster" RTO ≈ 0.

---

## Lab 30 — Capacity & Cost Design

**Goal:** sketch a sizing answer the way you'd give it to an engineering director.

### 30.1 The framework

For a workload, you need:
- Average and p99 CPU + memory per pod under realistic load
- Replica count for redundancy and throughput
- Headroom (~25–30%) for spikes + node failures
- Reserved overhead per node (kubelet, system pods): ~10% CPU, ~10% RAM

### 30.2 Worked example

App profile: 200m / 400Mi avg, 500m / 600Mi p99, 6 replicas for HA across 3 zones. Add 25% headroom.

- 6 × 0.5 vCPU = 3 vCPU + 25% = ~3.75 vCPU
- 6 × 0.6 GiB = 3.6 GiB + 25% = ~4.5 GiB

For node sizing: assume m5.xlarge (4 vCPU, 16 GiB). Allocatable ≈ 3.6 vCPU and ~14 GiB after overhead. With 2 zones × 1 node + 1 spare = 3 nodes minimum. That's ~10.8 vCPU, ~42 GiB allocatable for 3.75 vCPU / 4.5 GiB demand → plenty for HPA headroom and other workloads.

### 30.3 Common waste patterns

| Pattern | Spotting it | Fix |
|---|---|---|
| Massive requests, tiny actual usage | `kubectl top pod` vs `kubectl describe pod` | VPA recommender, right-size requests |
| Singleton replicas with HA pretensions | replicas: 1 with PDB minAvailable: 1 | Always at least 2 for HA |
| Underutilized large nodes | `kubectl describe node` allocated vs allocatable | Smaller node types or bin-packed scheduler |
| Unbounded retention (logs, prometheus) | TSDB / object storage growth | Set explicit retention; tier storage |

### 30.4 Reflect

What does "right-sized" mean? (Requests close to p95 usage so the scheduler packs nodes efficiently, but not so close that bursty traffic causes evictions. Limits ≥ p99 if set.)

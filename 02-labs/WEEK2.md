# Week 2 Labs — Configuration, Storage, Networking

Cluster needed: k3d `lab` (default).

---

## Lab 7 — ConfigMaps & Secrets

**Goal:** know all four ways config flows into a pod (env, envFrom, volume file, projected) and the trade-offs.

### 7.1 ConfigMap from literals and files

```
$ kubectl create cm app-config --from-literal=GREETING=hello --from-literal=LOG_LEVEL=debug
$ kubectl get cm app-config -o yaml
```

### 7.2 Use it four ways

```yaml
apiVersion: v1
kind: Pod
metadata: { name: cfg-demo }
spec:
  containers:
    - name: c
      image: busybox
      command: ["sh","-c","env | grep -E 'GREETING|LOG'; ls /etc/cfg; cat /etc/cfg/GREETING; sleep 3600"]
      env:
        - name: GREETING                       # 1. single env var from key
          valueFrom: { configMapKeyRef: { name: app-config, key: GREETING } }
      envFrom:
        - configMapRef: { name: app-config }   # 2. all keys as env vars
      volumeMounts:
        - name: cfg-vol                        # 3. as files
          mountPath: /etc/cfg
  volumes:
    - name: cfg-vol
      configMap: { name: app-config }
```

```
$ kubectl logs cfg-demo
```

### 7.3 Update behavior

```
$ kubectl patch cm app-config --type=merge -p '{"data":{"LOG_LEVEL":"info"}}'
$ kubectl exec cfg-demo -- cat /etc/cfg/LOG_LEVEL    # eventually consistent — file updates
$ kubectl exec cfg-demo -- env | grep LOG_LEVEL      # env var does NOT update
```

**Critical interview point:** env vars are baked at pod start. Volumes update (~minute). If you change a ConfigMap, deployments don't auto-restart unless you trigger a rollout (`kubectl rollout restart deploy/foo`) or use a config-hash annotation.

### 7.4 Secrets

```
$ kubectl create secret generic db-creds --from-literal=USER=admin --from-literal=PASSWORD='s3cret!'
$ kubectl get secret db-creds -o yaml    # values are base64, NOT encrypted
$ kubectl get secret db-creds -o jsonpath='{.data.PASSWORD}' | base64 -d
```

Same four mounting modes as ConfigMaps. The "encryption" is base64 — i.e. none. To actually encrypt at rest:
- enable `--encryption-provider-config` on the API server (KMS or aescbc)
- use external secret stores (Vault, AWS Secrets Manager + External Secrets Operator)
- use Sealed Secrets to store encrypted secret YAML in git

### 7.5 Reflect

Why do most teams *not* mount Secrets as env vars in production? (Logs, crashes, child processes inheriting env, ps showing cmdline — all leak env. Files are auditable and mode-restricted.)

---

## Lab 8 — Storage: PV, PVC, StorageClass

**Goal:** internalize how dynamic provisioning works and what reclaim policies and access modes mean.

### 8.1 What's already there

```
$ kubectl get storageclass
$ kubectl get csidriver         # may be empty in k3d
```

k3d ships with `local-path` as the default StorageClass — it dynamically provisions hostPath PVs.

### 8.2 PVC binding

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests: { storage: 1Gi }
```

```
$ kubectl apply -f pvc.yaml
$ kubectl get pvc
$ kubectl get pv
```

Watch the dance: PVC asks for storage → provisioner sees `storageClassName` → creates a PV → PV binds to PVC. The PVC has `volumeBindingMode: WaitForFirstConsumer` (k3s default), so it'll stay Pending until a Pod actually mounts it. Try it:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: c
      image: busybox
      command: ["sh","-c","echo persisted > /data/hello; sleep 3600"]
      volumeMounts: [{ name: d, mountPath: /data }]
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: data }
```

```
$ kubectl exec writer -- cat /data/hello
$ kubectl delete pod writer
```

Recreate `writer` from the same YAML — the file `/data/hello` is still there. That's persistence.

### 8.3 Reclaim policies

```
$ kubectl get pv <name> -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
```

- `Delete` — when PVC is deleted, the PV (and underlying disk) is wiped. Default for dynamic.
- `Retain` — PV is kept around in `Released` state. You must manually clean up. Use this when you can't afford accidental data loss.

### 8.4 Access modes

| Mode | Meaning |
|---|---|
| ReadWriteOnce (RWO) | Mounted by one node R/W. Most cloud block storage. |
| ReadOnlyMany (ROX) | Mounted by many nodes read-only. Rare. |
| ReadWriteMany (RWX) | Mounted by many nodes R/W. NFS, EFS, CephFS, Longhorn. |
| ReadWriteOncePod | RWO but enforced to a single Pod. Newer, better for leader-election style. |

### 8.5 Reflect

Why does a "WaitForFirstConsumer" volume binding mode matter for cloud clusters? (Answer: lets the scheduler pick a node first, then provision the disk in the right zone — avoids "PV is in zone-a but pod needs zone-b" deadlocks.)

---

## Lab 9 — StatefulSet with Persistent Storage (Postgres)

**Goal:** see why StatefulSet exists. Stable identity + per-replica volume + ordered rollout.

```yaml
apiVersion: v1
kind: Service
metadata: { name: pg }
spec:
  clusterIP: None             # headless — DNS resolves to pod IPs
  selector: { app: pg }
  ports: [{ port: 5432 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: pg }
spec:
  serviceName: pg
  replicas: 2
  selector: { matchLabels: { app: pg } }
  template:
    metadata: { labels: { app: pg } }
    spec:
      containers:
        - name: pg
          image: postgres:16
          env:
            - { name: POSTGRES_PASSWORD, value: pw }
            - { name: PGDATA,            value: /var/lib/postgresql/data/pgdata }
          ports: [{ containerPort: 5432 }]
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
          resources:
            requests: { cpu: 50m, memory: 128Mi }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 1Gi } }
```

```
$ kubectl apply -f pg.yaml
$ kubectl get pods -l app=pg -w     # pg-0 first, then pg-1
$ kubectl get pvc                    # data-pg-0, data-pg-1
```

### Stable identity

```
$ kubectl run psql --rm -it --image=postgres:16 -- bash
# psql -h pg-0.pg.default.svc.cluster.local -U postgres -c "CREATE TABLE t(x int); INSERT INTO t VALUES (1);"
```

Delete pg-0:

```
$ kubectl delete pod pg-0
$ kubectl get pod pg-0     # comes back with the SAME name and SAME PVC, so the table survives
```

That's the whole point. With a Deployment, the new pod gets a new random name and a new PVC.

### 9.5 Reflect

When would you NOT use a StatefulSet for a database? (Most production: you'd use a managed DB or an Operator that handles failover, leader election, and backup — StatefulSet alone gives you stable identity and storage but doesn't know what "primary" means.)

---

## Lab 10 — Cluster Networking Model

**Goal:** prove to yourself the four rules of K8s networking.

The model:
1. Every Pod gets its own IP.
2. Pods can reach each other across nodes without NAT.
3. Nodes can reach all pods without NAT.
4. The IP a Pod sees itself as is the IP others see it as.

### 10.1 Inspect

```
$ kubectl run a --image=busybox -- sleep 3600
$ kubectl run b --image=busybox -- sleep 3600
$ kubectl get pod -o wide      # note IPs
$ A=$(kubectl get pod a -o jsonpath='{.status.podIP}')
$ kubectl exec b -- ping -c2 $A
$ kubectl exec a -- ip addr show eth0
```

The IP a sees on its eth0 is the same IP b reaches it at. CNI's job is to make that true across nodes.

### 10.2 Who routes the packets?

In k3d/k3s the CNI is **flannel** (or kindnet in kind). Look:

```
$ kubectl -n kube-system get pods | grep -iE 'flannel|kindnet|cilium|calico'
```

Each node has a CNI agent that programs Linux routing/iptables/eBPF so pod-to-pod packets cross node boundaries with overlay encapsulation (vxlan) or pure routing.

### 10.3 Reflect

What problem does a CNI solve that the cloud's network alone doesn't? (Pod IPs need to be routable cluster-wide and consistent regardless of which node a pod runs on; the cloud only routes node IPs.)

---

## Lab 11 — DNS & CoreDNS

**Goal:** know the FQDN forms and the search-domain mechanism, so you can debug a DNS failure in 30 seconds.

### 11.1 Resolve all the forms

```
$ kubectl run dns --rm -it --image=busybox -- sh
/ # cat /etc/resolv.conf
nameserver 10.43.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:5

/ # nslookup kubernetes
/ # nslookup kubernetes.default
/ # nslookup kubernetes.default.svc.cluster.local
/ # nslookup pg-0.pg.default.svc.cluster.local
```

The `search` list and `ndots:5` together explain why `nslookup foo` and `nslookup foo.default` and `nslookup foo.default.svc.cluster.local` all work: each is tried with each search suffix until one resolves.

### 11.2 The CoreDNS Corefile

```
$ kubectl -n kube-system get cm coredns -o yaml
```

This is the actual DNS config. Lines worth knowing:
- `kubernetes cluster.local in-addr.arpa ip6.arpa` — the K8s plugin (resolves Service/Pod names)
- `forward . /etc/resolv.conf` — anything else goes to upstream DNS
- `cache 30` — DNS cache size

### 11.3 Break it

```
$ kubectl -n kube-system scale deploy coredns --replicas=0
$ kubectl run dns --rm -it --image=busybox -- nslookup kubernetes
```

You'll see resolution fail. This is the world inside a "DNS storm" incident. Restore: `kubectl -n kube-system scale deploy coredns --replicas=2`.

### 11.4 Reflect

Why does `ndots:5` cause more DNS traffic than people expect? (Anything with fewer than 5 dots — i.e. almost everything — is tried first as a search-domain expansion. `redis.example.com` becomes a flurry of `redis.example.com.default.svc.cluster.local`, `…svc.cluster.local`, `…cluster.local`, then finally bare. Long-known cause of DNS overload.)

---

## Lab 12 — NetworkPolicy

**Goal:** write a working default-deny + explicit allow.

### 12.1 Setup

```
$ kubectl create ns shop
$ kubectl -n shop run web --image=nginx --port=80 --labels=app=web,role=frontend
$ kubectl -n shop run api --image=nginx --port=80 --labels=app=api,role=backend
$ kubectl -n shop run db  --image=nginx --port=80 --labels=app=db,role=data
$ kubectl -n shop expose pod web --port=80
$ kubectl -n shop expose pod api --port=80
$ kubectl -n shop expose pod db  --port=80
```

### 12.2 Without policies, all-to-all works

```
$ kubectl -n shop run probe --rm -it --image=busybox -- wget -qO- web   # works
$ kubectl -n shop run probe --rm -it --image=busybox -- wget -qO- db    # works (this is the bad part)
```

### 12.3 Default deny ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: shop }
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

```
$ kubectl apply -f deny.yaml
$ kubectl -n shop run probe --rm -it --image=busybox -- wget -qO- --timeout=3 web   # times out
```

### 12.4 Allow web → api, api → db

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: web-to-api, namespace: shop }
spec:
  podSelector: { matchLabels: { app: api } }
  ingress:
    - from:
        - podSelector: { matchLabels: { role: frontend } }
      ports: [{ port: 80, protocol: TCP }]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: api-to-db, namespace: shop }
spec:
  podSelector: { matchLabels: { app: db } }
  ingress:
    - from:
        - podSelector: { matchLabels: { role: backend } }
      ports: [{ port: 80, protocol: TCP }]
```

Probe again from a labelled pod:

```
$ kubectl -n shop run probe --rm -it --image=busybox --labels=role=frontend -- wget -qO- api   # works
$ kubectl -n shop run probe --rm -it --image=busybox --labels=role=frontend -- wget -qO- db    # blocked
```

### 12.5 Heads-up

Some CNIs (k3s default is flannel) **do not enforce NetworkPolicy** out of the box. If your policies look correct but nothing changes, that's why. Confirm:

```
$ kubectl -n kube-system get pods | grep -iE 'calico|cilium|kube-router'
```

If empty, the lab still teaches the API correctly but enforcement isn't real until you swap CNI. For an enforcement lab, run the same scenario on Killercoda's Calico playground — listed in `04-production-scenarios/`.

### 12.6 Reflect

Why does NetworkPolicy operate on labels, not IPs? (Pod IPs are ephemeral; labels are the user-facing identity. The CNI translates label selectors to IP/iptables/eBPF rules continuously.)

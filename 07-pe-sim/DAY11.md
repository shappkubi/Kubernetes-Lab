# Day 11 — Emergency CAB: critical CVE patch on all nodes (drain drill)

**Theme:** Coordinated, time-bounded operation under leadership scrutiny. The work is mostly cordon/drain/replace/validate, the *judgment* is around PDBs, communication, and order of operations.

**Time budget:** 90–120 min.

---

## Prep (~20 min)

`02-labs/WEEK5.md` § Lab 25 (drain + PDB).

`04-production-scenarios/SCENARIOS.md` § Scenario 3 (Zero-downtime cluster upgrade).

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Emergency CAB

```
CHG-2026051401-EMRG
Type: Emergency change
Risk: High
Title: Patch all worker nodes for CVE-2026-XXXX (kernel privilege escalation)
Implementer: you
Approvers: platform lead, security lead (both reached on phone, recorded)
Window: ASAP, target completion by <today+1> 00:00 UTC (24h SLA from advisory)

Context:
  - CVE-2026-XXXX published <today-1> 09:00 UTC, CVSS 9.8
  - Allows privilege escalation from container to node
  - Patch available in node image v2026.05.14
  - 47 worker nodes across 3 clusters need patch
  - Lab equivalent: 1 worker node (k3d-lab-agent-0) needs to be drained, "replaced", validated

Implementation plan (per cluster):
  1. Cordon all nodes
  2. For each node:
     a. Drain (--ignore-daemonsets --delete-emptydir-data --grace-period=300)
     b. Verify pods rescheduled, customer impact = 0
     c. Replace node with patched image (max-unavailable=1)
     d. Validate workloads on new node
  3. Uncordon
  4. Validate cluster: all deployments at desired replicas, no Warning events

Per-cluster duration estimate: prod ~4h, staging ~2h, dev ~1h
Order: dev → staging → prod (smallest blast radius first)

Risk mitigations:
  - PDBs on all critical workloads — drain will respect them
  - HPA may scale up during drain if traffic-driven — let it
  - StatefulSets: ordered termination, watch for stuck pods
  - Persistent volumes: should rebind, validate per-StatefulSet

Rollback: not applicable (going back means accepting CVE exposure).
  If patch causes workload failures, mitigate by scaling other replicas.

Communication:
  - Started: post in #platform + #engineering-leadership
  - Per-cluster done: post in #platform
  - Done: email to security, close CHG
```

### Set up the simulation

```bash
# Workloads with various shapes that drain has to handle correctly
kubectl create deployment web-stateless --image=nginx:1.25 --replicas=4
kubectl create deployment app-with-pdb --image=nginx:1.25 --replicas=3
kubectl rollout status deploy/web-stateless --timeout=60s
kubectl rollout status deploy/app-with-pdb --timeout=60s

# PDB on the second one — this is what makes drain interesting
cat > /tmp/pdb.yaml <<'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: app-with-pdb }
spec:
  minAvailable: 2
  selector: { matchLabels: { app: app-with-pdb } }
EOF
kubectl apply -f /tmp/pdb.yaml

# A StatefulSet for ordered drain behavior
cat > /tmp/sts.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: data }
spec:
  clusterIP: None
  selector: { app: data }
  ports: [{ port: 80 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: data }
spec:
  serviceName: data
  replicas: 2
  selector: { matchLabels: { app: data } }
  template:
    metadata: { labels: { app: data } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
EOF
kubectl apply -f /tmp/sts.yaml
kubectl rollout status statefulset/data --timeout=120s
```

You now have 3 workload types on the agent: Deployment, Deployment-with-PDB, StatefulSet.

---

## Your job

### Step 1 — Pre-flight (don't skip)

```bash
# Workloads at desired replicas?
kubectl get deploy,statefulset

# PDBs sane?
kubectl get pdb

# All pods Running?
kubectl get pods -o wide

# Critical: how many pods are on the agent? They'll all need to move.
kubectl get pods --field-selector spec.nodeName=k3d-lab-agent-0
```

### Step 2 — Communication: opening status

In `incidents/cab-CHG-2026051401-EMRG.md` write:

```
[09:00] CAB opened. Patch CVE-2026-XXXX. Starting on dev cluster (k3d-lab).
        47 nodes total across 3 clusters; lab equivalent is 1 worker node.
        ETA: 30 min for lab, 4–8h for full prod fleet.
```

### Step 3 — Cordon

```bash
kubectl cordon k3d-lab-agent-0
kubectl get nodes
# k3d-lab-agent-0 should show "SchedulingDisabled"
```

Existing pods stay running on the cordoned node; new pods won't land there.

### Step 4 — Drain

```bash
kubectl drain k3d-lab-agent-0 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=300 \
  --timeout=10m
```

Watch what happens:

- The Deployment pods get evicted, the Deployment controller creates replacements on the server node
- The PDB-protected Deployment evicts pods one at a time, respecting `minAvailable: 2`
- The StatefulSet pod terminates, then is recreated on the server node (its PV stays, identity preserved)

**Drain may pause when PDBs are tight.** Don't `--force` past it. The PDB exists for a reason.

### Step 5 — Validate (this is the part juniors skip)

```bash
# All pods rescheduled?
kubectl get pods -o wide
# All on k3d-lab-server-0 now (or whatever your node was)

# Workloads back to desired replicas?
kubectl get deploy,statefulset
# READY = DESIRED for everything

# StatefulSet identity preserved?
kubectl get pods -l app=data -o wide
# data-0, data-1 — same names, just different node
kubectl get pvc -l app=data
# data-data-0, data-data-1 — same PVCs, still bound

# No errors in events?
kubectl get events --sort-by=.lastTimestamp | tail -15

# Synthetic check
kubectl run smoke --rm -it --image=busybox -- wget -qO- web-stateless || true
```

### Step 6 — Simulate the "node replaced with patched image"

In a real cloud (AKS/EKS/GKE), you'd terminate the VM and let the autoscaler launch a fresh one with the new image. In the lab:

```bash
# Pretend the node was replaced — uncordon brings it back to service
kubectl uncordon k3d-lab-agent-0
kubectl get nodes

# Pods will not automatically rebalance back. That's fine —
# the cluster autoscaler / scheduler handles balance on next pod creation.
```

In your runbook, note this: **K8s does not auto-rebalance after uncordon.** You can use `descheduler` or `kubectl drain && uncordon` cycles to move pods back, but most teams accept the imbalance and let next deploy / scale-up rebalance organically.

### Step 7 — Communication: closing status

```
[09:32] Lab cluster patched. Validation:
        - All Deployments at desired replicas
        - StatefulSet pods preserved identity, PVCs rebound
        - PDBs respected during drain — drain paused 90s on app-with-pdb
        - No Warning events in last 10 min
        Moving to staging cluster (in real run).
```

### Step 8 — Cleanup

```bash
kubectl delete deploy web-stateless app-with-pdb
kubectl delete statefulset data
kubectl delete svc data
kubectl delete pdb app-with-pdb
kubectl delete pvc -l app=data
```

---

## End-of-day artifacts

- [ ] CAB completion report at `07-pe-sim/incidents/cab-completion-CHG-2026051401-EMRG.md`
- [ ] Runbook `07-pe-sim/runbooks/RUN-node-drain.md`:
  - Pre-flight checklist
  - Cordon → drain → validate → uncordon flow
  - PDB-handling decision tree (when to wait, when to talk to app team about temp relax)
  - StatefulSet-specific handling (stuck pod cases, PV detach delays)
  - DaemonSet handling (`--ignore-daemonsets`)
  - Timing expectations (per-node drain ~1–5 min, depends on PDBs)
- [ ] Runbook `07-pe-sim/runbooks/RUN-cluster-upgrade.md` — borrow from drain runbook, add the kubeadm-side steps from `02-labs/WEEK5.md` § Lab 27 (concept-level, you don't run those)
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **Cordon before drain.** Otherwise, a pod evicted from the draining node could land right back on it before drain finishes.
2. **`--force` is not the answer to a stuck drain.** Stuck = PDB is doing its job OR a pod has a finalizer that hasn't released. Investigate, don't bulldoze.
3. **DaemonSet pods aren't drained** because they're tied to nodes. `--ignore-daemonsets` says "I know, that's expected".
4. **Per-cluster timing dominates.** A drain that takes 2 min in dev takes 30 min in prod with real PDBs and real traffic. Don't promise prod times based on dev observations.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Did pre-flight before any cordon | |
| Validation step covered all 3 workload types (Deployment, PDB-protected, StatefulSet) | |
| Status communication had timestamps and was 1-line per update | |
| Runbook accounts for stuck-PDB and stuck-StatefulSet branches | |

Target Day 11 average: 2.8.

---

## Tomorrow

Day 12 — Wednesday mid-week retro + on-call sim 1. You run `sim-page.sh`, don't peek, debug, postmortem. Set a 30-min timer.

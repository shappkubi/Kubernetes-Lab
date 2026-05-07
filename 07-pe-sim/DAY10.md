# Day 10 — SEV2 Page: node MemoryPressure, multi-pod evictions

**Theme:** Node-level (not pod-level) failure. Mitigation has multiple options — choose deliberately. RCA points back at a deploy from earlier in the day, not the last 5 minutes.

**Time budget:** 90–120 min.

---

## Prep (~15 min)

`03-troubleshooting/PLAYBOOK.md` § "Node NotReady" and § "OOMKilled".

`02-labs/WEEK4.md` § Lab 19 (requests/limits/QoS).

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Page

```
[ALERT - SEV2] aks-canada-central-prod / node-memory-pressure
Triggered: <today> 23:44:09 UTC
Cluster: k3d-lab                       (stand-in for aks-canada-central-prod)
Affected nodes: k3d-lab-agent-0
Symptom:
  - Node reporting MemoryPressure=True
  - kubelet evicting pods to reclaim memory
  - 5 pods evicted in last 10 min
  - HPA on inventory-svc scaled up triggering further pressure
Affected services: inventory-svc, recs-svc (pod evictions)
Recent activity:
  - inventory-svc deploy 23:30 UTC bumped memory request from 512Mi to 768Mi
  - HPA scaled from 6 to 9 replicas at 23:38 UTC
On-call: you
Customer impact: intermittent 503s on inventory and recs (degraded but not down)
```

### Set up the simulation

You only have 2 nodes in your lab; we'll simulate the pressure on the agent.

```bash
# Baseline: a deployment that fits comfortably
kubectl create deployment inventory --image=nginx:1.25 --replicas=2 \
  --dry-run=client -o yaml | \
  sed '/spec:$/,/^kind:/{
       s|        name: nginx|        name: nginx\n        resources:\n          requests:\n            memory: 200Mi\n          limits:\n            memory: 400Mi|
       }' | \
  kubectl apply -f -
kubectl rollout status deploy/inventory --timeout=60s

# Create the "deploy that bumped memory" scenario — too-large requests
kubectl set resources deploy/inventory --requests='memory=2Gi' --limits='memory=3Gi'
kubectl rollout status deploy/inventory --timeout=60s || true

# Some pods will go Pending because the agent doesn't have 2Gi schedulable memory
kubectl get pods -l app=inventory -o wide

# Plus stress on the node from chaos pods (simulating real workload pressure)
for i in 1 2 3; do
  kubectl run mem-stress-$i --image=polinux/stress --restart=Never \
    --overrides='{"spec":{"containers":[{"name":"stress","image":"polinux/stress","args":["stress","--vm","1","--vm-bytes","200M","--vm-hang","1"]}]}}' \
    >/dev/null 2>&1 || true
done
```

The combination — bigger requests on inventory + stress pods — should put the agent into a memory-tight state visible in `kubectl top`.

---

## Your job

### Step 1 — Triage

```bash
kubectl get nodes
kubectl describe node k3d-lab-agent-0 | grep -A5 'Conditions:'
kubectl top nodes
kubectl top pods -A --sort-by=memory | head -15
```

Look for:

- `MemoryPressure: True` in node Conditions
- Top pods by memory — who's eating the node?
- Recent events: `kubectl get events -A --sort-by=.lastTimestamp | grep -E 'Evicted|MemoryPressure'`

### Step 2 — Mitigation options (write this comparison in the incident log)

You have several knobs. Pick **one** to mitigate quickly.

| Option | Pros | Cons |
|---|---|---|
| **Cordon the bad node, drain it** | Immediate — pods reschedule, node settles | Other node may now also pressure |
| **Scale down a non-critical workload** | Frees memory directly | Has to be a workload that won't fight back |
| **Force-evict low-priority pods** | Targeted — only kills disposable | Need PriorityClasses set up first (you don't have them) |
| **Scale node pool** | Real fix in the long term | Slow (~2 min for new node), and you can't in lab |
| **Roll back the deploy that bumped memory** | Addresses root cause | Takes longer than just stopping the bleeding |

For the sim, the pragmatic mitigation: **roll back inventory's resource bump**, since it's the direct correlation.

```bash
kubectl set resources deploy/inventory --requests='memory=200Mi' --limits='memory=400Mi'
kubectl rollout status deploy/inventory
```

Or in real life: `kubectl rollout undo deploy/inventory`.

Then drop the chaos pods you injected:

```bash
kubectl delete pod -l run=mem-stress-1 mem-stress-1 mem-stress-2 mem-stress-3 --force --grace-period=0 2>/dev/null || true
kubectl delete pod mem-stress-1 mem-stress-2 mem-stress-3 --force --grace-period=0 2>/dev/null || true
```

### Step 3 — Verify

```bash
kubectl describe node k3d-lab-agent-0 | grep -A2 MemoryPressure   # MemoryPressure: False
kubectl top nodes                                                  # memory pct down
kubectl get events -A --sort-by=.lastTimestamp | grep -E 'Evicted' | tail -5
# (no new evictions in last 5 min)
```

### Step 4 — RCA: who's responsible?

The page said the inventory deploy at 23:30 bumped memory. Confirm:

```bash
kubectl rollout history deploy/inventory
# Should show the resource bump revision
```

Now: was the bump justified? In real life: was inventory actually using 768Mi, or did someone overshoot?

In your postmortem, the action item is NOT "block the team from bumping memory". It's:

- Was there a load-test before the change? If not — process gap.
- Did node-level capacity get reviewed pre-change? If not — process gap.
- Is there an admission policy that flags resource changes >20%? If not — recurrence prevention candidate.

### Step 5 — Cleanup

```bash
kubectl delete deploy inventory
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] Incident log + postmortem
- [ ] Runbook `07-pe-sim/runbooks/RUN-node-pressure.md`:
  - The 4-option mitigation matrix (cordon/drain, scale workload, force-evict, scale pool)
  - The diagnostic ladder
  - When to roll back the offending deploy vs handle node-side
  - PriorityClass and pod priority — what they would do here if you had them
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **Node-level pressure is rarely about *one* pod.** It's the sum of asks. Look at the recent change AND the existing tenants together.
2. **Cordon-and-drain is a hammer.** Use it for "I need this node out NOW for a security or hardware reason." For pressure, often the lighter move (scale a tenant down, roll back a deploy) is right.
3. **Eviction order is QoS-driven.** BestEffort (no requests) goes first. Burstable next. Guaranteed last. If your service was BestEffort and "got evicted unfairly", the answer is to make it Burstable or Guaranteed.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Identified MemoryPressure condition before just "scaling something" | |
| Chose mitigation option deliberately, with reasoning | |
| RCA points at the deploy AND the missing process control | |
| Action items address the *process gap*, not just the technical fix | |

Target Day 10 average: 2.7.

---

## Monday is the start of week 2 of the sim. Mid-week retro time on Wednesday (Day 12).

## Tomorrow

Day 11: an emergency CAB — critical CVE in the kernel. Patch all worker nodes inside 24h. Drain, replace, validate, communicate. This is the most-asked-about scenario in interviews after CrashLoopBackOff.

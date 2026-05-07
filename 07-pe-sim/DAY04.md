# Day 4 — SEV2 Page: pods CrashLoopBackOff, no recent deploy

**Theme:** No correlation handed to you. The system was fine, then it wasn't. This is harder — you have to find what changed.

**Time budget:** 90–120 min.

---

## Prep (~10 min)

`03-troubleshooting/PLAYBOOK.md` § "CrashLoopBackOff" and § "OOMKilled". Especially the difference: CrashLoop = container exited non-zero; OOMKilled = kernel killed it because it hit the memory limit.

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
[ALERT - SEV2] payments-prod / pod-crashloop-multi
Triggered: <today> 11:14:55 UTC
Service: web                          (stand-in)
Namespace: default
Cluster: k3d-lab
Symptoms:
  - 2 of 3 pods in CrashLoopBackOff
  - Service endpoints reduced to 1
  - Customer error rate climbing (now 12%)
  - Recent activity: nothing in last 6h (no obvious trigger)
On-call: you
Bridge: zoom://platform-incident-bridge
```

"Nothing in the last 6h" is a classic — except *something* changed; the question is finding it. In real life: cluster autoscaler scaled, a node restarted, certs rolled, a CronJob ran, a sidecar's image pull rotated, etc.

### Inject the failure

Pick one (don't tell yourself which):

```bash
# Option A — memory limit too low, causing OOMKill
kubectl scale deploy/web --replicas=3
kubectl rollout status deploy/web --timeout=60s
kubectl patch deploy/web --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "image":"polinux/stress",
    "command":["stress"],
    "args":["--vm","1","--vm-bytes","100M","--vm-hang","1"],
    "resources":{"requests":{"memory":"32Mi"},"limits":{"memory":"32Mi"}}
  }]}}}}'

# Option B — bad command (process exits immediately)
kubectl scale deploy/web --replicas=3
kubectl rollout status deploy/web --timeout=60s
kubectl patch deploy/web --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "image":"busybox",
    "command":["sh","-c","echo starting; sleep 2; exit 1"]
  }]}}}}'

# Option C — startup probe failure (slow start, killed mid-init)
kubectl scale deploy/web --replicas=3
kubectl rollout status deploy/web --timeout=60s
kubectl patch deploy/web --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "image":"nginx:1.25",
    "livenessProbe":{"httpGet":{"path":"/","port":80},
                     "initialDelaySeconds":1,"periodSeconds":2,"failureThreshold":1}
  }]}}}}'
```

(Option C is subtle — nginx starts fast enough you usually won't trip it on its own. To make it real, also add `"command":["sh","-c","sleep 5; nginx -g 'daemon off;'"]` so the process delays past the liveness deadline.)

---

## Your job

### Step 1 — Triage tree (in this order, no skipping)

```bash
kubectl get pods -l app=web                    # which pods, how many, status
kubectl get pods -l app=web -o wide            # which nodes — same node? cluster-wide?
kubectl describe pod <crashing-one> | tail -30 # Last State + Events — the gold
kubectl logs <crashing-one> --previous          # what did the dead container say?
kubectl get events --sort-by=.lastTimestamp | tail -25
```

### Step 2 — Read the description carefully

The four signals from `describe`:

| Last State / Reason | Meaning |
|---|---|
| `Error, Exit Code: 1+` | App threw on startup. Read --previous logs. |
| `OOMKilled, Exit Code: 137` | Memory limit hit. Bump limit or fix leak. |
| `Reason: Completed` but liveness fails | Container ran fine, liveness killed it for slow response. Check probe. |
| `Failed to start container` events | Spec issue (bad command, missing volume, bad image). |

### Step 3 — Mitigate

- Memory issue → raise limit OR `kubectl rollout undo` if a recent deploy lowered it
- Bad command → `kubectl rollout undo`
- Probe issue → patch the probe to be saner OR `kubectl rollout undo`

The pattern: when in doubt, `rollout undo`. It's cheap. Then RCA on the dead RS that you can keep around.

### Step 4 — Verify and restore

```bash
kubectl rollout status deploy/web --timeout=120s
kubectl get pods -l app=web
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] Incident log
- [ ] Postmortem
- [ ] Update / write `07-pe-sim/runbooks/RUN-pod-crashloop-triage.md` — should include:
  - The "is it spec-related, runtime-related, or probe-related?" decision tree
  - The exit-code → cause mapping (1, 2, 130 SIGINT, 137 SIGKILL, 139 SEGV, 143 SIGTERM)
  - When `kubectl logs --previous` is your friend
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflex

When you read the page and "no recent deploy" is in the symptoms, your first move is **not** to assume the page is wrong — it's to look for **non-deploy changes**:

```bash
# What changed on this cluster recently? (audit log if you have one; otherwise events)
kubectl get events -A --sort-by=.lastTimestamp | tail -50
# Any nodes restart?
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].lastTransitionTime}{"\n"}{end}'
# Any HPA scaling activity?
kubectl get hpa -A
# Any recent CronJob runs?
kubectl get cronjob -A
kubectl get jobs -A --sort-by=.metadata.creationTimestamp | tail -10
```

In production, the equivalent move is "check the audit log + `kubectl events`". Train the muscle now.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Read `describe pod` before `kubectl logs` | |
| Identified the exit code and mapped it to a cause | |
| Mitigation worked on first attempt | |
| Runbook is comprehensive enough for any of the 4 patterns | |

Target Day 4 average: 2.7.

---

## Tomorrow

Day 5: NetworkPolicy gone wrong. A security team change broke pod-to-pod calls. You'll need `nicolaka/netshoot` for the first time.

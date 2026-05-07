# Day 13 — On-call simulation 2: stacked failures (drift + readiness regression)

**Theme:** The hard one. Two failures stacked, both contributing to the customer impact. You have to triage *which* to fix first, why, and not get tunnel-visioned on the more visible one.

**Time budget:** 90–120 min.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Page (multi-symptom)

```
[ALERT - SEV1] checkout-prod / multi-failure
Triggered: <today> 02:14:33 UTC
Symptoms:
  1. ArgoCD app `checkout-svc-prod` showing OutOfSync (drift since 01:50)
  2. Readiness probe failure rate climbing on checkout-svc pods
  3. Service endpoints dropping — 4 of 8 pods now NotReady
  4. Customer error rate climbing (0.2% → 8% in 10 min)

Audit:
  - 01:50 UTC: ArgoCD self-heal disabled by @alex.dev (no reason logged)
  - 01:53 UTC: kubectl patch on deployment/checkout-svc — readinessProbe path
              changed from /health to /healthz
  - 02:10 UTC: pods rolling, new pods failing /healthz (path doesn't exist on app)
  - 02:14 UTC: page fired

On-call: you
Customer impact: degrading rapidly, ~30% of checkouts failing
Bridge: zoom://platform-incident-bridge (Alex joined, woken up)
```

### Set up the simulation

```bash
# Baseline — "production" running fine
kubectl create deployment checkout --image=nginx:1.25 --replicas=8 \
  --dry-run=client -o yaml > /tmp/baseline.yaml
kubectl apply -f /tmp/baseline.yaml

# Add a working readiness probe on /
kubectl patch deploy/checkout --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "readinessProbe":{"httpGet":{"path":"/","port":80},
                      "initialDelaySeconds":1,"periodSeconds":2}
  }]}}}}'
kubectl expose deploy/checkout --port=80
kubectl rollout status deploy/checkout --timeout=120s

# === 02:14 — TWO FAILURES INJECTED SIMULTANEOUSLY ===

# Failure 1: ArgoCD-equivalent drift — "in-cluster has been edited"
# (We can't actually run ArgoCD; we represent drift by saying:
#  the file in 02-labs/checkout-baseline.yaml is what should be running,
#  but the cluster has had probe path changed.)

# Failure 2: readinessProbe pointing at a path that doesn't exist
kubectl patch deploy/checkout --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "readinessProbe":{"httpGet":{"path":"/healthz","port":80},
                      "initialDelaySeconds":1,"periodSeconds":2,"failureThreshold":2}
  }]}}}}'

# Wait a bit for the rollout to roll the new probe into pods
sleep 10
kubectl get pods -l app=checkout
```

You should now see most pods `0/1 NotReady` because nginx returns 404 on `/healthz`.

---

## Your job

### Step 1 — Triage IN ORDER, not in parallel

The temptation: panic-fix both. The senior move: **pick the one that gets customers back fastest, then unwind the other.**

Customer impact = readiness regression (errors climbing). The drift / disabled self-heal is a process problem; the bad probe is the immediate technical cause.

**Mitigate the readiness regression first.**

```bash
# Confirm the diagnosis
kubectl get pods -l app=checkout
# Most are 0/1
kubectl describe pod $(kubectl get pod -l app=checkout -o name | head -1) | grep -A3 'Readiness'
# Probe path = /healthz
kubectl get endpoints checkout
# Few or none

# Mitigation: rollback the probe
kubectl rollout undo deploy/checkout
kubectl rollout status deploy/checkout --timeout=120s

# Verify recovery
kubectl get endpoints checkout
# All 8 IPs back
kubectl get pods -l app=checkout
# All 1/1
```

### Step 2 — Status update mid-incident

```
[02:18] Acknowledged. Confirmed readiness probe regression on checkout-svc.
        Rolling back deploy via kubectl rollout undo.
[02:21] Rollback complete. Endpoints populated. Customer error rate dropping.
        Investigating the drift / self-heal-disabled side now.
```

### Step 3 — Now address the second failure (drift / self-heal)

The probe regression is fixed. But the *root cause* of the page is bigger: someone disabled self-heal at 01:50 (so the manual change at 01:53 wasn't auto-reverted), and made an unreviewed manual edit.

In the incident log, write:

```
[02:25] Talking to @alex.dev on bridge:
  Q: Why was self-heal disabled?
  A: Was investigating a flaky deploy yesterday, forgot to re-enable it.
  Q: Why was the readiness probe patched manually?
  A: Wanted to test a new health endpoint we're adding next sprint, didn't
     realize the app didn't expose it yet. Was going to revert in 5 min.
```

Decide:

- **Re-enable self-heal immediately.** This is a control plane state, not customer-impacting per se, but the absence of self-heal is what allowed the regression to roll. Re-enable: in real ArgoCD, this is a `kubectl patch` on the Application CR. In the sim, write what you'd do.
- **File a ticket on the policy gap.** Disabling self-heal should require a "expires_at" annotation that auto-re-enables it. Or require an emergency override flow. Add to `improvements.md`.

### Step 4 — Verify both fixes

```bash
# Customer impact
kubectl get endpoints checkout                    # 8 IPs
kubectl run smoke --rm -it --image=busybox -- wget -qO- checkout
# nginx HTML

# Drift
diff <(kubectl get deploy/checkout -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}') <(echo "/" && false) || true
# Path is back to /

# Self-heal: in real ArgoCD, you'd verify Application's syncPolicy.automated.selfHeal=true
```

### Step 5 — Cleanup

```bash
kubectl delete deploy checkout
kubectl delete svc checkout
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] Live incident log
- [ ] Postmortem at `07-pe-sim/incidents/postmortem-YYYY-MM-DD-oncall-sim-2.md` covering BOTH failures + the prioritization decision
- [ ] Update `RUN-pod-crashloop-triage.md` and `RUN-drift-investigation.md` with what you learned
- [ ] Two new items in `improvements.md`:
  1. Enforce annotation `expires_at` on `syncPolicy.automated.selfHeal=false`
  2. CI policy: `kubectl patch` outside of git requires a change-cause annotation
- [ ] 3 learnings — focus on the "two stacked failures" prioritization
- [ ] Commit + push, stop

---

## Senior reflexes

1. **In a multi-symptom page, fix the customer-impacting thing first.** Process problems can wait 30 minutes; bleeding revenue can't.
2. **"Forgot to re-enable" is a culture problem, not a person problem.** Don't blame Alex. Build the safeguard so the next person can't forget either.
3. **Two failures usually have a common ancestor.** In this case, the missing self-heal was the *enabling condition* for the readiness regression to bite. The fix is at the enabling layer, not just the symptom.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Triaged in priority order (customer impact first) | |
| Communicated to Alex without blame | |
| Postmortem covers both failures + the prioritization | |
| Recurrence prevention targets the *control plane*, not just the symptom | |

Target Day 13 average: 3.0 (this is the capstone drill).

---

## Tomorrow — final day

Day 14 is your readiness check + retro. Self-assess against the 7-item checklist. Write the 2-week retro. Decide what to keep doing.

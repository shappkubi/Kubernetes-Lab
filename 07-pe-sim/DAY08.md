# Day 8 — Page from Argo Rollouts: canary metric gate failed

**Theme:** Progressive delivery is working as designed (rollout aborted automatically). Your job is to figure out why the canary was unhealthy, communicate to the developer, and decide next steps.

**Time budget:** 60–90 min.

---

## Prep (~20 min)

`02-labs/WEEK6.md` § Lab 34 (Canary Deployments). Especially the difference between manual canary (replica counts) and Argo Rollouts (real percentage routing + analysis).

You won't install Argo Rollouts today — the drill simulates the *aftermath* of a canary abort. The investigation is the same regardless of tooling.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Page (from Argo Rollouts notification)

```
[ROLLOUT ABORTED] checkout-prod / canary-metric-gate-failed
Triggered: <today> 21:14:55 UTC
Service: checkout-svc
Rollout: checkout-svc → v2.5.0 (canary)
Step: setWeight 25% (was at step 3 of 5)
Metric: success-rate (Prometheus: rate(http_requests_total{status=~"2.."}) / rate(http_requests_total))
Threshold: >= 99.5%
Measured (canary pods): 96.2%
Measured (stable pods): 99.7%
Decision: rollout auto-aborted, traffic shifted back to v2.4.1
Affected canary pods: terminated
Recent activity: rollout started 21:00 UTC by @dave via ArgoCD
On-call: you (notified, no immediate customer impact since auto-rollback worked)
```

### Set up the simulation

The canary is gone (auto-rolled back), but you need to inspect the canary pods' logs and determine WHY. Simulate that the canary version was pushing 5xx:

```bash
# Create the rolled-back stable
kubectl create deployment checkout --image=nginx:1.25 --replicas=4 \
  --dry-run=client -o yaml | \
  sed 's/  template:/  selector:\n    matchLabels: { app: checkout }\n  template:/' | \
  kubectl apply -f -
kubectl expose deploy/checkout --port=80
kubectl rollout status deploy/checkout --timeout=60s

# Spin up the canary that "failed" — short-lived, with bad behavior
# We'll keep one pod to investigate
kubectl run checkout-canary --image=nginx:1.27 \
  --labels=app=checkout-canary,version=v2.5.0 \
  --restart=Never \
  --command -- sh -c 'echo "starting"; nginx -g "daemon off;" &
                       sleep 30 &
                       for i in $(seq 1 10); do
                         echo "[$(date)] simulating 5xx burst" >&2
                         sleep 3
                       done
                       wait' || true

# (In real life the canary pods are gone; here we keep one to inspect logs)
```

---

## Your job

### Step 1 — Confirm the rollback was clean

A "rollout aborted" page is good — auto-rollback did its job. But you still verify:

```bash
kubectl get pods -l app=checkout
# All on the stable version, healthy

kubectl get pods -l app=checkout-canary
# Should be 0 (canary terminated by Argo Rollouts) — in our sim, the one we spun up

kubectl get rs -l app=checkout
# Stable RS at desired replicas, no canary RS hanging around

kubectl get endpoints checkout
# Populated with stable pod IPs only
```

If anything's stuck (a canary pod still in Terminating, an orphan ReplicaSet, traffic split still misconfigured), fix it before doing anything else. **Auto-rollback that didn't fully clean up = silent half-failure.**

### Step 2 — Read the canary's logs

```bash
kubectl logs checkout-canary 2>/dev/null || kubectl logs --previous checkout-canary
```

In real life: `kubectl logs <canary-pod> --previous` or pull from your central logging system. The point: **you need to know what went wrong on the canary**, even though Argo Rollouts already aborted it.

### Step 3 — Describe what failed

Was it:
- Endpoint-specific (e.g. /checkout breaks but /healthz fine — a code regression)?
- Full-pod failures (every request 5xx — a config or dependency issue)?
- Performance regression (latency spike pushed timeouts)?
- Dependency change (new lib crashed under real traffic)?

You don't have full Prometheus in the sim. In real life, you'd pull:

```promql
sum(rate(http_requests_total{deployment="checkout-canary",status=~"5.."}[5m])) by (path, status)
```

In the sim, write what you'd query. The question matters more than the syntax.

### Step 4 — Decide and communicate

You have three reasonable next steps. Pick one and document why.

| Option | When |
|---|---|
| Re-canary with the same image after a small fix | Cause was config (DB URL, env var) or deploy-related, easy to correct |
| Hold v2.5.0 in staging for deeper testing | Cause was a real regression, needs the dev cycle |
| Promote the rollback to a release branch | Stable is fine; we don't actually need v2.5.0 yet |

Send Dave the report. Practice the message in your incident log:

```
@dave — checkout v2.5.0 canary was auto-aborted at 21:14 UTC. Stable is back, customer impact 0.

Root cause from canary logs: [paste the actual signal you found].

Next step: I recommend [option]. Want to chat tomorrow morning?
```

### Step 5 — Cleanup

```bash
kubectl delete pod checkout-canary
kubectl delete deploy checkout
kubectl delete svc checkout
```

---

## End-of-day artifacts

- [ ] Incident log with the (simulated) findings + your recommendation
- [ ] Runbook `07-pe-sim/runbooks/RUN-canary.md`:
  - Step-by-step canary execution (setWeight 5/25/50/100, with analysis gates)
  - What to do when a canary aborts (validate cleanup → investigate → recommend)
  - Common reasons canaries fail: regression in prod-only path, real-traffic-only bug, dependency mismatch, performance under real load
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **An auto-aborted canary is a *success of the system*, not a failure.** Don't treat it as a fire — treat it as a signal that the gate worked.
2. **Always validate the rollback is clean** — orphan canary pods are silent risk.
3. **Don't re-canary the same image without a fix** — re-canarying after auto-abort without changing anything is throwing the dice again.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Validated rollback cleanup before investigating | |
| Categorized the failure type (regression, perf, dep, config) | |
| Recommendation to Dave was specific, not "let's discuss" | |
| Runbook captures the 3-option decision tree | |

Target Day 8 average: 2.7.

---

## Tomorrow

Day 9: Black Friday capacity planning. Marketing wants 8x normal traffic. You're the platform engineer signing off (or pushing back) on what the cluster can handle.

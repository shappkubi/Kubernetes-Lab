# Day 6 — Jira: deploy v1.2 of checkout (blue/green)

**Theme:** Planned work, not an incident. Senior PEs spend 70% of their time on planned work — deployments, capacity, runbooks, automation. Triage is the loud minority. Today: blue/green deployment from scratch.

**Time budget:** 60–90 min.

---

## Prep (~15 min)

If you haven't covered blue/green yet, read:

- `02-labs/WEEK6.md` § Lab 34 — Canary Deployments (the manual canary section explains the dual-Deployment pattern that's the backbone of blue/green too)
- `05-interview-prep/03-whiteboard-scenarios.md` doesn't have a blue/green write-up; the comparison from your Day 3 conversation in chat is in `learnings.md` if you saved it. Otherwise: blue/green = two parallel Deployments, Service selector flip, instant rollback.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Jira ticket (what you find in your queue)

```
JIRA: CHK-1842
Type: Deployment task
Priority: P3 (planned)
Reporter: @dave.checkout
Assignee: you
Summary: Deploy checkout-svc v1.2.0 to staging

Description:
  v1.2.0 includes:
    - New feature flag for express checkout (default OFF)
    - Performance fix for cart calculation (CHK-1799)
    - Updated dependency: spring-boot 3.2.4 → 3.2.5 (CVE-2026-XXXX patch)

  Image: nginx:1.27 (stand-in for registry.pcfin.io/checkout/checkout-svc:1.2.0)
  Manifest PR: github://infra/k8s-manifests/pull/417
  Strategy: blue-green via Service selector swap

Pre-deploy checklist (all required):
  - [ ] Image scan passed (Trivy report attached)
  - [ ] Staging smoke tests passed in CI
  - [ ] Performance tests passed (no regression vs v1.1)
  - [ ] Feature flag default-OFF confirmed
  - [ ] On-call notified
  - [ ] Rollback plan documented

Validation in staging:
  - All 3 replicas healthy after deploy
  - / returns 200 for 5 min
  - Synthetic checkout test passes (CHK-monitor)
  - Error rate < 0.1% for 10 min observation window

If staging validation passes for 2h, file CHG ticket for prod deploy.
```

### Senior PE move BEFORE running anything

Reply on the Jira ticket with clarifying questions and what's missing — practice the intake step. Write these in `incidents/intake-CHK-1842.md`:

- "I see image and PR but no link to the Trivy scan output. Please attach."
- "What's the rollback signal? If error rate >0.5% during the 10-min window, do we auto-revert or wait for human call?"
- "Is the feature flag controlled by an env var on the new pods, or via an external service? If external, the cutover is decoupled from this deploy."
- "Should I tag-cleanup the old (v1.1) Deployment after 2h soak, or keep it idle for fast rollback?"

That's the senior version of "going through a checklist". You don't blindly check boxes — you confirm each one.

---

## Your job

### Step 1 — Set up the blue side (current production = v1.0 stand-in)

```bash
# Blue Deployment + Service. Note the version label on pods.
kubectl create deployment checkout-blue --image=nginx:1.25 --replicas=3 --dry-run=client -o yaml \
  | sed 's/    spec:/    metadata:\n      labels:\n        app: checkout\n        version: blue\n    spec:/' \
  | kubectl apply -f -

# (Or skip the sed and just edit by hand — see below for the cleaner manifest)
```

Cleaner: write `02-labs/blue-green.yaml` with both Deployments + the Service. Save this:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-blue
spec:
  replicas: 3
  selector:
    matchLabels: { app: checkout, version: blue }
  template:
    metadata:
      labels: { app: checkout, version: blue }
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 2
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-green
spec:
  replicas: 0                     # green starts at 0 — we scale it up before flipping
  selector:
    matchLabels: { app: checkout, version: green }
  template:
    metadata:
      labels: { app: checkout, version: green }
    spec:
      containers:
        - name: web
          image: nginx:1.27       # stand-in for v1.2.0
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 2
---
apiVersion: v1
kind: Service
metadata:
  name: checkout
spec:
  selector: { app: checkout, version: blue }     # currently routing to blue
  ports: [{ port: 80, targetPort: 80 }]
```

Apply:

```bash
kubectl apply -f 02-labs/blue-green.yaml
kubectl rollout status deploy/checkout-blue
```

### Step 2 — Smoke test blue (current state)

```bash
kubectl run smoke --rm -it --image=busybox -- wget -qO- checkout
# nginx HTML
```

### Step 3 — Bring up green at full size, but no traffic

```bash
kubectl scale deploy/checkout-green --replicas=3
kubectl rollout status deploy/checkout-green
```

Verify green pods are healthy **without traffic**:

```bash
kubectl get pods -l app=checkout,version=green
# All 3 Ready

# Smoke test green directly using a port-forward (Service still routes to blue)
GREEN_POD=$(kubectl get pod -l version=green -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward pod/$GREEN_POD 8080:80 &
sleep 2
curl http://localhost:8080
# nginx HTML — green is alive
kill %1
```

### Step 4 — The flip (the actual deploy)

This is one command. The instant-rollback property comes from the Service knowing both colors are running.

```bash
kubectl patch svc/checkout --type=merge -p '{"spec":{"selector":{"app":"checkout","version":"green"}}}'
```

Verify traffic is now hitting green:

```bash
kubectl get endpoints checkout
# Should show only the green pod IPs

kubectl run smoke --rm -it --image=busybox -- wget -qO- checkout
# nginx HTML (still works, but now from green pods)
```

### Step 5 — Soak / observation window

Real deploy: monitor error rate and latency for 10 min before declaring success. In sim, simulate the watch:

```bash
# In one terminal — watch endpoints staying healthy
kubectl get endpoints checkout -w &

# In another — synthetic check loop
for i in $(seq 1 30); do
  kubectl run smoke-$i --rm --image=busybox --restart=Never -- wget -qO- --timeout=2 checkout >/dev/null && echo "OK $i" || echo "FAIL $i"
  sleep 2
done
```

If any FAIL during the window, abort:

```bash
kubectl patch svc/checkout --type=merge -p '{"spec":{"selector":{"app":"checkout","version":"blue"}}}'
```

That single command is the rollback. Instant.

### Step 6 — Decommission blue (only after soak passes)

DON'T do this for hours in real production — you might still need to flip back. In the sim:

```bash
kubectl scale deploy/checkout-blue --replicas=0
```

Keep the blue Deployment object around until the next deploy (when green becomes "blue" for purposes of the next round).

### Step 7 — Cleanup

```bash
kubectl delete deploy checkout-blue checkout-green
kubectl delete svc checkout
```

---

## End-of-day artifacts

- [ ] Intake clarification doc at `07-pe-sim/incidents/intake-CHK-1842.md` — the questions you'd have asked Dave before deploying
- [ ] Runbook `07-pe-sim/runbooks/RUN-blue-green.md` covering:
  - The 7 steps from above
  - Decision criteria for "soak passes" vs "abort"
  - Comparison: blue/green vs rolling vs canary (3-row table)
  - Cost note: 2x infra during cutover, ~30 min before you can scale blue down
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **Bring green up healthy *before* flipping**. Don't do `replicas: 3` at the same time as the selector flip. You want green proven good with 0 traffic risk first.
2. **The flip is one command — but the validation around it is 10 commands.** That's the work.
3. **Don't kill blue immediately after the flip.** It's your fast-rollback path. Keep it scaled up during the soak window.
4. **Document the rollback as one command, not a paragraph.** When you panic, paragraphs don't run.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Pre-deploy checklist questioned, not just rubber-stamped | |
| Green validated with zero traffic before the flip | |
| Rollback was a single command you tested in advance | |
| Runbook makes the next deploy a 5-minute task | |

Target Day 6 average: 2.7.

---

## Tomorrow

Day 7: GitOps drift investigation. ArgoCD detected a manual edit on a production Deployment. Don't just revert. Talk to humans.

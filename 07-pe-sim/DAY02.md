# Day 2 — SEV2 Page: web service throwing 503s

**Theme:** Your first real page. The classic "service has no endpoints" pattern. By the end of the day you should be able to triage a 503 alert in under 5 minutes.

**Time budget:** 90–120 min (drill + runbook + postmortem).

---

## Prep (~15 min)

If you haven't already covered Services and Endpoints, skim `02-labs/WEEK1.md` § Lab 4 (Services & kube-proxy). Specifically:

- ClusterIP, what an Endpoints / EndpointSlice is, what kube-proxy does
- The classic "selector doesn't match labels" failure mode
- The 30-second debug ladder

Also re-read `03-troubleshooting/PLAYBOOK.md` § "Service has endpoints but I can't reach it" and § "Service has no endpoints".

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

Compare today's output to yesterday's. Anything different? Same restart counts? Same baseline pods?

---

## Today's intake

### Page (received in PagerDuty)

```
[ALERT - SEV2] checkout-prod / http-5xx-rate-high
Triggered: <today's date> 14:02:11 UTC
Service: checkout-svc
Namespace: default                    ← in real prod this would be checkout-prod
Cluster: k3d-lab                      ← stand-in for aks-canada-central-prod
Metric: nginx_ingress_controller_requests{status=~"5.."} rate(5m)
Threshold: > 1% for 3m
Current value: 12.7% and rising
Affected: 87% of requests to /
Recent deploys:
  - web v2.4.1 deployed 13:48 UTC via ArgoCD (14 min ago)
  - PR #2841 by @dave (manifests for new feature flag)
Linked dashboard: grafana://checkout/health
Runbook: confluence://runbooks/RUN-checkout-5xx
On-call: you
Customer impact: ~1800 failed checkouts in last 5 min, ~$45K GMV at risk
Bridge: zoom://platform-incident-bridge (Dave joined, business stakeholder pinged)
```

### Inject the failure (this is your "production")

Pick **one** of these, don't tell yourself which one was used (it's the drill):

```bash
# Option A — selector mismatch
kubectl patch svc/web --type=merge -p '{"spec":{"selector":{"app":"nope"}}}'

# Option B — readiness probe failing
kubectl patch deploy/web --type=merge -p '{
  "spec":{"template":{"spec":{"containers":[{
    "name":"nginx",
    "readinessProbe":{"httpGet":{"path":"/does-not-exist","port":80},
                      "initialDelaySeconds":1,"periodSeconds":3,"failureThreshold":2}
  }]}}}}'
kubectl rollout status deploy/web --timeout=60s || true
```

Don't peek at which one you ran. Treat the cluster as "production with an unknown problem".

(Trick: the `cat ~/.bash_history | tail -20` after the drill will tell you which one if you really need to know.)

---

## Your job (talk through this in your head before typing)

### Step 1 — Acknowledge and start a live incident log

Open `07-pe-sim/incidents/incident-$(date +%F-%H%M).md` and seed it from `templates/incident-log-template.md`. **Before** you start triaging, jot the first timeline line.

### Step 2 — Clarifying questions you'd ask the bridge

Write these in the incident log too. A senior PE never rushes to action without confirming the picture. Examples for this kind of page:

- Is the alert real (do customers actually see 503s, or is it just the metric)?
- Is it 100% of pods or a subset?
- Is it correlated with the deploy or did the metric pre-date it?
- Was anything else changed in the last 4 hours?
- What's the rollback decision authority — you, or do you need Dave/release captain?

### Step 3 — Mitigate, then RCA

Mitigation order (this is the senior pattern):

1. **Stop the bleeding before understanding.** If a deploy correlates within 15 minutes of the alert, the default move is `kubectl rollout undo deploy/web` — don't wait for RCA.
2. Verify recovery: error rate drops, endpoints populate, synthetic check passes.
3. Update the bridge ("Mitigated. Investigating root cause now.").
4. Then run the RCA on a non-burning system.

Run the diagnosis ladder for "service returning 503s":

```bash
kubectl get svc/web
kubectl get endpoints web                       # CRITICAL — is it empty?
kubectl get pods -l app=web -o wide             # are they Ready?
kubectl describe pod <one of them> | tail -25   # readiness failures? recent restarts?
kubectl describe svc web | head -20             # selector vs pod labels?
```

Empty `Endpoints` is the smoking gun. From there:

- If `kubectl get pods -l app=web` returns 0 pods → label/selector mismatch on the Service
- If pods are present but `READY 0/1` → readiness probe is failing → check probe path

### Step 4 — Fix the root cause cleanly

If selector mismatch (Option A):
```bash
kubectl patch svc/web --type=merge -p '{"spec":{"selector":{"app":"web"}}}'
```

If readiness probe failure (Option B):
```bash
# Either point the probe at an endpoint that exists, or remove it.
kubectl patch deploy/web --type=json \
  -p '[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]'
# Then bump revision so pods restart with the new spec
kubectl rollout restart deploy/web
kubectl rollout status deploy/web
```

### Step 5 — Verify

```bash
kubectl get endpoints web                          # should now have IPs
kubectl run probe --rm -it --image=busybox -- wget -qO- http://web      # should print nginx HTML
```

### Step 6 — Restore the cluster fully

```bash
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] **Live incident log** at `07-pe-sim/incidents/incident-YYYY-MM-DD-HHMM.md` with timestamps for every observation, hypothesis, and action
- [ ] **Postmortem** at `07-pe-sim/incidents/postmortem-YYYY-MM-DD-503s.md` from `templates/postmortem-template.md`
- [ ] **Runbook** at `07-pe-sim/runbooks/RUN-service-no-endpoints.md` — codify the diagnosis ladder you just ran
- [ ] **3 learnings** in `07-pe-sim/learnings.md`
- [ ] Commit + push, `bash stop.sh`, stop Codespace

---

## Status updates you should have posted to the bridge (during the drill)

If you didn't, write what you would have. Aim for 4–5, one sentence each, timestamped:

```
[14:03] Acknowledged. Investigating endpoints on checkout-svc.
[14:06] Endpoints empty. Checking pod readiness.
[14:09] Pods Running but NotReady — readiness probe pointing at /does-not-exist. Suspect deploy v2.4.1.
[14:12] Rolling back to previous revision via kubectl rollout undo.
[14:15] Endpoints populated, error rate dropping. Monitoring 5-min recovery window.
[14:21] Recovered. Postmortem to follow within 24h.
```

---

## Self-grading

| Item | 1–3 |
|---|---|
| Time from page-acknowledged to recovery | (target: <15 min) |
| Did you mitigate before fully diagnosing? | (correct answer: yes) |
| Did you check `kubectl get endpoints` before logs? | (correct answer: yes — events/endpoints first, then logs) |
| Postmortem includes a non-trivial action item | |
| Runbook is concrete enough that you wouldn't have to think next time | |

Target Day 2 average: 2.5.

---

## Tomorrow

Day 3: a pod stuck in `ImagePullBackOff` after an HPA scale-up. Lower severity, but a different muscle — registry, secrets, network paths.

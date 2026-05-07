# Day 3 — SEV3 Page: pod stuck in ImagePullBackOff

**Theme:** A subtler page. No customer impact yet — but capacity is at risk. By the end you should be able to read a `kubectl describe pod` events block and diagnose any pull failure in 30 seconds.

**Time budget:** 60–90 min.

---

## Prep (~10 min)

Re-read `03-troubleshooting/PLAYBOOK.md` § "ImagePullBackOff / ErrImagePull" for the four flavors of pull error.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

Today there's a deliberate anomaly hidden in your cluster — does the morning check catch it?

---

## Today's intake

### Page

```
[ALERT - SEV3] orders-prod / pod-stuck-imagepullbackoff
Triggered: <today> 16:22:08 UTC
Service: web                          (stand-in for orders-svc)
Namespace: default                    (stand-in for orders-prod)
Cluster: k3d-lab
Pod: web-7c4b6f9d-xyz12
State: ImagePullBackOff for 8 min
Image: nginx:does-not-exist
Replicas: 4 desired, 3 ready (1 stuck)
Recent activity: HPA scaled up from 3 to 4 at 16:14
Linked dashboard: grafana://orders/health
Runbook: confluence://runbooks/RUN-pod-imagepullbackoff (incomplete)
On-call: you
Customer impact: none yet (3 healthy replicas), but capacity at risk if HPA scales further
```

### Inject the failure

```bash
# Make sure we have a healthy baseline first
kubectl scale deploy/web --replicas=3 || kubectl create deployment web --image=nginx:1.25 --replicas=3
kubectl rollout status deploy/web --timeout=60s

# Inject the ImagePullBackOff
kubectl scale deploy/web --replicas=4
kubectl set image deploy/web nginx=nginx:does-not-exist
```

You'll get 3 healthy nginx:1.25 pods + 1 stuck on the bad image. The Deployment surge math from Lab 3 means you actually end up with at least 2 stuck — that's expected.

---

## Your job

### Triage in 30 seconds

```bash
kubectl get pods -l app=web -o wide
```

You'll see 3 Running on `nginx:1.25` and some in `ImagePullBackOff`. Pick a bad pod:

```bash
BAD=$(kubectl get pods -l app=web --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')
kubectl describe pod $BAD | tail -25
```

The Events section is the answer. Read the message. Map it to one of the four flavors:

| Message contains | Cause | Fix |
|---|---|---|
| `manifest unknown` / `not found` | Tag doesn't exist | Fix the image tag |
| `pull access denied` / `unauthorized` | Bad / missing imagePullSecret | Create or attach correct secret |
| `i/o timeout` / `dial tcp` | Network — node can't reach registry | Check egress / firewall / DNS to registry |
| `no space left` | Disk pressure on the node | Clean image cache, scale node disk |

Today's drill should give you flavor #1.

### Mitigation (don't think — act)

If the rolled image is bad and there's no proven good replacement at hand:

```bash
kubectl rollout undo deploy/web
kubectl rollout status deploy/web
```

That's the senior move when the deploy is the proven correlation. ~30 seconds to recovery.

### Verify

```bash
kubectl get pods -l app=web
# All Running on the previous image
kubectl get rs -l app=web
# Bad RS scaled to 0, good RS at desired count
```

### Restore baseline

```bash
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] Incident log at `07-pe-sim/incidents/incident-YYYY-MM-DD-HHMM.md`
- [ ] Postmortem at `07-pe-sim/incidents/postmortem-YYYY-MM-DD-image-pull.md`
- [ ] Runbook at `07-pe-sim/runbooks/RUN-image-pull-debug.md` — should include the four-flavor table from above
- [ ] 3 learnings
- [ ] Commit + push, `bash stop.sh`

---

## Senior reflex worth practicing

**Don't `kubectl logs` a pod that's never been Running.** It'll fail or be empty — the container hasn't started, there's nothing to log. The right tool for "pod won't start" is `kubectl describe pod`. Logs are for "pod started but is misbehaving".

This is the kind of thing a junior wastes 5 minutes on. A senior moves to `describe` immediately.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Time to identify the exact pull error | (target: <60s) |
| Mitigation chosen (rollback) was correct first move | |
| Runbook covers all four pull-error flavors with example messages | |
| You did NOT waste time on `kubectl logs` for a never-Running pod | |

Target Day 3 average: 2.5.

---

## Tomorrow

Day 4 is harder: a deployment in CrashLoopBackOff with no recent deploy. No correlation handed to you. You'll have to find it.

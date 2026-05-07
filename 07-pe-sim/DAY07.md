# Day 7 — Investigation: GitOps drift on a prod Deployment

**Theme:** A page-equivalent that's NOT an outage. Someone bypassed git and made a manual change to production. The work is half forensics, half conversation. The senior move is to investigate before reverting.

**Time budget:** 60–90 min.

---

## Prep (~20 min — has lab content)

If you haven't covered ArgoCD yet, read `02-labs/WEEK6.md` § Lab 31 (Argo CD).

You don't need to install ArgoCD today (we'll do that next time it makes sense). The drill simulates an ArgoCD detection — your job is to investigate the *drift* and decide what to do.

End-of-week is also retro time. After the drill, do the Friday retro at the bottom.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Investigation ticket

```
JIRA: PLAT-3601
Type: Investigation
Priority: P2
Reporter: @argocd-monitor (auto-generated)
Assignee: you
Summary: Production Deployment drifting from Git — manual edit detected

Description:
  ArgoCD detected drift on Application `inventory-svc-prod`:
    - In-cluster: replicas=8, image=nginx:1.27
    - In Git: replicas=4, image=nginx:1.25
  Drift detected at <today> 14:22 UTC
  Self-heal is OFF for this app (manual sync only)

  Audit log shows:
    - 14:18 UTC, principal=alex.dev@company.io, action=patch deployment/inventory-svc
    - Reason field: "(empty)"

Investigation needed:
  - Why was the manual change made?
  - Is the change correct (and Git should be updated to match)?
  - Or is Git correct (and we should revert the cluster)?
  - Is this a recurring pattern from this principal?

Suggested resolution paths:
  1. Talk to Alex, understand why
  2. If the change was right: PR to update Git
  3. If the change was wrong: ArgoCD sync to revert
  4. Either way: incident review on why bypass happened
  5. Policy review: should we enforce Git-only changes via OPA/Kyverno?

Acceptance:
  - Drift resolved
  - Decision documented
  - Recurrence prevention either implemented or filed
```

### Set up the simulation

```bash
# "Git-tracked" baseline — what the manifest in git looks like
cat > 02-labs/inventory-svc.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-svc
  labels: { app: inventory }
spec:
  replicas: 4
  selector:
    matchLabels: { app: inventory }
  template:
    metadata:
      labels: { app: inventory }
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
EOF
kubectl apply -f 02-labs/inventory-svc.yaml
kubectl rollout status deploy/inventory-svc

# "Alex's manual change" — drift introduced
kubectl scale deploy/inventory-svc --replicas=8
kubectl set image deploy/inventory-svc web=nginx:1.27
kubectl rollout status deploy/inventory-svc
```

Now you have a real drift to investigate.

---

## Your job

### Step 1 — Detect and quantify the drift

Don't just trust the ticket — confirm. The manual diff between cluster and git:

```bash
# Live state
kubectl get deploy inventory-svc -o yaml > /tmp/cluster.yaml

# Git state (the manifest you saved)
cat 02-labs/inventory-svc.yaml > /tmp/git.yaml

# Diff (focusing on the relevant fields)
diff <(kubectl get deploy inventory-svc -o jsonpath='{.spec.replicas}') <(grep replicas 02-labs/inventory-svc.yaml | head -1 | awk '{print $2}')
diff <(kubectl get deploy inventory-svc -o jsonpath='{.spec.template.spec.containers[0].image}') <(grep image 02-labs/inventory-svc.yaml | head -1 | awk '{print $2}')
```

Or just compare visually:

```bash
kubectl get deploy inventory-svc -o yaml | grep -E 'replicas:|image:'
grep -E 'replicas:|image:' 02-labs/inventory-svc.yaml
```

Confirm: replicas 8 vs 4, image nginx:1.27 vs nginx:1.25.

### Step 2 — Look at the audit log (or what you have)

In a real cluster, you'd `grep alex.dev` in the audit log. In the lab, look at recent events:

```bash
kubectl get events -A --sort-by=.lastTimestamp | grep -i inventory | tail -10
```

You won't see the user — k3d audit logging isn't enabled by default. Note this in your runbook as "real cluster has audit log; lab doesn't".

### Step 3 — Talk to Alex (in your incident log, write the conversation you'd have)

In `incidents/incident-YYYY-MM-DD-drift.md`, write:

```
[14:30] Slack DM to @alex.dev:
  "Hey Alex — ArgoCD flagged drift on inventory-svc-prod. Cluster has replicas=8, image=nginx:1.27;
   git has replicas=4, image=nginx:1.25. Audit log shows you patched it at 14:18.
   What was the change for? I want to make sure we don't roll back something that needed to be there."

[14:35] @alex.dev replies:
  "Sorry — Black Friday traffic test scheduled for tomorrow, need temp capacity bump.
   Was going to PR it but couldn't get past the manifest review timing. Image bump was a typo
   while editing — meant to leave it at 1.25."

[14:38] Decision:
  - replicas=8 is INTENTIONAL but bypassed process. Keep the bump but PR it to git.
  - image=1.27 is UNINTENTIONAL. Revert.
  - Recurrence prevention: file ticket for OPA policy preventing manual patches without
    a "change-cause" annotation.
```

That's the senior pattern. **Investigate. Talk. Decide. Document.**

### Step 4 — Execute the decision

Two parts:

**Part A — revert the unintentional image change.**

If using ArgoCD: trigger a sync. Without ArgoCD installed: `kubectl apply` from the manifest:

```bash
kubectl set image deploy/inventory-svc web=nginx:1.25
kubectl rollout status deploy/inventory-svc
```

**Part B — update git to match the intentional capacity change.**

Edit `02-labs/inventory-svc.yaml` to change `replicas: 4` → `replicas: 8`. Commit:

```bash
git add 02-labs/inventory-svc.yaml
git commit -m "PLAT-3601: bump inventory-svc to 8 replicas for BF traffic test (was manual patch)"
git push
```

In real life, this would be a PR Alex approves. In the sim, you committed it directly.

### Step 5 — Verify alignment

```bash
kubectl get deploy inventory-svc -o jsonpath='{.spec.replicas}'   # 8
grep replicas 02-labs/inventory-svc.yaml                          # 8
# Match — drift resolved
```

### Step 6 — File the recurrence-prevention ticket

In `improvements.md`, add:

```
- [ ] PLAT-3650: enforce change-cause annotation on Deployment patches via Kyverno policy
  (drives manual changes through git or at minimum makes them auditable)
```

### Step 7 — Cleanup

```bash
kubectl delete deploy inventory-svc
rm 02-labs/inventory-svc.yaml
git add 02-labs/inventory-svc.yaml
git commit -m "Day 7 cleanup"
```

---

## End-of-day artifacts

- [ ] Incident log with the simulated conversation (this is the artifact — practicing how you'd handle it)
- [ ] Runbook `07-pe-sim/runbooks/RUN-drift-investigation.md`:
  - When to revert immediately vs investigate first
  - The diff commands
  - The "what to ask the human" template
  - When to update git vs when to revert cluster
- [ ] 3 learnings
- [ ] `improvements.md` updated with the recurrence-prevention item
- [ ] Commit + push, stop

---

## Friday retro (do this before stop.sh)

End of week 1 of the sim. In `learnings.md` add a short retro section:

```
## Week 1 retro
- What surprised me this week: ...
- Which runbook did I actually use vs just write: ...
- Which day was hardest, and why: ...
- One thing to do differently next week: ...
- One improvement I closed: ...
```

---

## Senior reflexes

1. **Drift is rarely just "git is right".** Often someone made a manual change for a real reason (capacity, emergency hotfix, troubleshooting they forgot to revert). Investigate the why before deciding how.
2. **The fix is two parts: revert the wrong thing, codify the right thing in git.** Don't conflate them.
3. **Recurrence prevention is the deliverable**, not the immediate fix. The fix takes 30 seconds; the policy ticket is what stops this happening 50 more times.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Did NOT just revert reflexively | |
| Decision separated "intentional vs unintentional" components | |
| Recurrence-prevention ticket filed with concrete proposal | |
| Postmortem identifies the *process* gap, not just the technical drift | |

Target Day 7 average: 2.7. Cumulative average through week 1: 2.5+.

---

## Weekend

Don't run drills. Read your week's postmortems. Notice patterns. Read 1–2 chapters of *Site Reliability Engineering* (free at sre.google) — pick "How SRE Relates to DevOps" or "Embracing Risk".

Day 8 (Monday): Argo Rollouts canary that auto-aborted. Investigate why.

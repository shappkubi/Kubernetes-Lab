# Day 1 — Onboarding & First Morning Check

**Theme:** Set up the muscle and the artifacts that the next 13 days depend on. No incident today; you're getting the bench ready.

**Time budget:** 60–90 min.

---

## Morning ritual (this is what you'll do every morning from now on)

```bash
bash resume.sh                        # cluster up
chmod +x 00-setup/morning-check.sh \
         00-setup/sim-page.sh \
         00-setup/restore.sh
bash 00-setup/morning-check.sh
```

Read every section of the morning check output:

- Are nodes Ready?
- Are any pods not Running/Completed?
- Any Warning events in the last hour?
- Are any Deployments off their desired replica count?

You're not investigating anything yet. You're learning what "normal" looks like in your cluster so when something is abnormal tomorrow, your eyes catch it instantly.

The script writes to `00-setup/logs/health-YYYY-MM-DD.log` — that file becomes your personal observability dataset over 14 days. Compare day to day.

---

## Today's tasks (in order)

### 1. Bootstrap the lab fixtures the sim assumes

Some drills assume there's a `web` Deployment + Service in the `default` namespace. Create it:

```bash
kubectl create deployment web --image=nginx:1.25 --replicas=3
kubectl expose deployment web --port=80
kubectl rollout status deploy/web
kubectl get all -l app=web
```

Verify in the next morning check that this deploys cleanly.

### 2. Write your first runbook — `RUN-morning-check.md`

Use `07-pe-sim/templates/runbook-template.md` as the starting point. Save your version to `07-pe-sim/runbooks/RUN-morning-check.md`.

Document:

- **When to use:** every morning, first thing
- **Inputs:** none — just need a working kubectl context
- **Pre-checks:** confirm `kubectl config current-context` is `k3d-lab`
- **Execute:** the actual command (`bash 00-setup/morning-check.sh`)
- **Verify (what "OK" looks like):** all 8 sections pass, exit code 0, last line says "cluster healthy"
- **Decision points:** what to do if NOT_READY > 0, BAD > 0, deploy drift detected
- **Known gotchas:** metrics-server takes ~30s after cluster start before `kubectl top` works

This first runbook is short and easy. You'll write it 4 more times in 14 days, and the pattern will become automatic.

### 3. Pick 2 improvements for the week

Open `07-pe-sim/improvements.md`. Move 2 items from the "Ideas" section into "Open" — pick ones that match where you are. Reasonable picks for week 1:

- Wire `morning-check.sh` to also tail to a local file you can `git diff` (compare morning-to-morning)
- Add a `kustomize` overlay for staging vs prod copy of the `web` Deployment

You don't have to finish them today. Just commit to them.

### 4. Run the destructive scripts in dry-run mode (don't execute, just read them)

You will run `sim-page.sh` on Day 12 and 13. Read it now while it's calm:

```bash
cat 00-setup/sim-page.sh
cat 00-setup/restore.sh
```

Internalize:

- What kinds of failures it injects (pod kill, scale to zero, bad image, CPU chaos, deny-all NetworkPolicy, broken readiness, wrong selector)
- That it refuses to run if the context isn't `k3d-lab` or `kind-lab-kind` (so you can't accidentally page production)
- That `restore.sh` is the rollback button — always run it after a drill

### 5. End-of-day artifacts

- [ ] `07-pe-sim/runbooks/RUN-morning-check.md` filled in
- [ ] `07-pe-sim/improvements.md` has 2 items in "Open"
- [ ] `07-pe-sim/learnings.md` has Day 1 entry with 3 bullets
- [ ] Morning check log saved at `00-setup/logs/health-YYYY-MM-DD.log`
- [ ] Commit + push:
  ```bash
  git add .
  git commit -m "Day 1: PE sim bootstrap + first runbook"
  git push
  ```
- [ ] `bash stop.sh`, then stop Codespace from the menu

---

## Self-grading

| Item | Score 1–3 |
|---|---|
| Morning check ran clean, log readable | |
| Runbook is concrete (not vague), someone else could follow it | |
| Improvements are specific, not generic | |
| Learnings name three things that actually surprised you, not "I learned how to use kubectl" | |

Target Day 1 average: 2.0. You're warming up.

## Tomorrow

Day 2 is your first real page. SEV2, web service is throwing 503s, recent deploy correlates. Triage in 30 minutes. Get sleep.

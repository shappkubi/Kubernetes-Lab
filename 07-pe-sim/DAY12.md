# Day 12 — Mid-week retro + On-call simulation 1 (random failure)

**Theme:** Wednesday is mid-week — pause and look at trend. Then a real drill: you don't know what's broken, the page is generic, you have 30 minutes.

**Time budget:** 60–90 min.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

Compare today's `00-setup/logs/health-YYYY-MM-DD.log` to Day 1's. What's different? Restart counts? New workloads? Any drift you notice?

Write a quick note in `learnings.md` Day 12 entry: "Compared morning checks Day 1 vs Day 12 — noticed [X]."

---

## Mid-week retro (10 min, before the drill)

Open `learnings.md`. Add a short section:

```
## Mid-week retro (Day 12)
- What's been hardest so far: ...
- What runbook have I actually USED (vs just written): ...
- Which day felt rushed / incomplete: ...
- One adjustment for the rest of the sim: ...
```

Then look at `improvements.md`:

- Did I close the items I committed to on Day 1?
- If not, why not? Genuine block, or just didn't make time?
- Reset for the rest of the week.

---

## Today's drill — On-call sim 1

This is the closest the sim gets to a real on-call experience. You don't know what failure was injected. Set a timer. Go.

### Drill protocol

1. **Confirm context** — never ever run `sim-page.sh` against the wrong cluster:
   ```bash
   kubectl config current-context
   # Must be k3d-lab
   ```

2. **Start a 30-minute timer.**

3. **Open a fresh incident log:**
   ```bash
   vi 07-pe-sim/incidents/incident-$(date +%F-%H%M).md
   ```
   Seed it with the template content from `templates/incident-log-template.md`.

4. **Run the page:**
   ```bash
   bash 00-setup/sim-page.sh
   ```
   The script will print a `[PAGE]` and inject ONE random failure. **Don't peek at which one** (the script does print a hint, but cover that line — your terminal scrollback is the real adversary).

5. **Triage. Mitigate first, RCA second.** Use everything you've built — runbooks 1–8, the playbook, your reflexes.

6. **Status updates**: post one in your incident log every 5 min, even if "no progress, still investigating".

7. **Stop the clock when:**
   - All pods Running
   - Service endpoints populated
   - `kubectl get events --sort-by=.lastTimestamp | tail -10` shows no new Warnings

8. **Restore fully:**
   ```bash
   bash 00-setup/restore.sh
   ```

9. **Write the postmortem.** Save as `07-pe-sim/incidents/postmortem-YYYY-MM-DD-oncall-sim-1.md`.

---

## What the drill covers

`sim-page.sh` randomly picks one of:

| Failure | What you'll see |
|---|---|
| Random pod kill | One web pod missing; Deployment recreates it. Easy. |
| Scale to zero | `web` Deployment at 0 replicas. Endpoints empty. |
| Bad image | Latest pod stuck in ImagePullBackOff. |
| CPU chaos | Node CPU pegged, top pods shows the chaos pod hot. |
| Deny-all NetPol | Apparent connectivity failure (won't actually enforce on flannel). |
| Broken readiness probe | Pods Running but `0/1`, endpoints empty, service unreachable. |
| Wrong service selector | Endpoints empty, pods are all healthy. |

If you've done Days 1–11 well, your reflexes are now:

```
1. Read events / describe first
2. Check service endpoints early
3. Check recent changes (rollout history, NetPols, audit log)
4. Mitigate before fully diagnosing
5. Verify recovery on a synthetic test, not just on the get-pods table
6. Write the postmortem from your live log
```

---

## End-of-day artifacts

- [ ] Live incident log with timestamped events
- [ ] Postmortem at `07-pe-sim/incidents/postmortem-YYYY-MM-DD-oncall-sim-1.md`
- [ ] Update one of your existing runbooks if the drill exposed a gap
- [ ] 3 learnings (this one's easy: what surprised you in the drill?)
- [ ] Commit + push, stop

---

## Self-grading

| Item | 1–3 |
|---|---|
| Time from page to mitigation | (target: <15 min) |
| Used existing runbooks rather than re-thinking | |
| Postmortem written within 30 min of recovery | |
| Action item filed for the gap the drill exposed | |

Target Day 12 average: 2.8.

If your time-to-mitigation was >25 min, identify which runbook was missing or had a gap. Add to `improvements.md`.

---

## Tomorrow

Day 13: on-call sim 2 — but this one is *stacked*. Two failures, not one. Real production rarely fails alone.

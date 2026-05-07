# Day 14 — Readiness check + 2-week retro

**Theme:** Stop, count what you've built, grade yourself honestly. The artifacts are the proof of work.

**Time budget:** 60 min.

---

## Morning ritual (last time as a sim — keep doing it forever)

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

Compare to Day 1's log. Difference is your skill drift in your favor.

---

## Step 1 — Count the artifacts

Run from the project root:

```bash
echo "=== PE Sim 2-Week Audit ==="
echo "Runbooks committed:"
ls -1 07-pe-sim/runbooks/RUN-*.md 2>/dev/null | wc -l
ls -1 07-pe-sim/runbooks/RUN-*.md 2>/dev/null

echo
echo "Postmortems committed:"
ls -1 07-pe-sim/incidents/postmortem-*.md 2>/dev/null | wc -l
ls -1 07-pe-sim/incidents/postmortem-*.md 2>/dev/null

echo
echo "Live incident logs committed:"
ls -1 07-pe-sim/incidents/incident-*.md 2>/dev/null | wc -l

echo
echo "Improvements:"
echo "  Closed: $(grep -c '^\- \[x\]' 07-pe-sim/improvements.md 2>/dev/null || echo 0)"
echo "  Open:   $(grep -c '^\- \[ \]' 07-pe-sim/improvements.md 2>/dev/null || echo 0)"

echo
echo "Days with learnings entries:"
grep -c '^## Day' 07-pe-sim/learnings.md 2>/dev/null || echo 0

echo
echo "Morning check logs (one per day = ideal):"
ls -1 00-setup/logs/health-*.log 2>/dev/null | wc -l
```

Targets:

- Runbooks: **8+**
- Postmortems: **5+**
- Closed improvements: **2+**
- Days with learnings: **14**
- Morning check logs: **14** (1 per day)

If you're missing some, that's fine for now — but write down which ones. They become next-cycle's homework.

---

## Step 2 — Day 14 readiness checklist (self-assess honestly)

For each, answer with concrete proof from your repo:

- [ ] **Morning check is reflex, under 5 min** → How do I know? Last 5 days of `health-*.log` show I ran it before doing anything else.
- [ ] **I can deploy + verify a service in under 5 min** → Proof: `RUN-blue-green.md` is concrete enough; I executed Day 6 in X minutes.
- [ ] **I can blue-green and roll back without consulting notes** → Proof: I memorized the Service selector flip; rollback is one command.
- [ ] **I can diagnose pod-not-running issues in under 60 seconds** → Proof: Day 12 sim took me Y minutes from page to identification of the failure type.
- [ ] **I can write a postmortem in under 15 min** → Proof: Day 13 postmortem timestamp was X min after recovery.
- [ ] **At least 8 runbooks committed** → Yes / No
- [ ] **At least 5 postmortems committed** → Yes / No
- [ ] **At least 2 closed items in `improvements.md`** → Yes / No
- [ ] **My Day 1 log vs Day 14 log shows obvious skill drift in my favor** → diff them and write 1 line of evidence

Score: how many of 9 boxes are checked?

- 7+ → ready to walk into a real PE job
- 5–6 → ready, but identify the gap and close it
- ≤4 → you have the structure but need more reps; don't fake-graduate

---

## Step 3 — 2-week retro

Save as `07-pe-sim/RETRO.md`. Cover:

```markdown
# 2-Week PE Sim Retro

## Top 3 surprises
1.
2.
3.

## Strongest day, why
What clicked that hadn't before?

## Weakest day, why
Where did the artifact feel forced or shallow? What would a real senior do differently?

## Mental models that stuck
List 3–5 things you can now explain cold that you couldn't on Day 1.
- ...
- ...

## Mental models still fuzzy
Honest. Things you still nodded along to but couldn't whiteboard.
- ...
- ...

## What I would change about the sim if I ran it again
- More drills involving git-side workflows (PR review, merge conflicts on manifests, etc.)?
- More cross-team comms drills (talking to security/dev like Day 5/13 forced)?
- More planning, less firefighting? Or vice versa?

## What I'd keep doing forever
- Morning check
- Postmortem after every drill, even smooth ones
- Adding 1 thing/week to improvements.md
- ...

## What I'd drop
- ...

## One concrete next thing
What's the SINGLE highest-leverage habit to keep going? Don't pick five. Pick one.
```

---

## Step 4 — Update memory

This step is for me, not you — but you should know what's saved. Your Cowork memory file at `MEMORY.md` should now reflect that you've completed the 2-week PE sim and what your skill state is. (I'll update it.)

---

## Step 5 — Commit + push + stop

```bash
git add .
git commit -m "Day 14: PE sim retro + readiness check"
git push
bash stop.sh
```

Stop the Codespace.

---

## What's next

You have two reasonable paths from here:

**Path A — keep operating the lab as production.** Run morning-check daily, do one drill a week, write one runbook a week, close one improvement a month. The structure is now self-sustaining.

**Path B — go deeper on one area.** Pick the topic that felt weakest (probably one of: GitOps, networking, observability, security). Find the matching `02-labs/WEEK*.md` content and spend 1–2 weeks just there. Build 3–4 runbooks specifically for that area.

Either is right. Both is best.

The sim was scaffolding. The reflex it built is yours forever — it transfers to any cluster, any team, any company.

Don't tell yourself the sprint is over and let the morning check slide. The drop-off after sprints is the most expensive thing in skill development. Keep the daily ritual.

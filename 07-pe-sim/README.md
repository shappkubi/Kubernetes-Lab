# 2-Week Platform Engineer Simulation

This is a 14-day prescribed program that gives you the **shape** of a real platform engineer's day — pages, deploys, capacity reviews, CABs, postmortems — using your existing K8s lab cluster as the production system. Each day has a specific intake (a page, a Jira ticket, a CAB request), and your job is to handle it end-to-end the way a senior PE would.

By Day 14, your reflexes (not just your knowledge) should look like someone who's been at this for years.

## Why this exists

The 6-week curriculum (`01-curriculum/ROADMAP.md`) builds depth — you'll know what an HPA does, how a Service routes, what a NetworkPolicy enforces. The **sim** builds reflexes — when someone pages you about 503s at 02:00, your hands move before your brain panics. Two different muscles. You need both.

## Daily flow (memorize this)

```
1. Open Codespace, run resume.sh                       (~2 min)
2. Run morning-check.sh — log it                       (~5 min)
3. Read DAY{N}.md from this folder                     (~5 min)
4. Read today's intake (the page / ticket / CAB)       (~5 min)
5. Write clarifying questions you'd ask                (~10 min)
6. Execute the work — narrate via status updates       (variable)
7. Write the artifact (runbook update, postmortem)     (~30 min)
8. Add 3 bullets to learnings.md                       (~5 min)
9. Commit, push, run stop.sh, stop Codespace
```

If a day takes 60 min, great. If it takes 3 hours, also fine — operations are non-deterministic. Don't fake-finish; fully complete each artifact before moving on.

## Day index

| Day | Theme | Intake type | Output artifact |
|---|---|---|---|
| 1 | Setup the PE sim infrastructure + first morning check | n/a — onboarding | `RUN-morning-check.md`, learnings entry |
| 2 | Web service 503s | SEV2 page | `RUN-service-no-endpoints.md` + postmortem |
| 3 | Pod ImagePullBackOff | SEV3 page | `RUN-image-pull-debug.md` + postmortem |
| 4 | Pod CrashLoopBackOff with no recent deploy | SEV2 page | `RUN-pod-crashloop-triage.md` + postmortem |
| 5 | Inter-service connectivity broken (NetworkPolicy) | SEV2 page | `RUN-network-policy-debug.md` + postmortem |
| 6 | Deploy v1.2 of checkout to staging (blue/green) | Jira deployment | `RUN-blue-green.md` |
| 7 | GitOps drift investigation | Investigation ticket | `RUN-drift-investigation.md` + decision doc |
| 8 | Canary metric gate failing | Page from Argo Rollouts | `RUN-canary.md` + postmortem |
| 9 | Black Friday capacity planning | Capacity request | `capacity-plan-blackfriday.md` |
| 10 | Node pressure / evictions | SEV2 page | `RUN-node-pressure.md` + postmortem |
| 11 | Critical CVE — patch all nodes | Emergency CAB | `RUN-node-drain.md` + CAB completion report |
| 12 | On-call sim 1 (random failure injection) | SEV? page from sim-page.sh | live incident log + postmortem |
| 13 | On-call sim 2 (stacked: drift + readiness regression) | SEV1 multi-failure page | live incident log + postmortem |
| 14 | Readiness check + retro | n/a | `RETRO.md`, readiness checklist |

## Folder structure

```
07-pe-sim/
├── README.md                         <-- this file
├── DAY01.md ... DAY14.md             <-- one file per day, your prescription
├── runbooks/                         <-- you write these as you go (target: 8+)
├── incidents/                        <-- live incident logs + postmortems (target: 5+)
├── templates/                        <-- runbook, postmortem, status-update templates
├── improvements.md                   <-- 1-2 added each Monday, close 1 each Friday
└── learnings.md                      <-- 3 bullets/day, no exceptions
```

## Supporting scripts (in `00-setup/`)

| Script | When to run |
|---|---|
| `morning-check.sh` | Every morning, first thing. Logs to `00-setup/logs/health-YYYY-MM-DD.log` |
| `sim-page.sh` | Days 12 and 13 (or any time you want a surprise drill). Injects a random failure |
| `restore.sh` | After any drill — brings cluster back to a known-good state |

## Standards (these are graded)

A good day produces:

1. **A runbook update or new runbook** — production reality is "first time you do it, you write it down so you never have to think again next time"
2. **A postmortem** if there was an incident — even drills get postmortems. The artifact IS the practice.
3. **Status updates with timestamps** posted in your incident log — proves you communicated, not just executed
4. **Three learnings entries** — what surprised you, what you understand now that you didn't this morning
5. **A commit** — `git add . && git commit -m "Day N: <title>" && git push`

Days where you executed correctly but produced no artifact don't count. The artifact is half the point.

## How to grade yourself at the end of each day (1–3 scale)

For each:
- **3 — production-ready**: I'd hand this runbook/postmortem to my replacement and they could run with it. Status updates are tight, decisions are explicit.
- **2 — solid trainee**: Right shape, missing some detail. A senior would help me sharpen it.
- **1 — incomplete**: Skipped sections, vague claims, no decision log.

Target: average 2.5+ by Day 7, average 3.0 by Day 14.

## Day 14 readiness checklist (the goal)

You're ready to walk in to a real PE job when:

- [ ] Morning check is reflex, under 5 min
- [ ] You can deploy + verify a service in under 5 min
- [ ] You can blue-green and roll back without consulting notes
- [ ] You can diagnose pod-not-running issues in under 60 seconds
- [ ] You can write a postmortem in under 15 min
- [ ] At least 8 runbooks committed
- [ ] At least 5 postmortems committed
- [ ] At least 2 closed items in `improvements.md`
- [ ] Your Day 1 morning-check log vs Day 14 morning-check log shows obvious skill drift in your favor

## Note on prerequisites

Some days assume Week 2–6 lab content (NetworkPolicy, ArgoCD, HPA, drain). Each day file points you to the relevant lab section as **prep** — do that prep first thing in the morning before reading the intake. You're not skipping the curriculum; you're compressing it into a real-work envelope where you learn the thing AND apply it the same day.

## What this isn't

- A real on-call rotation. Real on-call has unknown timing, real customer pressure, sleep deprivation, and consequences.
- A substitute for production experience. It's a scaffolding to have shape and reflexes by the time you're in production.
- A linear march. If a day takes you longer, take longer. If a drill bores you, write a harder follow-up. Adapt.

## Start

Open `DAY01.md`. Go.

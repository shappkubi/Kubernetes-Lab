# Day 9 — Capacity request: scale checkout for Black Friday (8x traffic)

**Theme:** Pure planning, no incident. The output is a written plan that costs money — you have to be specific about node count, headroom, and load-test acceptance criteria. This is what most senior PE work actually looks like.

**Time budget:** 90–120 min.

---

## Prep (~20 min)

`02-labs/WEEK4.md` § Labs 19, 21, 22 (requests/limits, HPA, autoscaling-design exercise).

`04-production-scenarios/SCENARIOS.md` § Scenario 8 ("Cost is exploding") for the cost-side perspective.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Capacity ticket

```
JIRA: PLAT-3578
Type: Capacity planning
Priority: P2
Reporter: @lisa.product
Assignee: you
Summary: Scale checkout for Black Friday — expected 8x normal traffic 2026-11-28

Description:
  Marketing forecasts 8x normal peak traffic for Black Friday + Cyber Monday.
  Last year we hit 95% of HPA max replicas at peak — no room.
  Request: ensure checkout-svc can scale to 12x current peak with headroom.

Current state:
  - checkout-svc HPA: min 4, max 30 replicas
  - Last year peak: 28 replicas
  - Resource requests: 500m CPU, 1Gi mem per pod
  - Resource limits:   1500m CPU, 2Gi mem per pod
  - Node pool: standard-d4s-v3 × 12 (4 vCPU + 16Gi each = 48 vCPU + 192Gi total)

Forecast for 2026:
  - Peak target: 50 replicas of checkout-svc
  - Required node capacity: ~32 vCPU just for checkout (with headroom)
  - Plus other services scaling (cart, payments, inventory)

Asks:
  - Increase HPA max to 60 (with PDB updated)
  - Increase node pool to 18 nodes
  - Pre-warm cluster autoscaler for the event window
  - Validate with load test 1 week before
  - Document scale-up + scale-down playbook

Acceptance:
  - Load test sustaining 12x normal RPS for 30 min, error rate < 0.5%
  - p99 latency < 500ms throughout
  - Postmortem-style writeup with capacity headroom evidence
```

---

## Your job

The output today is a **written capacity plan**, not commands you ran. Save it as `07-pe-sim/incidents/capacity-plan-blackfriday.md`. Cover all six sections below.

### 1. Sanity-check Lisa's math (do this before agreeing)

She says peak target is 50 replicas. Let's verify the request:

- 8x normal — fine, but normal of *what*? Of last year's peak? Of average? Get specifics.
- 50 replicas × 500m CPU request = **25 vCPU just for checkout requests**
- With limits at 1500m and HPA scaling on CPU, real consumption could spike to 75 vCPU briefly
- That's 50–75% of your current node pool's 48 vCPU **for just one service**

The other services (cart, payments, inventory) — what do they look like at 8x? Ask Lisa for their numbers too.

In your plan, write:

> "Open question to @lisa: the 50-replica figure for checkout is reasonable given the 8x scenario, but I need projections for cart/payments/inventory at the same multiplier. Without those I can't size total node pool. Can you get me their HPA + load-test ratios by EOD?"

### 2. Compute proposed node pool size

For the *checkout-only* portion:

- 50 replicas × 500m request = 25 vCPU steady
- Add 25% headroom for spikes = 31 vCPU
- Plus per-node overhead (kubelet, system pods): assume 10% per node = need ~34 vCPU schedulable
- standard-d4s-v3 has 4 vCPU each → need ~9 nodes JUST for checkout

For the whole cluster (rough — refine after Lisa's answer):

- Other services scale similarly: 2–3x more vCPU
- Total: 18–24 nodes feels right, matching Lisa's ask of 18

In your plan, **show the math**. Don't just say "18 nodes is fine" — write the computation. Senior PEs are auditable on cost.

### 3. HPA + PDB changes

```yaml
# Proposed changes (commit to git)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout
  minReplicas: 8                         # was 4 — pre-warm for event
  maxReplicas: 60                        # was 30 — Lisa's ask
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 60 }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
        - { type: Percent, value: 100, periodSeconds: 15 }
        - { type: Pods,    value: 6,   periodSeconds: 15 }
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 600     # was 300 — more conservative for event
      policies:
        - { type: Percent, value: 25, periodSeconds: 60 }
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout
spec:
  minAvailable: 6                         # was probably 2 — needs scaling with replicas
  selector:
    matchLabels: { app: checkout }
```

Save this to `02-labs/blackfriday-hpa-pdb.yaml`. Don't apply yet — capacity plans get reviewed first.

### 4. Cost surface to product

Adding 6 nodes (12 → 18) — at standard-d4s-v3 rates, that's ~$200–250/node-month in Azure. So:

- Pre-warm window: 1 week → ~$15/node × 6 nodes = ~$90
- Event week (3 days surge): ~$30
- Post-event scale-down: nodes back to 12 over 4–6 hours

**Total incremental cost for the event window: ~$120–150.** Trivial vs the GMV at risk if checkout falls over.

But — write it in the plan explicitly. Product manages a budget; engineering numbers without dollar context are unhelpful.

### 5. Load-test plan

Acceptance: 12x sustained RPS for 30 min, error rate <0.5%, p99 <500ms.

```
LOAD TEST SCHEDULE
- T-7 days: full load test in staging (or prod off-hours window)
  - Tool: k6 or Locust (whatever your team uses)
  - Pattern: ramp 0→12x over 5 min, sustain 30 min, ramp down 5 min
  - Watch:
    - HPA scaling latency (was new pod ready before throughput need?)
    - Node pool autoscaler response (did new nodes appear in under 2 min?)
    - p99 latency curve
    - Error rate breakdown by endpoint
    - Per-pod CPU + memory utilization
  - Acceptance:
    - error rate < 0.5% throughout
    - p99 < 500ms
    - HPA reached steady-state before 25 min mark
    - At least 20% headroom remaining at peak (replicas ≤ 48 of 60 max)
- T-3 days: re-test if first test failed any acceptance criterion
- T-1 day: pre-warm — bump min replicas to 8 hours before expected peak
```

### 6. Day-of runbook

Cover:

- Pre-event checklist (5 min before peak window opens)
- What to watch on dashboards
- Decision criteria for emergency scale-up (e.g. "if we hit replicas=55 of 60, page me even at 03:00")
- Decision criteria for emergency rollback (e.g. "if error rate >2% sustained 5 min")
- Communication cadence (status update every 30 min during event window)
- Post-event scale-down schedule (don't kill capacity at 23:59 on the dot — soak for 4h)

---

## End-of-day artifacts

- [ ] `07-pe-sim/incidents/capacity-plan-blackfriday.md` — the full plan with all 6 sections
- [ ] `02-labs/blackfriday-hpa-pdb.yaml` — proposed manifest changes (git, not applied)
- [ ] Runbook `07-pe-sim/runbooks/RUN-event-day-oncall.md` — the pre/during/post-event playbook
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **Push back on the request before sizing.** Lisa says "8x" — but 8x of what? What about the other services? A senior PE refuses to plan in a vacuum.
2. **Show your math on cost.** Engineering recommendations without dollar figures get rubber-stamped or ignored. With dollar figures they get debated, which is what you want.
3. **Pre-warming is cheap; cold-starts in a peak event are expensive.** Bump min replicas hours before the surge — the cost of running too many for a few hours is much less than the cost of a queue forming during the first 90 seconds.
4. **The scale-down plan is part of the plan.** Don't just "fire and forget" the scale-up; write the scale-down explicitly so you don't pay for the surge the next 5 weeks.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Math is shown, not asserted | |
| Cost in dollars is in the plan | |
| Load-test acceptance is measurable, not vague | |
| Day-of runbook has decision criteria, not just steps | |

Target Day 9 average: 2.7.

---

## Tomorrow

Day 10: nodes hitting MemoryPressure overnight. Multi-pod evictions. The interesting part is investigating *which* deploy caused it, even when nothing was deployed in the last hour.

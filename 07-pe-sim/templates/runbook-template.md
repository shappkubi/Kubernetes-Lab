# Runbook: <task name>

**Owner:** <you> | **Last updated:** YYYY-MM-DD | **SLA:** P? | **Tested:** YYYY-MM-DD

## When to use this runbook
One sentence describing the symptom or trigger.

## Inputs
- Cluster: ...
- Namespace: ...
- Service / Deployment: ...
- Anything else you need before you start

## Pre-checks (do these FIRST, abort if any fail)
- [ ] `kubectl config current-context` matches expected cluster
- [ ] Recent deploys / changes in last 4h reviewed (link)
- [ ] On-call peer notified you're running this
- [ ] Backup / snapshot taken if destructive

## Execute
Step-by-step, copy-pasteable. Annotate WHY each step.

```bash
# 1. ...
kubectl ...

# 2. ...
kubectl ...
```

## Verify (don't declare done until ALL pass)
- [ ] `kubectl get pods -l <selector>` shows N/N Running
- [ ] No new Warning events in last 5 min
- [ ] Synthetic test passes
- [ ] Customer error rate back to baseline

## Rollback
What to do if any verify step fails. Be specific.

```bash
kubectl ...
```

## Decision points / branching
- If condition X → do A
- If condition Y → do B
- If unsure → escalate to <name>

## Known gotchas
- ...
- ...

## Linked
- Postmortem(s) that drove this runbook: ...
- Related runbooks: ...
- Slack / docs: ...

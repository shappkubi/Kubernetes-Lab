# Status Update Format (when paged)

When you're on an incident, every update is one sentence. No editorializing. No apologies. Just observation → hypothesis → action → result.

## Good (use these patterns)

```
[14:02] Observed 503s on checkout-svc, no recent deploy. Investigating endpoints.
[14:06] Endpoints empty — readinessProbe failing on all 3 pods. Checking probe target.
[14:09] Probe pointing at /healthz, app exposes /health. Fixing manifest via Git.
[14:13] Manifest reverted, ArgoCD synced, pods passing readiness. Traffic restored.
[14:18] Error rate back to baseline. Closing incident, postmortem to follow.
```

## Bad (don't do these)

- "Looking into it." — useless, says nothing
- "I think it might be the database, not sure though." — uncertainty without action
- "OK so the way Kubernetes works is that..." — explaining the system to a bridge that already knows
- "Sorry for the delay everyone, just had to grab coffee." — never apologize on a bridge

## Cadence
- Every 5 minutes during active incident
- Or whenever you make a meaningful change
- Final update when resolved + when postmortem is up

## What goes in each update
1. **Observation** (what's true right now)
2. **Hypothesis** (what you think)
3. **Action** (what you're about to do)
4. **Result** (what changed)

Most updates have 2 of those, not all 4. That's fine.

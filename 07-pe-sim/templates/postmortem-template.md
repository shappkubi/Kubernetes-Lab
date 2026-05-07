# Postmortem: <one-line title>

**Date:** YYYY-MM-DD
**Duration:** HH:MM start → HH:MM resolved (X min)
**Severity:** SEV1 / SEV2 / SEV3
**Author:** <you>
**Status:** Draft / Reviewed / Closed

## Summary
Two sentences. What happened. What was the impact.

## Customer Impact
- What was affected (which service, which endpoints, which users)
- For how long (from first failed request to recovery)
- Counts (failed requests, lost revenue if applicable, SLA breach if any)
- Was data lost? Recoverable?

## Timeline (UTC)
- HH:MM — alert fired: `<metric> exceeded <threshold>`
- HH:MM — engineer (you) acknowledged
- HH:MM — observed `<X>`, hypothesized `<Y>`
- HH:MM — applied mitigation: `<action>`
- HH:MM — confirmed recovery: `<signal>`
- HH:MM — incident closed
- HH:MM — postmortem published

## Detection
- How was the issue detected? (Page / customer report / dashboard)
- Time to detect (from incident start to alert fire)
- Was the detection sufficient? Could it have been faster?

## Root Cause
What actually caused this. Not "pod crashed" — *why* did it crash.
Multiple paragraphs if needed. Walk through the chain of events.

## Why it took X minutes to resolve
- Time spent on diagnosis: ?
- Time spent on mitigation: ?
- What slowed us down? (missing runbook, unclear ownership, paged wrong person, etc.)

## What Went Well
- ...

## What Didn't Go Well
- ...

## Where We Got Lucky
- ...

## Action Items
| # | Action | Type | Owner | Due | Status |
|---|--------|------|-------|-----|--------|
| 1 | Add alert for X | Detection | you | YYYY-MM-DD | Open |
| 2 | Write runbook RUN-Y | Process | you | YYYY-MM-DD | Open |
| 3 | Patch service Z to handle case W | Code | <team> | YYYY-MM-DD | Open |
| 4 | Add validation in CI for ... | Prevention | <team> | YYYY-MM-DD | Open |

## Lessons
One-liner takeaways that should change how we operate.

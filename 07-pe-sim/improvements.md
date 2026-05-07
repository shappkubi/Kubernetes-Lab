# Improvements Backlog

Add 1–2 items every Monday. Close at least one by Friday. This is the thing that proves you're not just operating — you're investing.

## Open

- [ ]

## In progress

- [ ]

## Closed

- [x]

---

## Ideas (don't have to commit until you pull them into Open)

- Wire Prometheus + Grafana into the lab cluster, build a "cluster overview" dashboard
- Kustomize overlay for staging vs prod, run the same Deployment through both
- ArgoCD notifications to a fake Slack webhook (use webhook.site)
- A `make smoke` target that hits every Service after a deploy
- Add validating admission policy that requires resource requests on every Deployment
- Write a script that compares `helm get values <release>` to git — drift detection
- Wire the existing `morning-check.sh` into a CronJob so it runs hourly
- Add a `slo.md` per service: what's your SLO, what's the error budget, how do you alert
- Define a "platform contract" doc — what app teams can expect from you, what you expect from them

# Kubernetes Deep-Dive Lab Pack

A self-contained 6-week sprint to build deep technical Kubernetes experience and validation — architecture, troubleshooting, and real production scenarios — for someone already at the intermediate level. Built to run on a disk-constrained laptop via **GitHub Codespaces** (recommended), local k3d, or Killercoda.

## What you'll be able to do at the end

- Draw the Kubernetes architecture from memory and explain what every component does, what fails when it's down, and how `kubectl apply` becomes a running pod.
- Debug CrashLoopBackOff / ImagePullBackOff / OOMKilled / Pending / DNS / NetworkPolicy / PVC / etcd issues in under a minute each.
- Discuss multi-tenancy, autoscaling, progressive delivery, GitOps, upgrades, disaster recovery with concrete trade-offs.
- Run a clean kubeadm-style upgrade end to end.
- Pass the architecture and design portions of any K8s engineering interview.

## How to use this pack

1. **Set up your cluster.** Read `00-setup/README.md`, then `00-setup/CODESPACES.md` if going the Codespaces route. Spin up the k3d cluster.
2. **Follow the roadmap.** `01-curriculum/ROADMAP.md` is a 6-week sprint at 1–2 hrs/day. Each day points to a section in the lab files.
3. **Do the labs.** `02-labs/WEEK1.md` through `WEEK6.md`. Reflect (5 lines, your own words) at the end of every lab.
4. **Drill the troubleshooting.** `03-troubleshooting/PLAYBOOK.md` is the document you'll reread before any pager rotation or interview.
5. **Run the production scenarios.** `04-production-scenarios/SCENARIOS.md` — talk through each out loud.
6. **Pass the mock interview.** `05-interview-prep/MOCK-INTERVIEW.md` after week 6, then again a week later.

## Folder layout

```
Kubernetes Lab/
├── README.md                                      <-- you are here
├── .devcontainer/                                 <-- Codespaces config (auto-installs all tools)
│   ├── devcontainer.json
│   └── post-create.sh
├── .gitignore
│
├── 00-setup/                                      <-- spin up cluster
│   ├── README.md                                  step-by-step setup
│   ├── CODESPACES.md                              push to GitHub, open as Codespace
│   ├── 00-disk-check-and-cleanup.{sh,ps1}
│   ├── 01-k3d-config.yaml                         primary cluster (1 server + 1 agent)
│   ├── 02-create-k3d-cluster.{sh,ps1}
│   ├── 03-install-addons-k3d.{sh,ps1}             ingress-nginx, metrics-server
│   ├── 04-kind-config.yaml                        heavier 4-node config (only when needed)
│   ├── 05-create-kind-cluster.{sh,ps1}
│   ├── 06-install-addons-kind.{sh,ps1}            adds MetalLB
│   └── 99-teardown.{sh,ps1}                       run at end of EVERY session
│
├── 01-curriculum/
│   └── ROADMAP.md                                 6-week, day-by-day study plan
│
├── 02-labs/                                       hands-on labs aligned to the roadmap
│   ├── WEEK1.md                                   architecture + core workloads
│   ├── WEEK2.md                                   config, storage, networking
│   ├── WEEK3.md                                   security, RBAC, identity
│   ├── WEEK4.md                                   scheduling, autoscaling, observability
│   ├── WEEK5.md                                   failure, upgrades, disaster recovery
│   └── WEEK6.md                                   GitOps, helm, multitenancy, canary, operators
│
├── 03-troubleshooting/
│   └── PLAYBOOK.md                                15 production failures, with diagnosis steps
│
├── 04-production-scenarios/
│   └── SCENARIOS.md                               10 design + incident discussion drills
│
├── 05-interview-prep/
│   ├── 01-architecture-deep-dive.md               the diagram + 90-second narration
│   ├── 02-questions-by-topic.md                   57 Q&A across all topics
│   ├── 03-whiteboard-scenarios.md                 10 system-design prompts
│   └── MOCK-INTERVIEW.md                          end-of-sprint test
│
└── 06-manifests/                                  reference YAML library
    ├── README.md
    ├── pod.yaml
    ├── deployment.yaml
    ├── statefulset.yaml
    ├── daemonset.yaml
    ├── job.yaml
    ├── service.yaml
    ├── ingress.yaml
    ├── configmap-secret.yaml
    ├── pvc.yaml
    ├── rbac.yaml
    ├── networkpolicy.yaml
    ├── hpa-pdb-quota.yaml
    ├── securitycontext-psa.yaml
    └── gateway.yaml                               Gateway API (Ingress's successor)
```

## The disk story (for a constrained laptop)

| Path | Disk on YOUR laptop | Notes |
|---|---|---|
| GitHub Codespaces | **0 GB** | Cluster runs in the cloud container; you only need a browser |
| Local k3d 1+1 | ~0.7–1.2 GB while running | `99-teardown.{sh,ps1}` recovers it all |
| Local kind 1+3 | +2–3 GB | Only spun up for labs that explicitly need it |
| Killercoda | 0 GB | Browser-based; HA / upgrade / etcd drills run here |

End-of-session habit: run `99-teardown.{sh,ps1}` and **stop your Codespace**. That keeps free-tier usage low and your laptop clean.

## Suggested cadence

- **Mon–Fri, 1–1.5 hrs/day:** open Codespace, do the day's lab, write the 5-line reflection, push notes to git, stop Codespace.
- **Sat, 1–2 hrs:** redo the week's labs from scratch, no notes — the proof you've internalized them.
- **End of sprint:** mock interview (record audio), grade yourself, repeat in a week.

## When to deviate

- Stuck on a concept? Reread the matching section in `05-interview-prep/01-architecture-deep-dive.md` or the relevant Q&A in `02-questions-by-topic.md`.
- Concept clicked but can't articulate it? Write the 200-word "explain to a junior engineer" version. That gap closes fastest by teaching.
- Out of free Codespaces hours? Switch to local k3d for the rest of the month, or shift to scenario work in `04-production-scenarios/` (no cluster needed).

## What this pack deliberately does NOT cover

- Becoming a CNCF project contributor (out of scope for an interview-prep sprint).
- Cloud-specific deep dives (EKS IAM, GKE Workload Identity, AKS RBAC integration). Patterns are mentioned; implementation is cloud-flavor.
- Service mesh installation tutorial — covered conceptually in `02-labs/WEEK3.md` § Lab 18.
- Writing operators in Go — concept-level only in `02-labs/WEEK6.md` § Lab 35; building one is its own multi-week project.

If you want any of those expanded, that's a follow-up pack.

## Maintenance

The K8s ecosystem moves fast. The content here was written against K8s 1.30. Check release notes when you upgrade your lab cluster — most things in this pack survive minor version bumps, but the upgrade paths and API deprecations sections in particular are version-sensitive.

---

Good luck. The hardest part of this kind of sprint is just opening the lab on day 8 when day 7 felt like nothing clicked. It does click — keep going.

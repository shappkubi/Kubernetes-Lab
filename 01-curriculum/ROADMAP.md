# 6-Week Sprint Roadmap — Deep Kubernetes

Built for 1–2 hrs/day × 5–6 days/week. The arc deliberately moves from architecture → workloads → networking → storage → security → observability → scheduling → upgrades & failure → production patterns. By week 6 you should be able to whiteboard the K8s architecture cold, debug a CrashLoopBackOff in your sleep, and discuss multi-tenancy, autoscaling, and disaster recovery with concrete examples.

Every day has three blocks:

1. **Concept** — read & note key ideas (15–25 min)
2. **Lab** — hands-on against your local cluster (40–70 min)
3. **Reflect** — write 5 lines in your own words explaining what you just did (5 min)

The reflection step is non-negotiable. It's what converts "I followed steps" into "I can explain this on a whiteboard."

---

## Week 1 — Architecture & Core Workloads

Goal: be able to draw the K8s architecture from memory and explain what each component does, what happens when it fails, and how `kubectl apply` becomes a running pod.

| Day | Concept | Lab |
|---|---|---|
| 1 | Cluster anatomy: control plane (kube-apiserver, etcd, scheduler, controller-manager, cloud-controller-manager) and node (kubelet, kube-proxy, container runtime). Reconciliation loop / declarative model. | `02-labs/WEEK1.md` § Lab 1 |
| 2 | Pods deep dive: pod lifecycle (Pending → Running → Succeeded/Failed), restart policies, init containers, sidecar pattern, ephemeral storage, pause container. | `02-labs/WEEK1.md` § Lab 2 |
| 3 | Deployments, ReplicaSets, rolling updates, revision history, rollback. The Deployment → ReplicaSet → Pod ownership chain. | `02-labs/WEEK1.md` § Lab 3 |
| 4 | Services: ClusterIP, NodePort, LoadBalancer, ExternalName, headless. kube-proxy modes (iptables vs IPVS). Endpoints/EndpointSlices. | `02-labs/WEEK1.md` § Lab 4 |
| 5 | Ingress vs Gateway API. Path/host routing, TLS, rewrites, common annotations. Ingress controller as just-another-Deployment. | `02-labs/WEEK1.md` § Lab 5 |
| 6 | DaemonSets, StatefulSets (intro), Jobs, CronJobs — when each is right, ordering guarantees. | `02-labs/WEEK1.md` § Lab 6 |

**Week 1 milestone:** redraw the architecture diagram from `05-interview-prep/01-architecture-deep-dive.md` from memory, narrating each component.

---

## Week 2 — Configuration, Storage, Networking

Goal: be able to explain how a request flows from a user to a pod, where state lives, and the trade-offs of the storage primitives.

| Day | Concept | Lab |
|---|---|---|
| 7 | ConfigMaps and Secrets. Mount as files vs env vars. Secret encryption at rest. External Secrets pattern. | `02-labs/WEEK2.md` § Lab 7 |
| 8 | PV / PVC / StorageClass / CSI. Reclaim policies. Access modes. Volume binding modes. | `02-labs/WEEK2.md` § Lab 8 |
| 9 | StatefulSets in earnest: stable identity, ordered deployment, volumeClaimTemplates, headless service for DNS. | `02-labs/WEEK2.md` § Lab 9 |
| 10 | Cluster networking model: every pod has its own IP, no NAT between pods, services are virtual IPs. CNI's job. | `02-labs/WEEK2.md` § Lab 10 |
| 11 | DNS in K8s: CoreDNS, search domains, FQDN forms. Common DNS failures. | `02-labs/WEEK2.md` § Lab 11 |
| 12 | NetworkPolicies. Default-allow vs default-deny. Ingress/egress rules. CNI requirements. | `02-labs/WEEK2.md` § Lab 12 |

**Week 2 milestone:** stand up a Postgres StatefulSet with a persistent volume, expose it via a headless service, connect from a client pod, and write a NetworkPolicy that lets only that client reach it.

---

## Week 3 — Security, RBAC, Identity

Goal: own the security model. Explain authn vs authz vs admission, write a least-privilege Role, harden a pod.

| Day | Concept | Lab |
|---|---|---|
| 13 | Full request path: authn (certs, tokens, webhooks) → authz (RBAC) → admission (mutating, validating, ValidatingAdmissionPolicy). | `02-labs/WEEK3.md` § Lab 13 |
| 14 | RBAC: Roles, ClusterRoles, bindings, ServiceAccounts, Aggregated ClusterRoles. | `02-labs/WEEK3.md` § Lab 14 |
| 15 | Pod security: SecurityContext, runAsNonRoot, readOnlyRootFilesystem, capabilities, seccomp. Pod Security Admission. | `02-labs/WEEK3.md` § Lab 15 |
| 16 | Secrets management for real: external secrets, sealed secrets, KMS envelope encryption. | `02-labs/WEEK3.md` § Lab 16 |
| 17 | Image security: pull secrets, signing (cosign), private registries, distroless. | `02-labs/WEEK3.md` § Lab 17 |
| 18 | Network security + service mesh primer (when a mesh earns its keep). | `02-labs/WEEK3.md` § Lab 18 |

**Week 3 milestone:** harden the demo app to pass `pod-security.kubernetes.io/enforce=restricted` and explain every change you had to make.

---

## Week 4 — Scheduling, Resources, Autoscaling, Observability

Goal: be able to debug "why is my pod Pending?" in 30 seconds and explain HPA/VPA/Cluster Autoscaler trade-offs.

| Day | Concept | Lab |
|---|---|---|
| 19 | Requests, limits, QoS classes. OOMKilled vs CPU throttling vs eviction. | `02-labs/WEEK4.md` § Lab 19 |
| 20 | Scheduling: nodeSelector, affinity/anti-affinity, taints & tolerations, topology spread, priority & preemption. | `02-labs/WEEK4.md` § Lab 20 (kind required) |
| 21 | HPA: metrics-server vs custom/external metrics, behavior fields, stabilization windows. KEDA concept. | `02-labs/WEEK4.md` § Lab 21 |
| 22 | VPA, Cluster Autoscaler, Karpenter — trade-offs and when to use which. | `02-labs/WEEK4.md` § Lab 22 (design exercise) |
| 23 | Liveness / readiness / startup probes. Common probe mistakes that cause cascading failures. | `02-labs/WEEK4.md` § Lab 23 |
| 24 | Observability: events, kubectl logs/describe/top, metrics-server, kube-state-metrics. | `02-labs/WEEK4.md` § Lab 24 |

**Week 4 milestone:** create a Deployment that hits HPA-driven scale-out under load while staying within a ResourceQuota, and explain what would change with VPA.

---

## Week 5 — Failure, Upgrades, Disaster Recovery

Goal: speak confidently about what breaks in production and how you recover. This is the week interviewers love.

| Day | Concept | Lab |
|---|---|---|
| 25 | Node failures: cordon, drain, taints during maintenance. PodDisruptionBudgets. Voluntary vs involuntary disruptions. | `02-labs/WEEK5.md` § Lab 25 |
| 26 | etcd: what it stores, Raft consensus, backup, restore. | `02-labs/WEEK5.md` § Lab 26 (Killercoda) |
| 27 | Upgrades: kubeadm plan/apply, surge control plane, drain-upgrade-uncordon workers. API deprecations. | `02-labs/WEEK5.md` § Lab 27 (Killercoda) |
| 28 | Common production incidents tour. | Walk every scenario in `03-troubleshooting/PLAYBOOK.md` |
| 29 | Disaster recovery: Velero, GitOps-as-recovery, control-plane DR. | `02-labs/WEEK5.md` § Lab 29 |
| 30 | Capacity planning & cost: sizing, bin packing, requests vs limits in production, common waste patterns. | `02-labs/WEEK5.md` § Lab 30 (design) |

**Week 5 milestone:** run two of the production scenarios in `04-production-scenarios/` end to end and write a one-page post-mortem for each.

---

## Week 6 — Production Patterns & Polish

Goal: tie everything together with real-world patterns and finish interview-ready.

| Day | Concept | Lab |
|---|---|---|
| 31 | GitOps: Argo CD / Flux mental model. App-of-apps. Sync waves. Drift detection. | `02-labs/WEEK6.md` § Lab 31 |
| 32 | Helm: charts, values, templating, hooks. Helm vs Kustomize. | `02-labs/WEEK6.md` § Lab 32 |
| 33 | Multi-tenancy: ResourceQuota, LimitRange, NetworkPolicy as tenancy boundaries. | `02-labs/WEEK6.md` § Lab 33 |
| 34 | Progressive delivery: blue/green, canary, traffic mirroring (Argo Rollouts / Flagger). | `02-labs/WEEK6.md` § Lab 34 |
| 35 | Operators & CRDs: controller pattern, kubebuilder concepts, `Reconcile()`, when to write one. | `02-labs/WEEK6.md` § Lab 35 |
| 36 | Mock interview day. Run `05-interview-prep/MOCK-INTERVIEW.md`. | — |

**Week 6 milestone:** complete the mock interview with a written answer for every question, then re-grade yourself a week later.

---

## How to use this roadmap effectively

1. **Don't skip the reflection step.** The 5-line summary at the end of each day is what burns it in. Keep them in `01-curriculum/notes/dayNN.md`.
2. **Re-do labs from scratch.** After the first pass, delete your cluster and redo Week 1 from memory. Then Week 2. By week 6 you should be able to set up a cluster, run any lab, and tear it down without checking notes.
3. **Teach it.** For each week, write a 200-word blog-style explanation as if teaching a junior engineer. Best test of understanding.
4. **Cross-reference.** The labs are numbered to match this roadmap so you can jump around if a topic comes up at work.

### Pacing flexibility

If you're short a day in a week, drop the design-only labs (Day 22, Day 30) — the concepts are covered in `04-production-scenarios/` and `05-interview-prep/`. If you're ahead, double up on troubleshooting (`03-troubleshooting/`) — that's where interview gold lives.

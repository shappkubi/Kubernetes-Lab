# Whiteboard Scenarios

These are open-ended design questions. Practice talking through them out loud at a whiteboard (or in front of a mirror) for 5–10 minutes each. The grading rubric is structure, trade-offs, and concreteness — not memorization.

For each: read the prompt, set a 5-minute timer, talk it through. Then read the "framework" notes.

---

## W1 — Design a multi-region web app on K8s

**Prompt:** A web app with a Postgres-backed checkout flow. Active in two regions. Users in each region should hit the closest. Region failure should not cause >15 min downtime.

**Framework:**

1. Two regional clusters, hot/warm or hot/hot. Deploy stateless apps to both.
2. Global LB (anycast or DNS-based health steering) sends users to nearest healthy region.
3. Postgres: managed multi-region (Aurora Global / AlloyDB / Spanner) with one primary, async standby. Failover is the long pole — RTO is mostly DB promotion time.
4. Cache (Redis): per-region; cold-start acceptable on failover.
5. Object storage: cross-region replicated bucket.
6. CD: GitOps repo per environment + region. Deploys to both. PRs gate on canary in one region first.
7. Practice quarterly DR drill — actually fail traffic and measure RTO.

Discuss trade-offs: cost of hot/hot, complexity of multi-region writes, why federation isn't typically the answer in 2025.

---

## W2 — Design a CI/CD platform for 200 microservices

**Prompt:** Engineering wants self-service deploys. ~200 services, ~30 teams. Production K8s clusters in 2 regions. Build it.

**Framework:**

1. **Source of truth:** monorepo or polyrepo? Either works; a deployment manifest repo per service is common.
2. **Build:** GitHub Actions / GitLab CI builds, tests, scans (Trivy), pushes image with immutable tag (commit SHA).
3. **Deploy:** Argo CD per cluster, watching a deployment repo. PR to bump image tag → merge → Argo syncs.
4. **Promotion:** dev → staging → prod via PRs across env directories or via Argo CD ApplicationSets.
5. **Progressive delivery:** Argo Rollouts for prod, with canary steps and Prometheus-based analysis.
6. **Policy:** Kyverno / OPA for required labels, runAsNonRoot, allowed registries.
7. **Self-service:** team file in repo defines `WebApp` CR (your platform abstraction); operator generates Deployment + Service + Ingress + PDB + monitor + alerts.
8. **Observability:** standard sidecar/labels/dashboards inherited from the abstraction.
9. **Guardrails:** ResourceQuota per team namespace, default LimitRange, NetworkPolicy templates.

Discuss the build-vs-buy choice for the developer portal (Backstage), and the abstraction trap (your operator must allow escape hatches).

---

## W3 — A pod is "Running" but users see errors

**Prompt:** Deployment is at desired replicas. Pods all show Running and Ready. Error rate spiking. Walk through how you find the cause.

**Framework:**

The interviewer wants to see the differential diagnosis. Likely culprits:

1. **Bad new image, but readiness probe is too lax** — maybe "/" returns 200 even when the app's sub-system is degraded. Look at recent rollouts; rollback is the mitigation.
2. **Downstream failure** — DB, queue, third-party API. Pod is fine, dependency is not. Check downstream metrics; circuit breakers should engage; readiness should ideally fail.
3. **Some pods are bad, not all** — a node is unhealthy or one replica got a bad image rollout. `top pod` shows asymmetric utilization.
4. **NetworkPolicy or mesh authz change** — a recent PR cut off a path. `kubectl describe networkpolicy` recent changes; mesh AuthorizationPolicies.
5. **TLS or DNS issue** — `nslookup` from inside a pod, `openssl s_client` to dependency.
6. **Cert expiry** — for mTLS environments. Look for "x509: certificate has expired" in app logs.

Cover the "scope first, mitigate next, root-cause last" triage discipline.

---

## W4 — How would you onboard a new team safely?

**Prompt:** New 8-person team is joining the org. They have a few microservices. Bring them onto the prod cluster.

**Framework:**

1. **Namespace per environment** for the team: `team-x-dev`, `team-x-staging`, `team-x-prod`.
2. **Resource boundaries:** ResourceQuota + LimitRange per namespace, sized from their stated needs + headroom.
3. **Identity:** team SSO group → ClusterRoleBinding (with namespace scope) for Cluster Operators among them; basic developer Role for everyone else.
4. **Network:** default-deny in their namespaces, allow-list ingress from ingress-nginx and east-west calls they need.
5. **CI/CD:** GitOps manifest repo template, Argo Application pre-wired.
6. **Observability:** dashboards + alerts via the platform's WebApp abstraction.
7. **Onboarding:** a 30-min walkthrough; a smoke-test app that they deploy as their first PR; an on-call rotation.

Discuss what's *not* their responsibility: the platform team owns ingress, certs, mesh, monitoring stack.

---

## W5 — The cluster is slow; bonus: it's etcd

**Prompt:** kubectl is sluggish. Engineers complain about slow apply. What's your debug path?

**Framework:**

1. **API server first.** `kubectl --v=8 get nodes` — see request timing. Look at apiserver pod logs; any 429s?
2. **Audit logs:** which client is hammering it? Often a misbehaving custom controller in tight reconcile.
3. **etcd metrics:** `etcd_disk_wal_fsync_duration_seconds` p99, `etcd_db_total_size_in_bytes` vs `etcd_db_total_size_in_use_in_bytes` (delta = fragmentation).
4. **Disk:** etcd on dedicated low-latency SSD? Other workloads sharing that disk?
5. **Defrag:** `etcdctl defrag` per member, off-peak.
6. **Compaction:** if auto-compaction isn't enabled (`--auto-compaction-retention`), enable it.
7. **APF tuning:** if a runaway client is starving real traffic, tune flow schemas to throttle them.
8. **Long-term:** dedicated etcd machines, network and disk isolation, monitoring on the four golden signals for etcd.

Discuss the *culture* of taking etcd seriously — it's the most-overlooked maintenance task and the highest-yield place to add SRE rigor.

---

## W6 — Design a secrets workflow

**Prompt:** Secrets currently in `kubectl create secret` commands stored in 1Password. Engineers complain it's painful. Replace it.

**Framework:**

Three serious options:

1. **External Secrets Operator + Vault / cloud-native store.** Source of truth in Vault. ESO syncs into K8s Secret objects on a schedule. Pros: enterprise-grade, audit, rotation. Cons: depends on Vault availability; still creates K8s Secret in cluster.

2. **Sealed Secrets (Bitnami).** kubeseal encrypts a Secret manifest for the cluster's public key; encrypted YAML in git. Cluster controller decrypts. Pros: GitOps-friendly, no extra service. Cons: per-cluster key (unsealing in DR cluster requires key migration), no rotation.

3. **CSI Secret Store driver** (e.g., Vault CSI provider). Pods mount secrets directly from Vault via a CSI volume; no K8s Secret created. Pros: most secure (secret never persists to etcd). Cons: more complex setup, runtime dependency on Vault.

Pick one (typical recommendation: ESO + Vault for orgs that have or will have Vault; Sealed Secrets for smaller setups). Discuss rotation strategy and emergency-revocation. Mention encryption-at-rest for K8s Secrets as defense in depth.

---

## W7 — Cost is up 40%

(See `04-production-scenarios/SCENARIOS.md` § Scenario 8 for the full version. Practice that one.)

---

## W8 — Designing a stateful workload

**Prompt:** Run a 3-node Kafka cluster on K8s. What primitives, what are the gotchas?

**Framework:**

1. **StatefulSet** with `replicas: 3`, headless Service for per-broker DNS, `volumeClaimTemplates` for persistent storage per broker.
2. **PodDisruptionBudget** with `minAvailable: 2` of 3.
3. **Anti-affinity** across nodes (and ideally zones) so a node failure doesn't take 2 brokers.
4. **Resource requests** sized for steady-state, not peak — let HPA-equivalent handle peak.
5. **Probes:** readiness checks broker-controller connectivity; liveness checks the JVM is alive only.
6. **Storage class:** RWO block storage with high IOPS, `WaitForFirstConsumer` so the disk lands in the right zone.
7. **Backup:** Kafka MirrorMaker or Confluent's tooling — *not* PV snapshots alone (data file format is replication-aware).
8. **Operator?** For real production, probably yes (Strimzi). The operator handles broker IDs, rolling restarts, scaling, monitoring.

Gotchas: Kafka's broker ID must be stable; PV survives pod, identity survives via StatefulSet ordinal; rolling restart is sensitive to under-replicated partitions (operator handles this).

---

## W9 — Migrate VMs to K8s

**Prompt:** 30 VMs running 30 services. Move to K8s. Sketch the plan.

**Framework:**

1. **Containerize** services one at a time. Start with stateless ones. Use 12-factor patterns: config from env/files, no local state, graceful shutdown.
2. **Land in non-prod cluster first.** Smoke tests, load tests, observability parity.
3. **Strangler pattern:** route traffic gradually from VM to K8s for each service. DNS or LB-level shifts.
4. **State:** databases stay on managed services, not in-cluster, for early phases. Move state in only after the muscle is built.
5. **Order:** stateless web tier → background workers → caches → finally databases.
6. **Don't:** lift-and-shift VMs as `Pod`s with `hostNetwork: true` and one giant init script. That's a tar pit.

Discuss org change required: developers learn K8s, ops grows new muscles, on-call rotations adapt. The technical migration is the easy half.

---

## W10 — Custom Resource: when and how?

**Prompt:** Your org has 50 services that all want a similar Postgres-backed thing. Design a CRD.

**Framework:**

1. **Define the abstraction.** What's the contract? What can the user set? What's defaulted?
   ```yaml
   apiVersion: data.example.com/v1
   kind: PostgresApp
   metadata: { name: orders }
   spec:
     databaseSize: 10Gi
     replicas: 2
     backupSchedule: "0 2 * * *"
   ```
2. **Use kubebuilder** to scaffold the operator.
3. **Reconciler** owns the lifecycle: creates/updates a Postgres StatefulSet, a Secret for credentials, a CronJob for backups, a Service.
4. **Status subresource** reports observed state (replicas ready, last backup time, current size).
5. **Watch ownership** via `ownerReferences` so deletes cascade.
6. **Versioning** of the CRD: `v1alpha1` to start, conversion webhooks when you bump versions.
7. **Tests:** envtest for the controller, e2e tests against kind.
8. **Don't reinvent.** If a CNCF Operator already does the job (Zalando Postgres Operator, CloudNativePG), use that and wrap with a thinner CRD if needed.

The interviewer is checking whether you (a) can explain the controller pattern, (b) know when not to write a CRD.

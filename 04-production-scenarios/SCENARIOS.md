# Production Scenario Drills

These are the discussion-and-design exercises that separate "I can pass CKAD" from "I can run K8s in anger". Each scenario has:

- **The situation** (what's happening / what's needed)
- **Probing questions** (what an interviewer would ask next)
- **What a strong answer covers**
- **Lab variant** (how to recreate the spirit of it on k3d or Killercoda)

Work through one a day in week 5–6 of the roadmap. Speak the answer out loud — interviewers grade structure, not just facts.

---

## Scenario 1 — The 3 AM page: Half a Service is unhealthy

**Situation:** PagerDuty fires. Error rate on `payments-api` is at 12%. `payments-api` runs 12 replicas. You SSH into your jump host and start typing.

**Probing questions:**
- What do you check first?
- How do you tell if it's a subset of pods, all pods, a downstream, or the LB?
- How do you mitigate without root-causing first?

**What a strong answer covers:**

1. **Triage in the order:** scope (how many users / pods?) → mitigate → diagnose. In that order. Customers don't pay you to root-cause; they pay you to stop the bleeding.

2. **Scope:**
   - `kubectl -n prod top pod -l app=payments-api` — are some replicas hot and others not?
   - `kubectl -n prod get pod -l app=payments-api -o wide` — are bad replicas all on the same node?
   - Look at the per-pod error rate in your dashboard if it's tagged with `pod` label.

3. **Mitigation options:**
   - If a node looks bad: `kubectl cordon <node>; kubectl drain <node> --ignore-daemonsets`. PDB protects you.
   - If new image is bad: `kubectl rollout undo deploy/payments-api`.
   - If a downstream (DB, cache) is failing some calls: open a circuit breaker, scale down for graceful degradation, fail readiness on dependency loss.

4. **Diagnose** in parallel: `kubectl describe pod` for the bad replicas, recent rollouts, recent ConfigMap changes, recent NetworkPolicy changes, downstream health.

5. **Prevent:** PDB, anti-affinity across nodes/zones, canary deploys with auto-rollback, read-write split if DB is the bottleneck.

**Lab variant:** Deploy 6 replicas. SSH into one pod and `kill -SEGV 1` (causes restart loop on that one pod). Watch `kubectl top pod` and event stream show the asymmetry.

---

## Scenario 2 — Capacity request from a new team

**Situation:** A new team wants to onboard onto your shared cluster. They estimate 50 services, peak ~30 vCPU, ~80 GiB. They need an isolated environment but inside the same cluster. They mention they'll have one "background processor" that runs nightly and chews through 200 vCPU for 2 hours.

**Probing questions:**
- Soft or hard tenancy?
- How do you stop them from starving everyone else?
- How do you handle the nightly burst without permanently sized-for-peak nodes?

**What a strong answer covers:**

1. **Tenancy boundary:** namespace-per-environment with ResourceQuota + LimitRange + NetworkPolicy. If they're in a different trust domain, separate cluster.

2. **Quotas (steady-state):**
   - `requests.cpu: "30"`, `limits.cpu: "60"` — gives them room to burst within 2x.
   - LimitRange defaults so individual pods don't have to ask.
   - PriorityClass `tenant-default` (priority 0) for normal work.

3. **Nightly burst handling:**
   - Cluster Autoscaler / Karpenter sized for peak, scaled to 0 when idle.
   - The batch job pods carry a `PriorityClass: batch-low` so they're preempted by online traffic if the pool is full.
   - Optionally a separate NodePool tainted `dedicated=batch:NoSchedule` that grows on demand and gets paid for only when batch is running.

4. **Network isolation:** default-deny in the namespace, allow only the explicit cross-tenant calls.

5. **What can still go wrong:** they hit the apiserver hard with chatty informers; their PVs aren't quotaed (`requests.storage`); their logs blow your storage bill. Cover all three in the proposal.

**Lab variant:** `02-labs/WEEK6.md` § Lab 33 (multi-tenancy).

---

## Scenario 3 — Zero-downtime cluster upgrade

**Situation:** You run a self-managed kubeadm cluster: 3 control-plane, 12 workers across 3 zones. Workloads include a Postgres StatefulSet (with PDBs minAvailable=1 of 3), 30 Deployments, 5 DaemonSets. You need to go 1.29 → 1.30. Plan it.

**Probing questions:**
- What's the order?
- How do you keep customers up?
- What's the rollback plan?

**What a strong answer covers:**

1. **Pre-flight:**
   - Read 1.30 release notes, especially API removals; run `kubent` to find any deprecated API in the cluster.
   - Verify CNI / CSI / ingress-controller / monitoring stack support 1.30.
   - Backup etcd: `etcdctl snapshot save` on every control-plane node.
   - Cordon **plan**, don't actually cordon yet.

2. **Control plane:**
   - Drain control-plane node 1 of taints, `kubeadm upgrade plan`, `kubeadm upgrade apply v1.30.x`.
   - Restart kubelet, verify Ready.
   - Repeat on CP node 2 and 3 with `kubeadm upgrade node`.

3. **Workers, one at a time:**
   - `kubectl drain worker-N --ignore-daemonsets --delete-emptydir-data`. PDB on Postgres protects against draining the leader.
   - `apt install kubeadm=1.30.x`, `kubeadm upgrade node`, `apt install kubelet=1.30.x kubectl=1.30.x`, `systemctl restart kubelet`.
   - `kubectl uncordon worker-N`. Wait for pods to redistribute.

4. **Verify:** all nodes Ready 1.30, all pods Running, smoke tests pass, metrics dashboards match pre-upgrade baselines.

5. **Rollback:** with etcd snapshot, you can restore the etcd state of the old cluster. New control-plane binaries don't downgrade automatically — you'd need to also pin kubelet/kubeadm. Production reality: you usually fix forward, not roll back.

**Lab variant:** Killercoda *Upgrade a cluster from 1.29 to 1.30* — does this without disk cost.

---

## Scenario 4 — etcd is slow

**Situation:** Your dashboards show kube-apiserver request latency p99 climbing from 100ms to 800ms over a week. No traffic spike. etcd disk write fsync p99 is 80ms (was 5ms a week ago).

**Probing questions:**
- What's most likely?
- How do you confirm?
- How do you fix without downtime?

**What a strong answer covers:**

1. **Most likely:** etcd db is fragmented; defrag overdue. Or disk IOPS budget is being hit by something else on the node.

2. **Confirm:**
   - `etcdctl endpoint status --write-out=table` — look at `DB SIZE` vs `DB SIZE IN USE`. Big delta = needs defrag.
   - Compare `dbSize` and `dbSizeInUse` over time in your monitoring.
   - Check disk metrics on the etcd nodes (iostat, node_disk_io_time_seconds_total). If iops queue is saturated by something non-etcd, find that.

3. **Fix:**
   - Defrag one member at a time, off-peak. `etcdctl defrag --command-timeout=60s --endpoints=<one member>`. Wait for it to settle, then the next.
   - For chronic fragmentation: enable etcd auto-compaction (`--auto-compaction-retention=8h`).
   - Move etcd to its own disk if it's on the same disk as kubelet's image fs.

4. **Long-term:** etcd should be on dedicated low-latency SSD (NVMe / cloud Premium SSD). Ratings: target fsync p99 < 25ms, p99.9 < 50ms.

**Lab variant:** the etcd Killercoda from `02-labs/WEEK5.md` § Lab 26 — get familiar with `etcdctl` syntax.

---

## Scenario 5 — A bad rollout hit production at 100%

**Situation:** Engineer pushed `image: app:bad`. The Deployment doesn't have a readiness probe. All 8 replicas restarted with the new image. Error rate is 100%. Time on the wall: 10 seconds since deploy.

**Probing questions:**
- What's your sequence in the next 60 seconds?
- Why didn't the rollout protect you?
- What changes prevent recurrence?

**What a strong answer covers:**

1. **Mitigation, one command:** `kubectl rollout undo deploy/app -n prod`. Watch `kubectl rollout status`.

2. **Why no protection:**
   - Without readiness probe, kubelet marks pods Ready as soon as the container starts — even if the app inside is failing requests. The Deployment thinks the rollout succeeded.
   - With readiness probe, the new pods would fail readiness, the Deployment would not progress past the first one, `maxUnavailable: 1` would cap it.

3. **Prevent:**
   - Readiness probes mandatory (PSP, OPA, Kyverno policy).
   - Lower `maxSurge` and `maxUnavailable` for risk-tolerant services so first one going bad blocks rest.
   - Use Argo Rollouts or Flagger with automated analysis (error rate, latency) that aborts on regression.

4. **Cultural:** post-mortem, blameless. Was the bad image caught in any previous environment? If staging is missing, that's the real root cause.

**Lab variant:** `02-labs/WEEK1.md` § Lab 3 (intentionally bad image, watch maxUnavailable bound the damage).

---

## Scenario 6 — DNS storm

**Situation:** Cluster-wide elevated latency. Investigation shows ndots-driven DNS queries are pummeling CoreDNS. CoreDNS pods are CPU-saturated.

**Probing questions:**
- Why does ndots:5 cause this?
- Three ways to mitigate, and trade-offs?

**What a strong answer covers:**

1. **The mechanism:** /etc/resolv.conf in pods has `ndots:5`. Anything with fewer than 5 dots is tried with each search domain first. `redis.example.com` (3 dots) becomes 4–5 lookups before falling through to public DNS.

2. **Mitigations:**
   - **Use FQDNs in code/config** (`redis.example.com.`) — trailing dot bypasses search list. Cleanest but requires code changes.
   - **NodeLocal DNSCache** (DaemonSet that caches at every node) — reduces upstream CoreDNS pressure dramatically. Recommended baseline for any nontrivial cluster.
   - **Custom Pod dnsConfig with ndots:2** — per-pod override for known offenders.
   - **Scale CoreDNS** — higher replica count, anti-affinity across nodes, requests sized for actual load.

3. **The gotcha:** NodeLocal DNSCache has its own failure mode — if the local cache pod crashes, every pod on the node loses DNS. Pair with `--health-port` and a node-level recovery loop.

**Lab variant:** Lab 11 in WEEK2.md — the section showing the /etc/resolv.conf and the `nslookup foo` vs `nslookup foo.default.svc.cluster.local` difference.

---

## Scenario 7 — Multi-region: hot/hot, hot/warm, or one cluster?

**Situation:** Your service is going regulated → you need a documented DR strategy with RTO 1h / RPO 15m. Sketch the architecture.

**Probing questions:**
- Single global cluster, federated, or two regional?
- How do you handle stateful workloads?
- How does traffic shift on failover?

**What a strong answer covers:**

1. **Default recommendation:** two regional clusters, hot/warm. One global cluster is operationally simpler but loses you blast radius isolation; federated K8s in 2025 is rarely worth it for application teams.

2. **Stateless apps:**
   - Same workloads in both. GitOps deploys both. Cluster-local autoscaling.
   - Traffic via Global Load Balancer (Cloudflare, AWS Global Accelerator, GCP GLB) with health-based steering.

3. **Stateful:**
   - Database: managed multi-region (Aurora Global, AlloyDB, Spanner). RPO/RTO match the service's SLO.
   - Object storage: replicated buckets.
   - In-cluster state (Redis cache): warm region runs a smaller replica; cold-start okay if cache miss.
   - PVs: snapshotted to the other region nightly (Velero with restic + cross-region S3).

4. **Failover:**
   - GLB removes the failed region from rotation (health checks).
   - DB promotes the standby in the surviving region (manual or automatic depending on tolerance).
   - DNS-based failover is slower (TTL); GLB anycast is faster.

5. **Practice:** quarterly DR test where you actually fail traffic to the warm region for an hour. Untested DR isn't DR.

**Lab variant:** can't do regions on a laptop. Use this scenario as a written architecture exercise — it's the highest-yield interview topic.

---

## Scenario 8 — Cost is exploding

**Situation:** Your K8s cloud bill grew 40% in 3 months. Workloads grew 10%. CTO wants explanation by Friday.

**Probing questions:**
- Where do you start looking?
- What are the top 5 reasons K8s bills creep?
- How do you set up sustained guardrails?

**What a strong answer covers:**

1. **Where to look:**
   - **Resource utilization** — `kubectl top pod` cluster-wide vs requests. Average utilization < 30% means massive overprovisioning.
   - **Idle nodes** — nodes that are 80% empty for 22 hours/day.
   - **Storage growth** — PVs and S3 buckets that no one set lifecycle on.
   - **Logs** — log retention 90 days at 100 GB/day = real money.
   - **Egress** — cross-AZ chatty services, cross-region traffic.

2. **Top reasons:**
   - Requests grossly overscaled "to be safe" → poor bin packing.
   - HPA min replicas too high.
   - Images are not pruned; ECR / Artifact Registry storage growing.
   - Old PVs in `Released` state never deleted.
   - Dev/staging clusters running 24/7 when only used 9-5.

3. **Guardrails:**
   - VPA recommender to suggest right-sized requests.
   - Karpenter / Cluster Autoscaler with aggressive scale-down.
   - Cost dashboards (Kubecost, OpenCost) split by namespace/team.
   - Quotas per namespace tied to budget.
   - Schedule dev clusters off at night.

**Lab variant:** Lab 30 capacity-design exercise — write a 1-page memo on a hypothetical cluster's bill, broken down.

---

## Scenario 9 — Compliance: 'show me what's in the cluster'

**Situation:** Auditor wants:
- All running pod images and their CVE scan results.
- Who can read Secrets in `prod`?
- Network policies for `prod`.
- Recent admission rejections.

**Probing questions:**
- How do you produce each report?
- What tooling do you put in place once instead of rerunning ad hoc?

**What a strong answer covers:**

1. **Image inventory:**
   ```
   kubectl get pod -A -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u
   ```
   Pipe to Trivy / Grype CI scans, or use a registry-side scanner (ECR, GAR, Harbor with Trivy).

2. **Who can read Secrets in prod:**
   ```
   kubectl auth can-i get secret -n prod --as=<every subject>
   ```
   Or: `kubectl get rolebinding,clusterrolebinding -A -o yaml | yq` and grep for `secrets` + `get/list/watch`.

3. **NetworkPolicies in prod:**
   ```
   kubectl -n prod get netpol -o yaml
   ```
   Plus a visualization: `kubectl-np-viewer` or a screenshot from Hubble (if Cilium).

4. **Admission rejections:**
   API server audit log filtered to `RequestResponse` events with `responseStatus.code in (403, 422)`. Aggregate to your SIEM.

5. **Permanent tooling:**
   - **Kyverno / OPA Gatekeeper** with policy bundles for required images, runAsNonRoot, no privilege escalation.
   - **Falco** for runtime detection.
   - **Audit logs** to SIEM, retained per compliance requirement.

**Lab variant:** WEEK3.md (RBAC, NetworkPolicy, PSA) — rebuild the muscle.

---

## Scenario 10 — Onboarding: design a platform tier

**Situation:** Your CTO asks you to make K8s "boring and self-service" for app teams. They want a `Service` of their own to declare. Sketch what you build.

**Probing questions:**
- Build vs buy?
- What CRDs do you expose?
- How do you guard the platform API against misuse?

**What a strong answer covers:**

1. **Build vs buy:** Backstage (developer portal) + an Internal Developer Platform (IDP). 2025 patterns lean toward Crossplane or Kratix to abstract cloud + K8s.

2. **App team interface:** instead of teaching them Deployments, expose a CR like:
   ```yaml
   apiVersion: platform.example.com/v1
   kind: WebApp
   metadata: { name: orders }
   spec:
     image: ghcr.io/team/orders:abc
     replicas: 5
     port: 8080
     dependsOn: [{ kind: Postgres, name: orders-db }]
     trafficPolicy: { mtls: required }
   ```
   Operator generates the right Deployment, Service, ServiceAccount, NetworkPolicy, PDB, monitor, and ingress.

3. **Guardrails:** OPA / Kyverno policies enforce defaults, your operator adds them automatically. Quotas + RBAC limit damage.

4. **Anti-pattern:** an operator that locks teams in but leaks abstractions. Always expose an "I need to break the abstraction" escape hatch.

**Lab variant:** Lab 35 (Operator concept). Write the YAML for a small WebApp CRD and pseudocode for its Reconcile.

---

## Drill protocol

For each scenario:
1. Read the situation. Don't read further.
2. Talk for 3 minutes (out loud, recorded).
3. Read the strong answer.
4. Note the 1–2 things you didn't cover. Internalize them.
5. Re-attempt 2–3 days later from scratch.

By scenario 10 you'll find the structure (triage → diagnose → fix → prevent) is automatic, and that's exactly what interviewers grade.

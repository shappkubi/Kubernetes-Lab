# Mock Interview — 60 Minutes

This is the interview to give yourself at the end of week 6. Record the audio. Watch your answers back, find filler words, find vague claims. Then re-grade in a week.

If a friend can play interviewer, hand them this doc and have them ask follow-up questions where it says **(probe)**.

---

## Round 1 — Architecture (15 min)

1. Draw the Kubernetes architecture on the whiteboard. Label every component. **(probe: which components are stateless? where does state live? what happens if controller-manager is down for 10 minutes?)**

2. Walk me through what happens when I run `kubectl apply -f deploy.yaml` for a brand new Deployment. Don't skip steps. **(probe: where does authentication happen? what's the difference between mutating and validating webhooks? when is the pod IP assigned?)**

3. The cluster's etcd is unhealthy on one of three members. What do you do? **(probe: how do you know which member is bad? can the cluster keep serving with 2 of 3? when is it dangerous?)**

---

## Round 2 — Workloads & Networking (15 min)

4. I have a stateful workload — Postgres with primary + replica. What primitives do I use, and why a StatefulSet vs Deployment? **(probe: how do PVCs come back when a pod is rescheduled? what's the role of the headless Service?)**

5. A pod can ping another pod's IP but cannot reach the corresponding Service ClusterIP. How do you debug? **(probe: what's actually in the iptables / IPVS rules for that Service? what does kube-proxy do?)**

6. Walk through Service types: ClusterIP, NodePort, LoadBalancer, headless. **(probe: how does an external load balancer find the right backend? what makes a Service "headless"?)**

7. NetworkPolicy: write me one that allows pods labelled `app=web` in namespace `apps` to reach pods labelled `app=db` in namespace `data` on port 5432, and nothing else into `data`. **(probe: what enforces this? what if my CNI is flannel?)**

---

## Round 3 — Operations & Failure (15 min)

8. A pod is in CrashLoopBackOff. Walk me through your debug. What's the FIRST thing you type? **(probe: what does `--previous` do? what's the difference between OOMKilled and Evicted?)**

9. We need to drain a node for maintenance without dropping availability. Walk me through. **(probe: what's a PDB and why does it matter? what if drain hangs forever?)**

10. We're upgrading from 1.29 to 1.30. Sketch the plan. **(probe: which order — control plane or workers first? how do you avoid skipping minor versions? what catches deprecated APIs?)**

11. The cluster is slow. kubectl is timing out. Five-minute debug plan. **(probe: how would you tell apiserver-slow from etcd-slow? what does `--v=8` show?)**

---

## Round 4 — Design & Production Patterns (15 min)

12. Sketch a hot/warm multi-region deployment. RTO 1h, RPO 15m. **(probe: how does state failover? where does traffic shifting happen? what's tested quarterly?)**

13. A team wants to onboard with a hard requirement: "no other team can read our secrets." How do you prove that? **(probe: RBAC structure? encryption at rest? how do you audit?)**

14. Cost is up 40%. Walk through the investigation. **(probe: what's the most common over-provisioning anti-pattern? where does idle node time hide?)**

15. Your CTO says: "make K8s self-service for application developers." What do you build? **(probe: what's the abstraction? when should developers see Deployments and Services directly?)**

---

## Self-grading rubric

For each answer, score 0–3:

- **0 — vague.** "It depends, you'd look at things." No concrete commands, no specific component names.
- **1 — partial.** Mentions some right components, misses key ones, no trade-offs.
- **2 — solid.** Names the right components, the key commands, and at least one trade-off or gotcha.
- **3 — interview-strong.** Structured (problem → diagnosis → fix → prevention), names specific commands and outputs, identifies the non-obvious failure modes, surfaces trade-offs without being asked.

A target by week 6: average ≥2.5, no answer below 2. Re-take in a week and aim for ≥2.7.

## Red flags you'll catch on replay

- "I think" / "kind of" / "maybe" — replace with confident "if X then Y" structure or honest "I don't know, I'd verify by …".
- Naming objects with no behavior. ("Use a Service.") Always include why.
- Skipping the diagnosis step. Interviewers grade *how you'd find the answer* more than *the answer itself*.
- Talking about K8s in isolation. Real systems include CI/CD, observability, IAM, networking, cost — pull those in.
- Missing the trade-off. Every choice has a downside. Surface it.

# Day 5 — SEV2 Page: inter-service connectivity broken (NetworkPolicy)

**Theme:** A change *somewhere else in the org* broke your service. Mitigation requires you to talk to humans, not just type. Your debug toolkit grows: meet `netshoot`.

**Time budget:** 90–120 min.

---

## Prep (~30 min — has lab content)

This drill assumes Week 2 NetworkPolicy knowledge. Read first:

- `02-labs/WEEK2.md` § Lab 12 — NetworkPolicy
- `03-troubleshooting/PLAYBOOK.md` § "DNS not resolving" (because NetworkPolicies often break DNS by accident)

⚠️ Important caveat about k3d/k3s: **flannel (the default CNI in k3s) does NOT enforce NetworkPolicy out of the box.** That means in your lab cluster, applying a deny-all policy will *not* actually block traffic — the API objects exist but enforcement is a no-op. Use the drill to practice **diagnosis**, not enforcement validation. The diagnosis steps are identical to a real Calico/Cilium cluster.

If you want real enforcement, run this drill on a Killercoda Calico playground. For today, focus on: read the policy, predict its effect, walk the debug ladder.

---

## Morning ritual

```bash
bash resume.sh
bash 00-setup/morning-check.sh
```

---

## Today's intake

### Page

```
[ALERT - SEV2] payments-prod / outbound-connection-failure
Triggered: <today> 19:44:11 UTC
Service: payments-svc → fraud-check-svc
Namespace: default                    (stand-in for payments-prod)
Cluster: k3d-lab                      (stand-in for aks-canada-central-prod)
Symptom: 100% connection failures from payments-svc to fraud-check-svc:8443
Duration: 3 min and counting
Side effect: payments-svc returning 502 (fraud check is in critical path)
Recent activity:
  - 19:41 UTC: NetworkPolicy `restrict-payments-egress` applied (PR #4129 by @sec-team)
On-call: you
Customer impact: payments fully degraded, ~$200/sec at risk
Bridge: zoom://platform-incident-bridge (security team joined)
```

### Set up the topology

You need two services to simulate the call. Run this once at start of day:

```bash
kubectl create deployment payments --image=nginxinc/nginx-unprivileged:1.27 --replicas=1 \
  --port=8080 --dry-run=client -o yaml | \
  sed 's/labels:/labels:\n        role: frontend/' | \
  kubectl apply -f -
kubectl expose deployment payments --port=80 --target-port=8080

kubectl create deployment fraud --image=nginxinc/nginx-unprivileged:1.27 --replicas=1 \
  --port=8080
kubectl expose deployment fraud --port=80 --target-port=8080

kubectl rollout status deploy/payments
kubectl rollout status deploy/fraud
```

Verify the topology works pre-policy:

```bash
kubectl run probe --rm -it --image=busybox -- wget -qO- --timeout=2 fraud
# Should print nginx HTML
```

### Inject the failure

The "security team's PR" — apply this:

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-payments-egress
spec:
  podSelector:
    matchLabels:
      app: payments
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: fraud-check          # ← typo: real service is "fraud", not "fraud-check"
      ports:
        - protocol: TCP
          port: 8443                    # ← second mistake: real port is 80
EOF
```

Two mistakes in the policy. Find them.

---

## Your job

### Step 1 — Acknowledge and gather facts

Open incident log. First entry:

```
[19:45] Page acknowledged. Recent change: NetPol `restrict-payments-egress` applied 4 min ago.
        Suspect this is the cause given correlation. Investigating before reverting.
```

### Step 2 — Spin up netshoot to test in the affected namespace

`nicolaka/netshoot` is the swiss army knife of K8s networking diagnostics — has dig, nslookup, curl, tcpdump, traceroute, iperf, etc.

```bash
kubectl run netshoot --rm -it --image=nicolaka/netshoot --labels="app=payments" -- bash
```

Inside (note: you launched the netshoot pod with `app=payments` so the NetPol applies to it):

```sh
nslookup fraud                     # does DNS resolve? — usually yes
curl -m 3 http://fraud             # does the call work? — should fail/timeout
exit
```

### Step 3 — Read the actual policy

```bash
kubectl get netpol -o yaml
```

Compare the policy to your topology. Two things to spot:

1. The `to:` allows pods labelled `app=fraud-check`. **Your service is labelled `app=fraud`** (one of the failure modes). Selector typo.
2. The `ports:` restricts to TCP/8443. **Your fraud service listens on 80** (you exposed it that way). Wrong port.

### Step 4 — Decide: revert or fix forward?

This is the senior decision. Mitigation comes first.

- **Revert** (`kubectl delete netpol restrict-payments-egress`) — fastest, but it removes the security team's protection entirely. Customer-impacting bug fixed in 5 seconds, but undoes their PR.
- **Fix forward** (patch the policy with correct labels + port) — preserves the intent, takes a few minutes longer.

Per the playbook context: customer impact is $200/sec. Mitigation rule: minutes matter, get it back. Revert. Then immediately work with security on the corrected policy via PR. Talk to them on the bridge.

```bash
# MITIGATION
kubectl delete netpol restrict-payments-egress

# Verify recovery
kubectl run probe --rm -it --image=busybox --labels="app=payments" -- wget -qO- --timeout=3 fraud
# nginx HTML returns
```

### Step 5 — Status updates to the bridge

```
[19:46] Acknowledged. NetPol applied at 19:41 correlates strongly. Validating with netshoot.
[19:48] Confirmed: NetPol selector targets app=fraud-check, real label is app=fraud. Also wrong port.
[19:50] Mitigation: deleted NetPol. Customer recovery confirmed. Engaging @sec-team on corrected policy.
[19:52] Recovered. Working with @sec-team on PR #4131 with fixed selectors.
[19:55] Closing incident. Postmortem in 24h.
```

### Step 6 — Write the corrected policy with security team

The "fixed-forward" version that they should re-apply (after PR review):

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: restrict-payments-egress
spec:
  podSelector:
    matchLabels:
      app: payments
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: fraud           # corrected label
      ports:
        - protocol: TCP
          port: 80                 # corrected port
    # Don't forget DNS! Otherwise pods can't resolve names.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

The DNS allow is the **classic missed thing** in egress policies. Without it, pods can't resolve names — even names they're explicitly allowed to reach. Worth highlighting in the postmortem.

### Step 7 — Cleanup

```bash
kubectl delete deploy payments fraud
kubectl delete svc payments fraud
bash 00-setup/restore.sh
```

---

## End-of-day artifacts

- [ ] Incident log + postmortem
- [ ] Runbook `07-pe-sim/runbooks/RUN-network-policy-debug.md`:
  - Diagnostic ladder: connectivity test → policy listing → policy decode → namespaceSelector + podSelector + port match check → DNS check
  - Standard "what's missing in your egress policy?" checklist (incl. DNS, kube-apiserver if app talks to it, etc.)
  - The `nicolaka/netshoot` invocation
  - When to revert vs fix forward
- [ ] 3 learnings
- [ ] Commit + push, stop

---

## Senior reflexes

1. **NetworkPolicy is allow-by-default UNLESS a policy with a matching `podSelector` exists.** Once one matches, only what's explicitly allowed gets through. People forget this and write a single allow rule, expecting the rest to still work.
2. **Egress policies that miss DNS break everything.** Always include the kube-system / kube-dns allow.
3. **flannel doesn't enforce.** Calico, Cilium, kube-router, Antrea do. If you write a NetPol and "nothing changes", check your CNI.

---

## Self-grading

| Item | 1–3 |
|---|---|
| Used `netshoot` correctly to validate L7 + DNS | |
| Decided revert vs fix forward consciously, not by reflex | |
| Communicated to security team on the bridge appropriately | |
| Postmortem includes the DNS-in-egress lesson | |

Target Day 5 average: 2.7.

---

## Tomorrow

Day 6 is your first non-incident day in the sim. A planned Jira ticket: deploy v1.2 of the checkout service to staging using blue/green. You'll set up two Deployments and flip the Service selector.

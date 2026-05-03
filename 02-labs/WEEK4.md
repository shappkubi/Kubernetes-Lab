# Week 4 Labs — Scheduling, Resources, Autoscaling, Observability

Cluster: k3d `lab` for most. Lab 20 needs more workers — see note inside.

---

## Lab 19 — Requests, Limits, QoS

**Goal:** explain QoS classes from memory and predict what gets killed first when a node is under pressure.

### 19.1 Three classes

| QoS | How to get there | What it means |
|---|---|---|
| Guaranteed | Every container has CPU and memory **request == limit** | Highest priority, evicted last |
| Burstable  | At least one container has a request, but request != limit (or only one resource set) | Mid-tier |
| BestEffort | No requests or limits at all | Killed first when node is under pressure |

```yaml
# Guaranteed
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 100m, memory: 128Mi }

# Burstable
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 512Mi }

# BestEffort
# (no resources block at all)
```

```
$ kubectl get pod <name> -o jsonpath='{.status.qosClass}'
```

### 19.2 OOMKilled vs CPU throttle

- **Memory limit hit** → kernel OOM-kills the process. Pod restarts. `kubectl describe pod` shows `Last State: Terminated, Reason: OOMKilled`.
- **CPU limit hit** → process is throttled (slowed). No kill, just slow. Watch in `kubectl top pod` or container_cpu_cfs_throttled_seconds_total.

Cause an OOMKill:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: hog }
spec:
  containers:
    - name: c
      image: polinux/stress
      resources:
        requests: { memory: 64Mi, cpu: 100m }
        limits:   { memory: 64Mi, cpu: 100m }
      command: ["stress"]
      args: ["--vm","1","--vm-bytes","100M","--vm-hang","1"]
```

```
$ kubectl get pod hog -w
$ kubectl describe pod hog | grep -A2 "Last State"
```

### 19.3 Reflect

Should you set a CPU limit in production? (Controversial. The mainstream view: requests = guaranteed; limits = optional. Limits cause throttling under bursty load and aren't necessary if requests are sized right. Set a memory limit to catch leaks, but consider not setting a CPU limit unless you're enforcing multi-tenant fairness.)

---

## Lab 20 — Scheduling: Affinity, Taints, Topology Spread

**Goal:** make pods land where you want — and explain why they don't when they don't.

> **Cluster note:** the topology spread part is more visible with multiple workers. If you want the full effect, spin up the kind cluster (`./00-setup/05-create-kind-cluster.ps1`). On k3d-1+1 you can still do nodeSelector and taints meaningfully.

### 20.1 nodeSelector

```
$ kubectl get nodes --show-labels
$ kubectl label node <one-worker> tier=app
```

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app-pod }
spec:
  nodeSelector: { tier: app }
  containers: [{ name: c, image: nginx }]
```

Quick & blunt. Use `affinity` for everything beyond simple matches.

### 20.2 Affinity / anti-affinity

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: anti }
spec:
  replicas: 3
  selector: { matchLabels: { app: anti } }
  template:
    metadata: { labels: { app: anti } }
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector: { matchLabels: { app: anti } }
      containers: [{ name: c, image: nginx }]
```

This says "no two of these pods on the same node". On k3d-1+1, the third replica will be Pending — that's the expected behavior, and a great teaching moment about the difference between `required` (hard) and `preferred` (soft).

### 20.3 Taints & tolerations

```
$ kubectl taint node <worker> dedicated=batch:NoSchedule
```

Existing pods stay (NoSchedule), new pods need a matching toleration:

```yaml
spec:
  tolerations:
    - key: dedicated
      operator: Equal
      value: batch
      effect: NoSchedule
```

Taint effects:
- `NoSchedule` — new pods need toleration
- `PreferNoSchedule` — soft version of above
- `NoExecute` — also evicts pods that don't tolerate

Use case: GPU nodes are tainted `gpu=true:NoSchedule`; only GPU workloads with the matching toleration land there.

### 20.4 Topology spread

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: spread }
spec:
  replicas: 6
  selector: { matchLabels: { app: spread } }
  template:
    metadata: { labels: { app: spread } }
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: zone
          whenUnsatisfiable: DoNotSchedule
          labelSelector: { matchLabels: { app: spread } }
      containers: [{ name: c, image: nginx }]
```

With nodes labelled `zone=a` and `zone=b`, this distributes ~3 to each zone instead of all six on whichever node had room first. This is how production HA actually works.

### 20.5 Why is my pod Pending?

Top decision tree:

```
$ kubectl describe pod <name> | grep -A5 Events
```

Look at the message. The classics:
- `0/3 nodes are available: 3 Insufficient cpu` → request is bigger than any node's allocatable
- `0/3 nodes are available: 3 node(s) didn't match node selector` → nodeSelector / affinity has no match
- `0/3 nodes are available: 3 node(s) had untolerated taint` → tolerations missing
- `0/3 nodes are available: 3 node(s) didn't have free ports for the requested pod ports` → hostPort conflict

### 20.6 Reflect

Hard vs soft scheduling: use `required` for correctness (this MUST happen) and `preferred` for optimization (try, but don't block). Production wisdom: anti-affinity within a service should usually be `preferred` — `required` causes weird Pending states during node failures.

---

## Lab 21 — HPA (Horizontal Pod Autoscaler)

**Goal:** drive an HPA, watch scale-out and scale-in behavior, understand stabilization.

### 21.1 Setup

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: cpu }
spec:
  replicas: 1
  selector: { matchLabels: { app: cpu } }
  template:
    metadata: { labels: { app: cpu } }
    spec:
      containers:
        - name: c
          image: registry.k8s.io/hpa-example
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 500m, memory: 128Mi }
---
apiVersion: v1
kind: Service
metadata: { name: cpu }
spec:
  selector: { app: cpu }
  ports: [{ port: 80 }]
```

### 21.2 The HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: cpu }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: cpu }
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 50 }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 0
      policies: [{ type: Percent, value: 100, periodSeconds: 15 }]
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{ type: Percent, value: 50,  periodSeconds: 60 }]
```

Notes:
- `averageUtilization: 50` is **% of request** (50% of 100m = 50m).
- `behavior` (added in autoscaling/v2) lets you tune surge speed and scale-in conservatism. Production tip: scale-up fast (0s window), scale-down slow (5–10 min window).

### 21.3 Drive load

```
$ kubectl run loader --image=busybox --restart=Never -- sh -c "while true; do wget -qO- http://cpu/; done"
$ kubectl get hpa cpu -w
```

Expect replicas to rise toward 10, then settle back down ~5 minutes after you `kubectl delete pod loader`.

### 21.4 Reflect

What's the Achilles heel of HPA on CPU? (CPU-bound metrics lag behind real load. For chatty IO-bound services, scaling on RPS or queue depth via custom/external metrics or KEDA is far more responsive.)

---

## Lab 22 — Autoscaling Design Exercise (no install)

Compare:

| | HPA | VPA | Cluster Autoscaler | Karpenter |
|---|---|---|---|---|
| What it scales | Pod count | Pod size (requests) | Node count | Node count + shape |
| Triggered by | metrics (CPU, custom) | observed usage history | unschedulable pods | unschedulable pods |
| Time to react | seconds | minutes (recreates pod) | minutes | seconds |
| Plays well with each other? | with VPA: only on different metrics. Otherwise they fight. | | with HPA: yes | with HPA: yes |

Design question to write 200 words on:

> A multi-tenant cluster runs ~200 services. Some are spiky web (RPS-driven), some are steady backend, some are batch jobs that run for 2–5 minutes. What combination of autoscalers do you choose, and why?

(Sketch answer: HPA on RPS for web. HPA on queue depth or KEDA for batch. Optional VPA in `recommender` mode for the steady backends to right-size requests over time. Karpenter at the node layer because batch job spikes need fast node provisioning. Avoid VPA + HPA on the same metric.)

---

## Lab 23 — Probes

**Goal:** every pod ships with the right probes; bad probes are a top-3 outage cause.

### 23.1 The three probes

| Probe | Failure means | Common mistake |
|---|---|---|
| startupProbe | Kill the container — startup never finished | Not setting one for slow-starting JVMs/migrations; liveness then kills mid-startup |
| livenessProbe | Restart the container | Same endpoint as readiness — DB blip kills the pod cluster-wide |
| readinessProbe | Remove from Service endpoints (don't kill) | Returning healthy when you can't reach DB → NotReady = no traffic = good |

### 23.2 Sane defaults

```yaml
startupProbe:
  httpGet: { path: /healthz, port: 8080 }
  failureThreshold: 30
  periodSeconds: 10                 # up to 5 min for startup
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }
  periodSeconds: 10
  failureThreshold: 3
readinessProbe:
  httpGet: { path: /ready, port: 8080 }   # different endpoint!
  periodSeconds: 5
  failureThreshold: 3
```

`/healthz` should answer "am I alive?" — does the process loop run, can it allocate memory.
`/ready` should answer "should I get traffic?" — DB connection up, caches warmed, dependencies reachable.

### 23.3 Reflect

The classic "DB blip kills my whole cluster" anti-pattern: liveness checks DB. DB hiccups for 30s. Every pod gets killed simultaneously. New pods start, fail liveness because DB is still recovering, kill loop. Fix: only readiness checks dependencies; liveness only checks process health.

---

## Lab 24 — Observability

**Goal:** know the built-in tools and where each fits.

### 24.1 The five things you actually use 95% of the time

| Tool | When |
|---|---|
| `kubectl describe pod` | First place to look for any pod issue |
| `kubectl logs -f --previous` | What did the pod log? `--previous` shows the dead container's logs |
| `kubectl get events --sort-by=.lastTimestamp` | What is the cluster trying to tell you? |
| `kubectl top pod / node` | Live resource usage (needs metrics-server) |
| `kubectl exec -it <pod> -- sh` | Sometimes you just need a shell |

### 24.2 stern

`stern <selector>` tails logs from many pods at once with colored prefixes. Once you've used it, going back to `kubectl logs` for multi-replica deployments feels barbaric.

```
$ stern -n ingress-nginx .             # tail all ingress-nginx pods
$ stern -l app=web                      # all pods with that label
```

### 24.3 The three pillars in K8s

| Pillar | Stack |
|---|---|
| Metrics | metrics-server (raw) → kube-state-metrics + Prometheus → Grafana |
| Logs | Pod stdout → CRI → node disk → fluentbit/Vector → Loki/ELK |
| Traces | OpenTelemetry SDK in app → OTel collector DaemonSet → Tempo/Jaeger |

### 24.4 Reflect

Why is `kubectl logs` not enough on its own? (Pod evicted = logs gone. Multi-replica = correlation pain. Past windows = unavailable. That's why centralised logging exists.)

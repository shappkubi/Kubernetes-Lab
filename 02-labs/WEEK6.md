# Week 6 Labs — Production Patterns & Polish

Cluster: k3d `lab` for most.

---

## Lab 31 — GitOps with Argo CD

**Goal:** install Argo CD, wire it to a git repo, watch it reconcile drift.

### 31.1 Install (lightweight values)

```
$ kubectl create ns argocd
$ kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.11.0/manifests/install.yaml
$ kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
```

Get the initial admin password and port-forward:

```
$ kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
$ kubectl -n argocd port-forward svc/argocd-server 8081:443
```

Open https://localhost:8081, login as `admin`.

### 31.2 Wire an app

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    path: guestbook
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: guestbook
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
```

Apply, then watch in the UI. Argo polls the repo, computes a diff, and syncs.

### 31.3 Drift detection

```
$ kubectl -n guestbook scale deploy guestbook-ui --replicas=5
```

Argo detects drift and (with `selfHeal: true`) reverts to the spec in git. That's the GitOps loop.

### 31.4 Reflect

Imperative `kubectl apply` from a CI pipeline vs Argo CD pulling from git — pros/cons?
- Pull: cluster initiates, no inbound CI cred to cluster, drift visible/healable, easy multi-cluster.
- Push: simpler, immediate.

### 31.5 Cleanup

```
$ kubectl delete app -n argocd guestbook
$ kubectl delete ns argocd guestbook
```

Argo adds ~300 MB to disk usage; uninstall when the lab's done.

---

## Lab 32 — Helm: Charts and Templating

**Goal:** install, customize, and template a chart. Know when Helm vs Kustomize.

### 32.1 Install nginx via the bitnami chart (quick demo, then remove)

```
$ helm repo add bitnami https://charts.bitnami.com/bitnami
$ helm repo update
$ helm install demo bitnami/nginx --set service.type=ClusterIP --set replicaCount=1
$ helm list
$ helm get values demo
$ helm uninstall demo
```

### 32.2 Make your own minimal chart

```
$ helm create mychart
$ tree mychart
mychart/
├── Chart.yaml
├── charts/
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── _helpers.tpl
│   └── tests/
└── values.yaml
```

Edit `values.yaml`:

```yaml
replicaCount: 2
image:
  repository: nginx
  tag: "1.27"
service:
  type: ClusterIP
  port: 80
```

```
$ helm template mychart                # render to stdout, no apply
$ helm install local ./mychart
$ helm upgrade local ./mychart --set replicaCount=3
$ helm rollback local 1
```

`helm template` is your friend — render, eyeball the YAML, then apply.

### 32.3 Helm vs Kustomize

| | Helm | Kustomize |
|---|---|---|
| Mechanism | Go templates over YAML | Strategic merge / patches over base YAML |
| Strength | Distribution (charts on artifact hub), packaging | Overlays for env-specific changes, no templating language |
| Weakness | Templating sprawl, indentation pain | Limited transformation power |
| When | Distributing software (community charts) | Per-environment customization of your own apps |
| Use both? | Yes — Helm for vendored apps, Kustomize for your overlays |

### 32.4 Reflect

Why are Helm hooks (pre-install, post-upgrade) something you should be cautious about? (They run outside the normal reconcile loop, can leave clusters in mid-state if the hook fails, and don't compose well with GitOps tools.)

---

## Lab 33 — Multi-tenancy: Quotas, LimitRanges, NetPol

**Goal:** carve a namespace into a "tenant" with hard guardrails.

### 33.1 Setup

```
$ kubectl create ns tenant-a
$ kubectl label ns tenant-a tenant=a
```

### 33.2 ResourceQuota

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: tenant-a-quota, namespace: tenant-a }
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    persistentvolumeclaims: "5"
    requests.storage: 20Gi
    pods: "20"
    services.loadbalancers: "1"
    count/secrets: "20"
```

### 33.3 LimitRange (defaults & maxes per pod/container)

```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: tenant-a-defaults, namespace: tenant-a }
spec:
  limits:
    - type: Container
      default:        { cpu: 200m, memory: 256Mi }
      defaultRequest: { cpu: 100m, memory: 128Mi }
      max:            { cpu: 1,    memory: 1Gi }
      min:            { cpu: 50m,  memory: 64Mi }
```

LimitRange auto-fills missing requests/limits and rejects pods outside `min/max`. Combined with ResourceQuota, you get fairness.

### 33.4 NetworkPolicy as namespace boundary

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-other-namespaces, namespace: tenant-a }
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { tenant: a } }
```

Now only pods in `tenant-a` (or other namespaces labelled `tenant: a`) can reach pods in `tenant-a`.

### 33.5 Try to bust it

```
$ kubectl run -n tenant-a hog --image=nginx \
    --requests='cpu=3,memory=6Gi'      # blocked by ResourceQuota
$ kubectl run -n tenant-a tiny --image=nginx \
    --requests='cpu=10m,memory=16Mi'   # blocked by LimitRange (below min)
$ kubectl run -n tenant-a ok --image=nginx
$ kubectl describe pod ok -n tenant-a   # auto-filled with defaults from LimitRange
```

### 33.6 Reflect

When is namespace tenancy not enough? (Cluster-scoped CRDs leak across tenants. Privileged DaemonSets touch all nodes. If tenants are mutually distrusting, you want namespaces *plus* PSA + NetworkPolicy + Resource Quotas; for adversarial isolation, virtual clusters or separate clusters.)

---

## Lab 34 — Canary Deployments

**Goal:** roll a new version to 10% of traffic, monitor, then promote.

### 34.1 Manual canary with Services + replica counts

Cheapest way: keep two Deployments, tweak replica counts.

```yaml
# stable: 9 replicas, canary: 1 replica  → 10% by pod count (assumes even traffic)
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-stable }
spec:
  replicas: 9
  selector: { matchLabels: { app: app, track: stable } }
  template:
    metadata: { labels: { app: app, track: stable } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=v1"] }] }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-canary }
spec:
  replicas: 1
  selector: { matchLabels: { app: app, track: canary } }
  template:
    metadata: { labels: { app: app, track: canary } }
    spec: { containers: [{ name: c, image: hashicorp/http-echo, args: ["-text=v2"] }] }
---
apiVersion: v1
kind: Service
metadata: { name: app }
spec:
  selector: { app: app }       # matches both — Service load-balances ~10% to canary
  ports: [{ port: 5678, targetPort: 5678 }]
```

### 34.2 Real canary: Argo Rollouts (concept)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: app }
spec:
  strategy:
    canary:
      steps:
        - setWeight: 10
        - pause: { duration: 5m }
        - setWeight: 50
        - pause: { duration: 10m }
        - setWeight: 100
      analysis:
        templates: [{ templateName: error-rate }]
```

Argo Rollouts (or Flagger) integrates with a service mesh or ingress-nginx for **real percentage-based routing** (not pod-count). It also runs analysis runs (compare error rate / latency between stable and canary) and aborts on regression.

### 34.3 Reflect

Why do you almost always want progressive delivery in production? (A bug in a normal Deployment hits 100% of users at once. Canary + automated abort gives you a circuit breaker before customers feel it.)

---

## Lab 35 — Operators & CRDs (concept)

**Goal:** explain the operator pattern fluently.

### 35.1 The pattern in one sentence

An operator is a custom controller that reconciles a CRD into the actions a human operator would take to keep an application healthy.

### 35.2 The CRD half

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: { name: redises.cache.example.com }
spec:
  group: cache.example.com
  names:
    kind: Redis
    plural: redises
    singular: redis
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                replicas: { type: integer }
                version:  { type: string }
```

Now `kubectl get redises` works as a first-class K8s resource.

### 35.3 The controller half

A controller (Go, kubebuilder) implements `Reconcile(req)`:

```go
func (r *RedisReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. fetch Redis CR
    // 2. compare to desired state
    //    - is the StatefulSet in place at the right size?
    //    - is the headless Service there?
    //    - are leader/follower roles correct?
    // 3. take actions (create/update/delete child resources)
    // 4. return — K8s will call us again on watch events
}
```

The reconcile loop is the entire idea: declarative spec in, observed state out, controller closes the gap.

### 35.4 When to write one vs not

| Probably operator-worthy | Probably not |
|---|---|
| Distributed DB / queue with leader election, backups, version upgrades | Stateless web app |
| Multi-resource lifecycle (Cassandra, Kafka, etcd, Postgres-with-failover) | Single Deployment-shaped thing |
| Domain-specific knowledge encoded in the controller | Could just be a Helm chart |

### 35.5 Reflect

The "operator pattern" is just the K8s controller pattern applied to your domain. The same `informers → workqueue → reconcile` pipeline that the Deployment controller uses is what kubebuilder generates for you.

---

## Lab 36 — Mock Interview Day

Run `05-interview-prep/MOCK-INTERVIEW.md` from start to finish. Time yourself. Record (audio or video) — you'll catch your own filler words and shaky topics. Re-grade in a week.

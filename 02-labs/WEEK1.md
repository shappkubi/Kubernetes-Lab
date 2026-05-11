# Week 1 Labs — Architecture & Core Workloads

Cluster needed: **k3d `lab`** (default low-disk). Spin it up with `00-setup/02-create-k3d-cluster.ps1` if you haven't.

> Convention used in every lab: lines starting with `$` are commands; lines without are output you should expect (paraphrased). YAML blocks can be saved to a file and `kubectl apply -f`'d, or piped via `kubectl apply -f -`.

---

## Lab 1 — Architecture Tour

**Goal:** see every control-plane and node component, understand who's who, and watch the API request → etcd write → controller → scheduler → kubelet path actually happen.

### 1.1 Inventory the cluster

```
$ kubectl get nodes -o wide
$ kubectl get pods -n kube-system
$ kubectl get pods -A -o wide
```

In k3d, the "control plane" is the `k3s-server` container — k3s collapses kube-apiserver, controller-manager, scheduler, and an embedded etcd-equivalent into a single binary. That's a lab simplification; in production those are separate processes (often separate machines).

Spot the components running as pods (CoreDNS, metrics-server, ingress-nginx, local-path-provisioner) and the ones running as host processes inside the server container (the k3s binary itself, kubelet, containerd).

### 1.2 Watch a request flow

In one terminal:

```
$ kubectl get events -A -w
```

In a second terminal:

```
$ kubectl create deployment hello --image=nginx --replicas=2
```

You'll see events fire in this rough order:
- `ScalingReplicaSet` (Deployment controller created a ReplicaSet)
- `SuccessfulCreate` on the ReplicaSet (creating Pod objects)
- `Scheduled` (scheduler bound each Pod to a node)
- `Pulling` → `Pulled` (kubelet pulling the image)
- `Created` → `Started` (kubelet ran the container)

That sequence IS the K8s reconcile loop. Memorize it — it's the answer to "walk me through what happens when I run kubectl apply".

### 1.3 Inspect the ownership chain

```
$ kubectl get deploy hello -o yaml | grep -A2 ownerReferences
$ kubectl get rs -l app=hello -o yaml | grep -A4 ownerReferences
$ kubectl get pod -l app=hello -o jsonpath='{range .items[*]}{.metadata.name}: owner={.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}{end}'
```

Deployment → owns ReplicaSet → owns Pods. When you `kubectl delete deploy`, K8s walks the chain and garbage-collects.

### 1.4 Reflect

Write 5 lines: what is the API server, what is etcd, what does the scheduler do, what does the kubelet do, what does kube-proxy do. No looking.

---

## Lab 2 — Pods and Init Containers

**Goal:** internalize the pod lifecycle and the difference between an init container, a sidecar, and a main container.

### 2.1 Single-container pod with restart policies

```yaml
apiVersion: v1
kind: Pod
metadata: { name: never-restart }
spec:
  restartPolicy: Never
  containers:
    - name: bye
      image: busybox
      command: ["sh", "-c", "echo hi; sleep 5; exit 1"]
```

Apply, then `kubectl get pod never-restart -w`. After 5s the container exits 1. With `restartPolicy: Never` the pod goes to `Failed`. Change to `OnFailure` and re-create — it will restart with backoff. Watch `kubectl describe pod` for the `Last State / Reason` field — that's where CrashLoopBackOff information lives.

### 2.2 Init containers

```yaml
apiVersion: v1
kind: Pod
metadata: { name: web-with-init }
spec:
  initContainers:
    - name: wait-for-config
      image: busybox
      command: ["sh", "-c", "echo seeding...; sleep 10; echo done"]
  containers:
    - name: web
      image: nginx
      ports: [{ containerPort: 80 }]
```

`kubectl get pod web-with-init -w` shows `Init:0/1 → Init:1/1 → PodInitializing → Running`. Init containers run **sequentially to completion** before main containers start. They block startup — useful for migrations, waiting on dependencies, secrets bootstrapping.

### 2.3 Sidecar pattern (multi-container pod)

```yaml
apiVersion: v1
kind: Pod
metadata: { name: app-with-sidecar }
spec:
  volumes:
    - name: shared
      emptyDir: {}
  containers:
    - name: writer
      image: busybox
      command: ["sh", "-c", "while true; do date >> /var/log/app.log; sleep 2; done"]
      volumeMounts: [{ name: shared, mountPath: /var/log }]
    - name: log-shipper
      image: busybox
      command: ["sh", "-c", "tail -F /var/log/app.log"]
      volumeMounts: [{ name: shared, mountPath: /var/log }]
```

```
$ kubectl logs app-with-sidecar -c log-shipper -f
```

Two containers, one network namespace, one shared volume. That's the entire mental model of a pod. `kubectl exec -it app-with-sidecar -c writer -- sh` to enter the writer.

### 2.4 Reflect

Why do init containers exist when you could just script that into your main container's entrypoint? (Answer: separation of concerns, image reuse, and they get retried independently with the pod's restart policy.)

---

## Lab 3 — Deployments, ReplicaSets, Rolling Updates

**Goal:** drive a rolling update, watch surge/maxUnavailable, break the rollout deliberately, roll back.

### 3.1 Baseline

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 5
  selector: { matchLabels: { app: web } }
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: nginx:1.25
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /, port: 80 }
            periodSeconds: 2
```

```
$ kubectl apply -f web.yaml
$ kubectl rollout status deploy/web
```

### 3.2 Roll forward

```
$ kubectl set image deploy/web web=nginx:1.27
$ kubectl rollout status deploy/web
$ kubectl get rs -l app=web    # two ReplicaSets — old scaling down, new scaling up
$ kubectl rollout history deploy/web
```

### 3.3 Break it on purpose

```
$ kubectl set image deploy/web web=nginx:does-not-exist
$ kubectl get pods -l app=web    # ImagePullBackOff
$ kubectl rollout status deploy/web   # blocks
```

The Deployment respects `maxUnavailable: 1` — only one new bad pod at a time, the rest of the fleet keeps serving.

### 3.4 Roll back

```
$ kubectl rollout undo deploy/web
$ kubectl rollout status deploy/web
```

`undo` rolls to the previous ReplicaSet by spec hash, not by version tag. Worth understanding: the Deployment object stores a history of ReplicaSets (default 10), each is its own immutable spec; rolling back swaps which one is scaled up.

### 3.5 Reflect

What's the difference between `maxSurge` and `maxUnavailable`, and what happens if you set both to 0? (Answer: rollout deadlocks — there's no room to add a new pod and no permission to remove an old one.)

---

## Lab 4 — Services & kube-proxy

**Goal:** know all the Service types cold, understand the selector → Endpoints → kube-proxy chain, and be comfortable debugging "service exists, traffic doesn't flow".

### 4.1 ClusterIP

```yaml
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
```

```
$ kubectl apply -f svc.yaml
$ kubectl get svc web
$ kubectl get endpoints web
$ kubectl get endpointslices -l kubernetes.io/service-name=web
```

`Endpoints` (legacy) and `EndpointSlices` (current) hold the **actual list of pod IPs** behind the Service. The Service is just a virtual IP + selector; the data plane is the EndpointSlice + kube-proxy translating to iptables (or IPVS) rules on every node.

```
$ kubectl run debug --rm -it --image=busybox -- sh
/ # wget -qO- web    # hits ClusterIP, gets nginx welcome
/ # nslookup web
```

DNS for a Service is `<svc>.<ns>.svc.cluster.local`. CoreDNS resolves it to the ClusterIP.

### 4.2 NodePort

```
$ kubectl patch svc web -p '{"spec":{"type":"NodePort"}}'
$ kubectl get svc web    # observe the NodePort assigned in 30000–32767
```

NodePort opens that port on **every** node. Mostly useful for development and as a building block under LoadBalancer.

### 4.3 LoadBalancer (skip if MetalLB not installed)

In k3d default we disabled klipper-lb to free disk. To exercise this, either install MetalLB (see `00-setup`) or just read along.

### 4.4 Headless Service

```yaml
apiVersion: v1
kind: Service
metadata: { name: web-headless }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80 }]
```

`kubectl run debug --rm -it --image=busybox -- nslookup web-headless` — instead of one ClusterIP you get the **list of pod IPs**. This is how StatefulSets give pods stable, individually addressable DNS names.

### 4.5 Debug a broken Service

Mismatch the selector deliberately:

```
$ kubectl patch svc web -p '{"spec":{"selector":{"app":"wrong"}}}'
$ kubectl get endpoints web    # empty
```

Empty Endpoints == no traffic. Number-one most common Service bug. The 30-second debug ladder is in `03-troubleshooting/PLAYBOOK.md` § Service has no endpoints.

### 4.6 Reflect

Why is a Service IP a "virtual" IP and not bound to a NIC? (Answer: it only exists as an iptables/IPVS rule on each node — no interface holds it. That's why ping doesn't work to a ClusterIP, but TCP does.)

---

## Lab 5 — Ingress

**Goal:** route HTTP by host and path, understand that Ingress is a spec while the controller is what actually serves traffic.

### 5.1 Two backends

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-a }
spec:
  replicas: 1
  selector: { matchLabels: { app: app-a } }
  template:
    metadata: { labels: { app: app-a } }
    spec:
      containers:
        - name: c
          image: hashicorp/http-echo
          args: ["-text=hello from A"]
          ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata: { name: app-a }
spec:
  selector: { app: app-a }
  ports: [{ port: 80, targetPort: 5678 }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-b }
spec:
  replicas: 1
  selector: { matchLabels: { app: app-b } }
  template:
    metadata: { labels: { app: app-b } }
    spec:
      containers:
        - name: c
          image: hashicorp/http-echo
          args: ["-text=hello from B"]
          ports: [{ containerPort: 5678 }]
---
apiVersion: v1
kind: Service
metadata: { name: app-b }
spec:
  selector: { app: app-b }
  ports: [{ port: 80, targetPort: 5678 }]
```

### 5.2 Path-based routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - host: localhost
      http:
        paths:
          - path: /a
            pathType: Prefix
            backend: { service: { name: app-a, port: { number: 80 } } }
          - path: /b
            pathType: Prefix
            backend: { service: { name: app-b, port: { number: 80 } } }
```

```
$ curl http://localhost/a    # hello from A
$ curl http://localhost/b    # hello from B
```

### 5.3 What just happened?

The ingress-nginx controller is a Deployment running inside the cluster (`kubectl -n ingress-nginx get pod`). Its config is regenerated from `Ingress` objects via a control loop. The actual datapath: external client → Service of type LoadBalancer (k3d's serviceLB or your laptop's port 80) → ingress-nginx pod → backend Service → backend pod.

### 5.4 Reflect

Why is Ingress slowly being replaced by the Gateway API? (Hint: annotation sprawl, no clean abstraction for "the team running the LB" vs "the team running the app", weak support for protocols beyond HTTP/HTTPS.)

---

## Lab 6 — DaemonSets, Jobs, CronJobs, StatefulSet (intro)

**Goal:** fluent recall of when each workload type is correct.

### 6.1 DaemonSet (one per node)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-tag, namespace: kube-system }
spec:
  selector: { matchLabels: { app: node-tag } }
  template:
    metadata: { labels: { app: node-tag } }
    spec:
      tolerations: [{ operator: Exists }]
      containers:
        - name: tag
          image: busybox
          command: ["sh","-c","echo $(date) on $NODE; sleep 3600"]
          env: [{ name: NODE, valueFrom: { fieldRef: { fieldPath: spec.nodeName } } }]
```

```
$ kubectl -n kube-system get pods -l app=node-tag -o wide
```

One pod per node. Add a worker (k3d: `k3d node create --cluster lab --role agent extra1`) and watch a new DaemonSet pod appear automatically.

### 6.2 Job

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: pi }
spec:
  completions: 1
  backoffLimit: 4
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: perl:5.34
          command: ["perl","-Mbignum=bpi","-wle","print bpi(200)"]
```

```
$ kubectl logs job/pi
```

Difference vs Deployment: Jobs are for **work that finishes**. The Job tracks completion. `parallelism` + `completions` together give you batch parallel.

### 6.3 CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: { name: hello }
spec:
  schedule: "*/1 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: hi
              image: busybox
              command: ["sh","-c","date; echo hi from cron"]
```

After a couple of minutes:

```
$ kubectl get jobs    # one per scheduled run
$ kubectl get pods    # corresponding pods
```

### 6.4 StatefulSet (intro — full lab in Week 2)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: web }
spec:
  serviceName: web-headless    # the headless Service from Lab 4
  replicas: 3
  selector: { matchLabels: { app: web-sts } }
  template:
    metadata: { labels: { app: web-sts } }
    spec:
      containers:
        - name: web
          image: nginx
          ports: [{ containerPort: 80 }]
```

```
$ kubectl get pod -l app=web-sts -w
```


Pods come up **one at a time, in order: web-0, web-1, web-2**. Each has a stable name and DNS (`web-0.web-headless.default.svc.cluster.local`). Delete one — it comes back with the **same name and same identity**, unlike a Deployment pod which gets a new random suffix.

### 6.5 Reflect — when do you reach for each?

| Need | Workload |
|---|---|
| Stateless web app, scale freely, any pod is identical | Deployment |
| Process per node (log shipper, CNI, monitoring agent) | DaemonSet |
| Stateful service where each replica owns its own storage and identity (DBs, queues) | StatefulSet |
| One-shot batch work that must complete | Job |
| Recurring scheduled work | CronJob |

---

## End-of-week milestone

Without notes:
1. Draw the cluster architecture and label every component.
2. Spin up a Deployment behind a Service behind an Ingress and curl it.
3. Roll the Deployment forward, break it, roll it back, explain what you saw.
4. Tear it all down: `./00-setup/99-teardown.ps1`.

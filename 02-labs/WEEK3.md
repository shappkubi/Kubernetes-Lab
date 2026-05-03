# Week 3 Labs — Security, RBAC, Identity

Cluster: k3d `lab` (default).

---

## Lab 13 — Authn → Authz → Admission

**Goal:** trace a `kubectl` request through the API server's three gates.

```
                     ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
kubectl request ───► │   Authn     │───►│   Authz     │───►│  Admission  │───► etcd
                     │ who are you │    │ may you do  │    │ mutate /    │
                     │             │    │ this?       │    │ validate    │
                     └─────────────┘    └─────────────┘    └─────────────┘
```

### 13.1 Authn — who is the request from?

Sources the API server understands: client cert, bearer token (incl. ServiceAccount JWT), OIDC ID token, webhook. Look at your kubeconfig:

```
$ kubectl config view --raw -o jsonpath='{.users}'
```

You'll see a `client-certificate-data` (the cert that authenticates you) and a `client-key-data`. Decode the cert:

```
$ kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d | openssl x509 -text -noout | head -20
```

The cert's `Subject: CN=<user>, O=<group>` is what K8s uses for authorization. CN → username, O → group.

### 13.2 Authz — RBAC check

```
$ kubectl auth can-i create pods
$ kubectl auth can-i delete nodes
$ kubectl auth can-i list secrets --as=system:serviceaccount:default:default
```

`auth can-i` is the fastest debug for "why is this thing failing with Forbidden?". Use `--as` to impersonate any user/group/SA.

### 13.3 Admission

Built-in admission controllers run on every write. The defaults include `NamespaceLifecycle`, `LimitRanger`, `ServiceAccount`, `MutatingAdmissionWebhook`, `ValidatingAdmissionWebhook`. Modern clusters add `PodSecurity`.

```
$ kubectl get --raw='/api/v1/namespaces/default' | jq '.metadata.labels'
```

You'll see something like `kubernetes.io/metadata.name: default`. That label was added by the `NamespaceLabel` admission plugin — that's admission *mutating* a request.

### 13.4 Reflect

In what order do they run, and why does the order matter? (Authn → Authz → Mutating → Validating → etcd. If validation fails, mutation has already happened in memory but not been written. That's why mutating webhooks need to be reversible/idempotent.)

---

## Lab 14 — RBAC: Least-Privilege Role for a CI Bot

**Goal:** create a real ServiceAccount, give it just enough permissions, and prove it can do its job and nothing else.

### 14.1 The job description

The CI bot needs to deploy to namespace `prod`. It should be able to:
- list/get/update Deployments, Services, ConfigMaps, Secrets in `prod`
- read its own ServiceAccount

It should NOT be able to:
- touch any other namespace
- create or delete Namespaces
- read any other namespace's Secrets

### 14.2 Build it

```yaml
apiVersion: v1
kind: Namespace
metadata: { name: prod }
---
apiVersion: v1
kind: ServiceAccount
metadata: { name: ci-bot, namespace: prod }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: ci-deployer, namespace: prod }
rules:
  - apiGroups: ["apps"]
    resources: ["deployments", "deployments/scale"]
    verbs: ["get","list","watch","update","patch","create"]
  - apiGroups: [""]
    resources: ["services","configmaps","secrets"]
    verbs: ["get","list","watch","update","patch","create"]
  - apiGroups: [""]
    resources: ["pods","pods/log","events"]
    verbs: ["get","list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: ci-deployer, namespace: prod }
subjects:
  - kind: ServiceAccount
    name: ci-bot
    namespace: prod
roleRef:
  kind: Role
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
```

### 14.3 Verify

```
$ kubectl -n prod auth can-i update deploy --as=system:serviceaccount:prod:ci-bot       # yes
$ kubectl -n prod auth can-i delete deploy --as=system:serviceaccount:prod:ci-bot       # no (didn't grant delete)
$ kubectl -n default auth can-i list pods --as=system:serviceaccount:prod:ci-bot        # no
$ kubectl       auth can-i create ns      --as=system:serviceaccount:prod:ci-bot        # no
```

### 14.4 Use the SA from a pod

```yaml
apiVersion: v1
kind: Pod
metadata: { name: ci-test, namespace: prod }
spec:
  serviceAccountName: ci-bot
  containers:
    - name: kubectl
      image: bitnami/kubectl
      command: ["sleep","3600"]
```

```
$ kubectl -n prod exec ci-test -- kubectl get deploy        # works
$ kubectl -n prod exec ci-test -- kubectl get pods -n kube-system    # forbidden
```

The pod automatically receives a projected ServiceAccount token at `/var/run/secrets/kubernetes.io/serviceaccount/`. The token is short-lived and rotated by the kubelet (`BoundServiceAccountTokenVolume`).

### 14.5 Reflect

Difference between Role and ClusterRole? (Role is namespaced; ClusterRole is cluster-wide AND can be referenced by a RoleBinding to grant cluster-defined rules within a single namespace — useful for reusing common rules.)

---

## Lab 15 — Pod Security: SecurityContext + Pod Security Admission

**Goal:** harden a pod through SecurityContext, then enforce it cluster-wide via PSA.

### 15.1 Default-bad pod

```yaml
apiVersion: v1
kind: Pod
metadata: { name: bad }
spec:
  containers:
    - name: c
      image: nginx
      securityContext:
        privileged: true
        runAsUser: 0
```

Apply, then inspect:

```
$ kubectl exec bad -- id
uid=0(root)
$ kubectl exec bad -- cat /proc/self/status | grep CapEff   # all caps
```

### 15.2 Hardened pod

```yaml
apiVersion: v1
kind: Pod
metadata: { name: good }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 65532
    runAsGroup: 65532
    fsGroup: 65532
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: c
      image: nginxinc/nginx-unprivileged:1.27
      ports: [{ containerPort: 8080 }]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      volumeMounts:
        - { name: tmp, mountPath: /tmp }
        - { name: cache, mountPath: /var/cache/nginx }
        - { name: run, mountPath: /var/run }
  volumes:
    - { name: tmp, emptyDir: {} }
    - { name: cache, emptyDir: {} }
    - { name: run, emptyDir: {} }
```

Notes:
- `readOnlyRootFilesystem: true` requires writable emptyDirs for whatever paths the app writes to (nginx caches, /tmp, /var/run).
- `nginxinc/nginx-unprivileged` listens on 8080 because it's not root and can't bind to <1024.

### 15.3 Pod Security Admission

```
$ kubectl create ns secure
$ kubectl label ns secure pod-security.kubernetes.io/enforce=restricted
$ kubectl label ns secure pod-security.kubernetes.io/audit=restricted
$ kubectl label ns secure pod-security.kubernetes.io/warn=restricted
```

Try to apply the bad pod into `secure`:

```
$ kubectl -n secure apply -f bad.yaml
Error from server (Forbidden): pods "bad" is forbidden: violates PodSecurity "restricted:..."
```

Apply the good pod — works.

### 15.4 Reflect

Three PSA levels (`privileged`, `baseline`, `restricted`) — pick a sensible default per environment. `restricted` for app namespaces; `baseline` for system namespaces that need a few capabilities; `privileged` only for trusted things like CNI/CSI.

---

## Lab 16 — Secrets, For Real

**Goal:** know the production options for protecting secrets.

### 16.1 The problem

```
$ kubectl get secret db-creds -o yaml
```

`data.PASSWORD` is base64. Anyone with `get secret` permission sees the cleartext. Anyone with `etcdctl` access to the etcd data dir sees the cleartext too — secrets are stored as plain protobuf in etcd unless you've configured encryption-at-rest.

### 16.2 Three escape hatches

**a) Encryption at rest (the cluster does it).**
- API server config: `--encryption-provider-config=/etc/kubernetes/enc/enc.yaml`
- File defines providers — most production: `kms` (uses cloud KMS) with `aescbc` fallback.
- Once enabled, new writes are encrypted; old secrets are re-encrypted on touch (`kubectl get secret -A -o json | kubectl replace -f -`).
- *Read-only on a managed lab cluster* — concept-level for now.

**b) External Secrets Operator** (most common pattern in 2025+ environments).
- Secrets live in Vault / AWS Secrets Manager / Azure Key Vault / GCP Secret Manager.
- ESO syncs them into K8s Secret objects on a schedule.
- Pros: source of truth outside K8s; integrates with existing org secret stores.
- Cons: still creates a K8s Secret in cluster; protect with RBAC + encryption at rest.

**c) Sealed Secrets** (great for GitOps).
- `kubeseal` encrypts a Secret manifest with a public key from the cluster controller.
- Encrypted YAML is committed to git.
- Only the controller (with the private key) can decrypt; even the engineer who wrote the manifest cannot.

### 16.3 Read-only exercise

For ESO, mentally walk the flow:

```
ExternalSecret (CR) ──► ESO controller ──► reads Vault ──► writes K8s Secret ──► Pod mounts it
```

Where does the Vault credential come from? (A Kubernetes ServiceAccount JWT bound to a Vault role — the cluster's identity authenticates to Vault.)

### 16.4 Reflect

Why is "just put secrets in env vars from a ConfigMap" not secure even on a private cluster? (Image of cleartext at rest in etcd; visible to every pod with `get secret`; no audit trail of read; no rotation.)

---

## Lab 17 — Image Security

**Goal:** know image pull secrets, signature verification, distroless.

### 17.1 imagePullSecret for a private registry

```
$ kubectl create secret docker-registry regcred \
    --docker-server=registry.example.com \
    --docker-username=alice \
    --docker-password='xxx' \
    --docker-email=a@example.com
```

```yaml
apiVersion: v1
kind: Pod
metadata: { name: priv }
spec:
  imagePullSecrets: [{ name: regcred }]
  containers: [{ name: c, image: registry.example.com/team/app:1.0 }]
```

### 17.2 Distroless

Compare:

| Image | Size | Shell? | Package mgr? |
|---|---|---|---|
| `nginx` (Debian based) | ~190 MB | yes | yes |
| `nginxinc/nginx-unprivileged` (Alpine) | ~70 MB | yes | yes |
| `gcr.io/distroless/static` | ~2 MB | no | no |

Distroless = no shell, no busybox, just the binary and its dynamic libs. Drastically shrinks the attack surface — an RCE that wants `bash` or `wget` is dead in the water.

### 17.3 Signature verification (concept)

`cosign sign` (sigstore) signs an image and writes the signature to the registry. Admission controllers like `cosigned` or Kyverno's `verifyImages` rule reject pods whose images aren't signed by a trusted key. Production clusters increasingly require this as part of supply-chain security (SLSA).

### 17.4 Reflect

Three layers of "should this image run?":
1. Is the registry trusted? (private registry, allow-list)
2. Is the image signed by an authorized signer? (cosign + admission)
3. Does the image pass policy? (no critical CVEs via Trivy/Grype scanning in CI)

---

## Lab 18 — Service Mesh Primer

**Goal:** know what a mesh adds, when it earns its keep, and the mental model — without installing one (we're disk-conscious).

### 18.1 What a mesh adds

A service mesh injects a sidecar (Envoy / linkerd-proxy) into every pod. The sidecar takes over inbound and outbound traffic. From there:

| Capability | What it gives you |
|---|---|
| mTLS everywhere | Encryption + identity for every call, no app changes |
| Retries / timeouts / circuit breaking | Without changing app code |
| Traffic shifting | 1% canary, mirror traffic to staging, blue/green |
| Observability | RED metrics + per-call tracing without instrumentation |
| Authz on calls | "Service X may call Service Y, but only on /v1" |

### 18.2 When it earns its keep

- Many services (>20–30) and you need consistent retry/timeout policy.
- Hard regulatory requirement for mTLS between every pair.
- Teams want progressive delivery (Argo Rollouts works far better with a mesh).

### 18.3 When it doesn't

- Small clusters (under ~10 services). NetworkPolicies + a good HTTP client cover most needs at far less complexity.
- Latency-critical workloads where the sidecar's added hop is unacceptable.
- Teams without the operational headcount to debug Envoy.

### 18.4 Linkerd vs Istio (high level)

| | Linkerd | Istio |
|---|---|---|
| Proxy | linkerd2-proxy (Rust) | Envoy (C++) |
| Footprint | Smaller | Larger |
| Configuration | Simple | Many CRDs, steeper curve |
| Best at | "Just work, low overhead" | Power, ecosystem, gateway features |

### 18.5 Reflect

Why is a service mesh not a substitute for NetworkPolicy? (Mesh enforces L7 between pods that have the proxy. NetPolicy enforces L3/L4 cluster-wide and protects pods that aren't in the mesh. Defense in depth.)

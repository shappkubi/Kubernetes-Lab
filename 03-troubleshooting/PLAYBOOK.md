# Production Troubleshooting Playbook

This is the document you reread before any operations interview and bookmark for any pager rotation. Each section follows the same shape: **Symptom → Quickest diagnosis → Root causes → Fix → Reproduce in lab**.

The reproduction recipes are the secret weapon — actually causing each failure on your k3d cluster burns the diagnosis path into muscle memory.

---

## The universal first three commands

For any pod-shaped problem, in this order:

```
$ kubectl describe pod <name>            # events at the bottom — read them first
$ kubectl logs <name> --previous          # logs from the last (dead) container
$ kubectl get events --sort-by=.lastTimestamp -n <ns> | tail -20
```

90% of pod issues are diagnosable from these three. Don't skip to `kubectl exec` — if the container isn't running, you can't exec into it.

For node/cluster-shaped problems:

```
$ kubectl get nodes
$ kubectl describe node <node>
$ kubectl top node ; kubectl top pod -A --sort-by=memory
```

---

## 1. CrashLoopBackOff

**Symptom:** `kubectl get pod` shows `CrashLoopBackOff`. The pod started, exited, restarted, exited, kept exiting. Each loop adds backoff (10s, 20s, 40s, ...).

**Diagnosis:**

```
$ kubectl describe pod <name> | grep -A3 "Last State"
$ kubectl logs <name> --previous
```

**Root causes (ranked by frequency):**

1. App threw an exception on startup (config missing, DB unreachable, env var unset).
2. liveness probe is failing immediately because the app hasn't bound to its port yet → set a startupProbe.
3. Container's command is wrong / binary doesn't exist (`exec /app: not found`).
4. Permission error on a mounted volume (especially with `runAsNonRoot`).
5. App needs a graceful-shutdown window > terminationGracePeriodSeconds and getting SIGKILL'd.

**Fix:** read `--previous` logs, fix the app config, redeploy. If 30+ seconds startup is normal, add a `startupProbe` so liveness doesn't kill before app is ready.

**Reproduce:**

```yaml
apiVersion: v1
kind: Pod
metadata: { name: crash }
spec:
  restartPolicy: Always
  containers:
    - name: c
      image: busybox
      command: ["sh","-c","echo starting; sleep 2; exit 1"]
```

---

## 2. ImagePullBackOff / ErrImagePull

**Symptom:** pod stuck `Pending` or `ContainerCreating`; events say `Failed to pull image "..."`.

**Diagnosis:**

```
$ kubectl describe pod <name> | tail -20
```

Read the exact error. The four flavors:

| Error message | Cause |
|---|---|
| `repository does not exist or may require 'docker login'` | Private registry without `imagePullSecrets`, or wrong path |
| `manifest unknown` | Tag doesn't exist (typo, wrong tag) |
| `pull access denied` | imagePullSecret has wrong creds, or your token expired |
| `i/o timeout` / `dial tcp ...` | DNS or egress firewall — node can't reach registry |

**Fix:**

- Wrong tag: `kubectl set image deploy/foo c=image:correct-tag`
- Need pull secret: `kubectl create secret docker-registry regcred --docker-username=... --docker-password=... --docker-server=...` then add `imagePullSecrets: [{name: regcred}]` to the pod spec (or attach to a ServiceAccount).
- Network: SSH the node, `crictl pull <image>` and see the lower-level error.

**Reproduce:** `kubectl run bad --image=nginx:tag-that-does-not-exist`.

---

## 3. OOMKilled

**Symptom:** pod restarts; `kubectl describe pod` shows `Last State: Terminated, Reason: OOMKilled`.

**Diagnosis:**

```
$ kubectl describe pod <name> | grep -A3 "Last State"
$ kubectl top pod <name>
$ kubectl get events -n <ns> | grep -i OOM
```

**Root causes:**

1. App genuinely needs more memory than its limit allows — raise the limit.
2. Memory leak — `top` over time shows steady climb. Heap dump / profiling.
3. JVM default heap sized incorrectly — the JVM only sees the cgroup limit if you give it `-XX:+UseContainerSupport` or `-Xmx` consistent with the container limit.
4. Off-heap allocations (mmap, native libraries) eating non-heap memory the JVM doesn't know to track.

**Fix:** Raise memory limit, fix the leak, or right-size with VPA's recommender.

**Important nuance:** if `requests < limits`, the kubelet may evict the pod *before* OOMKill when the **node** is under memory pressure. That looks different — pod goes `Failed` with reason `Evicted`, not `OOMKilled`. Confirm with `kubectl get pod -o wide` and `kubectl describe pod`.

**Reproduce:** the `polinux/stress` snippet from `02-labs/WEEK4.md` § Lab 19.

---

## 4. Pending pod (won't schedule)

**Symptom:** pod stuck in `Pending` for minutes.

**Diagnosis:**

```
$ kubectl describe pod <name> | grep -A10 Events
```

Read the FailedScheduling message. Common patterns:

| Message | Meaning |
|---|---|
| `0/N nodes are available: N Insufficient cpu` | Pod's CPU request > any node's allocatable |
| `0/N nodes are available: N Insufficient memory` | Same for memory |
| `0/N nodes are available: N node(s) didn't match Pod's node affinity/selector` | nodeSelector or required affinity has no match |
| `0/N nodes are available: N node(s) had untolerated taint` | Tolerations missing |
| `0/N nodes are available: N node(s) didn't have free ports for the requested pod ports` | hostPort conflict |
| `0/N nodes are available: N pod has unbound immediate PersistentVolumeClaims` | PVC stuck in Pending |
| `node(s) didn't match Pod's anti-affinity rules` | Required anti-affinity has no node where pod can land |

**Fix:** depends on the message. Most common fixes:
- Lower the request (it was sized too aggressively).
- Add a node / let cluster autoscaler add one.
- Loosen affinity/anti-affinity from `required` to `preferred`.
- Check the PVC: `kubectl get pvc` — see § "PVC Pending".

**Reproduce:** `kubectl run hog --image=nginx --requests='cpu=100,memory=100Gi'`.

---

## 5. Service has endpoints but I can't reach it

**Symptom:** `curl <svc>` from inside the cluster times out or refuses, even though pods are Running.

**The 30-second debug ladder:**

```
$ kubectl get svc <svc>                          # exists?
$ kubectl get endpoints <svc>                    # has IPs? (CRITICAL CHECK)
$ kubectl describe svc <svc>                     # selector matches pods?
$ kubectl get pods --selector='<svc selector>' -o wide   # pods Running, Ready?
```

If `Endpoints: <none>`:
- Selector mismatch (typo in label or selector).
- Pods are running but not Ready (readiness probe failing).

If endpoints look right but you can't connect:
- Pod's container isn't listening on `targetPort`.
- NetworkPolicy is blocking — `kubectl describe networkpolicy -A` and check if anything selects your client or server.
- For NodePort/LoadBalancer: `kube-proxy` issue (rare); check `kubectl logs -n kube-system -l k8s-app=kube-proxy`.

**Reproduce:** the selector-mismatch trick from `02-labs/WEEK1.md` § Lab 4.

---

## 6. Service has no endpoints

This is sub-case of the above, but it's so common it deserves its own playbook.

```
$ kubectl get endpoints <svc>
NAME      ENDPOINTS         AGE
foo       <none>            5m
```

Three causes:

1. **Selector mismatch.** `kubectl get svc foo -o jsonpath='{.spec.selector}'` and `kubectl get pods --show-labels`. Compare exactly.
2. **Pods are not Ready.** `kubectl get pods -l app=foo` — note the `READY` column. If readiness probe is failing, pods aren't added to endpoints. `kubectl describe pod` to find why.
3. **Pod ports don't match.** If Service has `targetPort: 8080` but the pod's container exposes 9000, the EndpointSlice will have the wrong port.

---

## 7. DNS not resolving

**Symptom:** in-cluster name lookups fail. `nslookup kubernetes.default` returns SERVFAIL or times out.

**Diagnosis:**

```
$ kubectl run dnsdebug --rm -it --image=busybox -- sh
/ # cat /etc/resolv.conf                # nameserver should be CoreDNS ClusterIP
/ # nslookup kubernetes
/ # nslookup -timeout=2 google.com
/ # exit
$ kubectl -n kube-system get pods -l k8s-app=kube-dns
$ kubectl -n kube-system logs -l k8s-app=kube-dns
$ kubectl -n kube-system get svc kube-dns
```

**Root causes:**

1. CoreDNS is down / not enough replicas. Scale: `kubectl -n kube-system scale deploy coredns --replicas=2`.
2. NetworkPolicy in the namespace blocks egress to kube-dns. Allow port 53 UDP/TCP to `kube-system / k8s-app=kube-dns`.
3. Upstream DNS is broken (a CoreDNS forward error). Check `forward . /etc/resolv.conf` in CoreDNS Corefile.
4. `ndots:5` causing search-domain explosion overload — see Lab 11.

**Fix:** depends on the cause. The "CoreDNS is fine but my pod's NetworkPolicy blocks DNS" mistake is a top-3 cause of one-pod-can't-talk-to-anything.

---

## 8. Node NotReady

**Symptom:** `kubectl get nodes` shows a node `NotReady`. Workloads scheduled there go bad.

**Diagnosis:**

```
$ kubectl describe node <node> | tail -40
```

Look at `Conditions`. If `Ready: False`, the message tells you why. Top causes:

| Condition | Meaning |
|---|---|
| `KubeletNotReady` / `network plugin is not ready` | CNI agent (Calico/Cilium/etc.) not running or not configured |
| `MemoryPressure: True` | Free RAM below threshold; eviction kicking in |
| `DiskPressure: True` | Imagefs or nodefs filling up |
| `PIDPressure: True` | Out of process IDs |
| `Ready: False, message: PLEG is not healthy` | Container runtime issue (containerd/CRI-O hung) |

**Fix paths:**

- DiskPressure: `crictl ps -a` then `crictl rm` dead containers, `crictl rmi --prune` images. Bigger disk for the kubelet's image fs.
- MemoryPressure: scale workloads down, raise node size, kill noisy neighbors (`kubectl top pod -A --sort-by=memory`).
- CNI not ready: `kubectl -n kube-system get pods -l k8s-app=<cni>` — restart, check logs.
- PLEG: SSH the node, `systemctl restart containerd && systemctl restart kubelet`. If recurring, bigger problem.

---

## 9. PVC Pending

**Symptom:** `kubectl get pvc` shows `Pending`.

**Diagnosis:**

```
$ kubectl describe pvc <name>
```

| Message | Cause |
|---|---|
| `waiting for first consumer to be created before binding` | Storage class is `WaitForFirstConsumer` — normal until a pod uses the PVC |
| `no persistent volumes available for this claim and no storage class is set` | Missing `storageClassName` and no default StorageClass |
| `provisioning failed for ... could not provision in zone ...` | Cloud provisioner can't satisfy zone/size — check the provisioner pod logs |

**Fix:**

- Most common: add a Pod that mounts the PVC — `WaitForFirstConsumer` will then bind.
- Set the default StorageClass: `kubectl annotate sc local-path storageclass.kubernetes.io/is-default-class=true`.
- Cloud provisioner: check StorageClass parameters (zone, fsType, type) and IAM permissions.

---

## 10. Certs expired (kubeadm clusters)

**Symptom:** API server returns `Unable to authenticate the request` or kubectl times out with cert errors.

**Diagnosis:**

```
$ kubeadm certs check-expiration
```

**Fix:**

```
$ kubeadm certs renew all
$ systemctl restart kubelet
# restart static control-plane pods (delete their pods; kubelet recreates)
```

For client kubeconfigs, regenerate from the new CA. Managed clusters (EKS/GKE/AKS) don't have this problem — the cloud handles control-plane certs.

---

## 11. kube-apiserver overload

**Symptom:** kubectl is slow; clients see `Timeout: request did not complete within ...`; lots of `429 Too Many Requests`.

**Diagnosis:**

```
$ kubectl get --raw /metrics | grep apiserver_request_total | head
$ kubectl logs -n kube-system kube-apiserver-... | tail -50
```

Common causes:

1. A controller (sometimes a custom one) hot-looping → audit logs show one user/SA dominating.
2. Many large List requests (e.g. `kubectl get pod -A` over 100k pods). Switch to `--watch` + caching. APIServer Priority and Fairness (APF) helps.
3. etcd is slow (defrag overdue, disk IO degraded). Check `etcd_disk_wal_fsync_duration_seconds` p99 — should be <25ms.

**Fix:**

- Identify the bad client and stop it.
- Tune APF flow schemas to throttle non-critical clients.
- Defrag etcd: `etcdctl defrag` per member, off-hours.

---

## 12. Pod is Running but the app is slow

**Symptom:** pod is healthy from K8s' perspective; users see slow response.

**Diagnosis:**

```
$ kubectl top pod <name>                 # is it CPU bound?
$ kubectl describe pod <name>             # any throttling on container?
$ kubectl exec <name> -- cat /sys/fs/cgroup/cpu.stat   # nr_throttled, throttled_time
```

CPU **throttling** is invisible from the outside but devastating. Look at `container_cpu_cfs_throttled_seconds_total` — non-zero means you're being throttled and need a higher CPU limit (or no limit at all).

Other suspects:
- Memory pressure causing swap (rare on K8s; nodes typically run with swap off, so it manifests as OOMKill).
- Noisy neighbor on the node — `kubectl top pod -A --sort-by=cpu`.
- Network: drops on the CNI overlay, MTU mismatch (tcpdump on the node).

---

## 13. RBAC: "forbidden" but I should have access

**Symptom:** `Error from server (Forbidden): ...`

**Diagnosis:**

```
$ kubectl auth can-i <verb> <resource> -n <ns>
$ kubectl auth can-i <verb> <resource> -n <ns> --as=<user-or-sa>
$ kubectl get rolebinding,clusterrolebinding -A | grep <user-or-sa>
```

Use `--v=8` on the failing command to see the exact API path being checked — sometimes the issue is a sub-resource like `pods/exec` or `deployments/scale` and you only granted `pods` or `deployments`.

---

## 14. The "all my pods are Pending after upgrade" pattern

After a control-plane upgrade, suddenly things won't schedule. Causes:

1. New version added a default admission policy you weren't ready for (e.g. PodSecurity enforcement).
2. CRD versions changed; controllers using the old version error out.
3. The scheduler restarted and lost its cache (rare; usually recovers).

Check: `kubectl get events -A --sort-by=.lastTimestamp | tail -30` for admission rejections.

---

## 15. CrashLoopBackOff specifically after a config change

Common pattern: edit a ConfigMap, pods don't restart, then someone scales or rolls and **all** new pods crash because the new config is bad.

**Mitigation:**

- Roll deployments deliberately on config change so the bad config blast-radius is small.
- Annotate Deployments with a hash of the ConfigMap content (`stakater/Reloader` or `kubectl rollout restart`).
- Add a startup health check that validates config, so pods crash *fast* on bad config and stop the rollout via maxUnavailable.

---

## How to use this playbook in interviews

When asked "have you debugged X in production", structure your answer like this:

1. **Symptom** as the user/system saw it.
2. **What you checked first** (the universal three commands).
3. **What the events / logs told you.**
4. **Hypothesis and how you tested it.**
5. **Fix and how you verified.**
6. **Long-term prevention.**

Practice this on every section above. By the end of week 5 of the roadmap, you should be able to talk through any one of them cold.

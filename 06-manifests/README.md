# Sample Manifests Library

Copy-pasteable YAML for every primitive, with comments showing the trade-offs and the gotchas. Use these as starting points for labs and as references for interview "write me a YAML for X" prompts.

| File | What's in it |
|---|---|
| `pod.yaml` | Pod with init container, sidecar, securityContext, resources, probes |
| `deployment.yaml` | Deployment with rolling update strategy, anti-affinity, readiness/liveness, resources |
| `statefulset.yaml` | StatefulSet with headless Service, volumeClaimTemplates, anti-affinity |
| `daemonset.yaml` | DaemonSet that tolerates all taints (logging agent shape) |
| `job.yaml` | Job and CronJob with sane defaults |
| `service.yaml` | ClusterIP, NodePort, LoadBalancer, headless |
| `ingress.yaml` | Ingress with TLS, host + path routing |
| `configmap-secret.yaml` | All four ways to consume config and secrets |
| `pvc.yaml` | PVC with explicit storage class, access mode |
| `rbac.yaml` | ServiceAccount, Role, RoleBinding, ClusterRole pattern |
| `networkpolicy.yaml` | Default-deny + specific allow + cross-namespace allow |
| `hpa-pdb-quota.yaml` | HPA with behavior, PDB, ResourceQuota, LimitRange |
| `securitycontext-psa.yaml` | A pod that passes Pod Security `restricted` |
| `gateway.yaml` | Gateway API equivalent of common Ingress patterns |

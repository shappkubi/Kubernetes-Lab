#!/usr/bin/env bash
# Restore the lab to a known-good state after sim-page.sh has wreaked havoc.
# Idempotent — safe to run repeatedly.
set -uo pipefail
NS="${NS:-default}"

CTX=$(kubectl config current-context 2>/dev/null || echo "none")
echo "==> Restoring lab in context '$CTX', namespace '$NS'..."

# 1. Remove chaos-injected NetworkPolicy.
kubectl delete -n "$NS" netpol/chaos-deny-all 2>/dev/null || true

# 2. Remove cpu-stress chaos pod.
kubectl delete -n "$NS" pod/chaos-cpu --force --grace-period=0 2>/dev/null || true

# 3. Reset deploy/web to a sane state if it exists.
if kubectl get deploy web -n "$NS" >/dev/null 2>&1; then
  kubectl scale -n "$NS" deploy/web --replicas=3 >/dev/null
  kubectl set image -n "$NS" deploy/web web=nginx:1.25 >/dev/null
  # Strip any chaos-injected probes by removing readinessProbe entirely.
  kubectl patch -n "$NS" deploy/web --type=json \
    -p '[{"op":"remove","path":"/spec/template/spec/containers/0/readinessProbe"}]' \
    2>/dev/null || true
  kubectl rollout status deploy/web -n "$NS" --timeout=120s
fi

# 4. Restore service selector if it was tampered with.
if kubectl get svc web -n "$NS" >/dev/null 2>&1; then
  kubectl patch -n "$NS" svc/web --type=merge \
    -p '{"spec":{"selector":{"app":"web"}}}' >/dev/null
fi

# 5. Clean up any obvious chaos labels left behind.
kubectl get pods -n "$NS" --no-headers 2>/dev/null \
  | grep -E 'chaos-|sim-' \
  | awk '{print $1}' \
  | xargs -r -I{} kubectl delete pod -n "$NS" {} --force --grace-period=0 >/dev/null 2>&1 || true

echo "==> Restore complete. Cluster state:"
kubectl get all -n "$NS" 2>/dev/null

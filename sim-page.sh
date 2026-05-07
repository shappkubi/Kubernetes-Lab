#!/usr/bin/env bash
# Random K8s failure injector — simulates a page.
# WARNING: destructive. Only run against your lab cluster.
# Always verify context before running.

set -uo pipefail

CTX=$(kubectl config current-context 2>/dev/null || echo "none")
if [[ "$CTX" != "k3d-lab" && "$CTX" != "kind-lab-kind" ]]; then
  echo "REFUSING: current context is '$CTX'. Expected k3d-lab or kind-lab-kind."
  echo "Run: kubectl config use-context k3d-lab"
  exit 1
fi

NS="${NS:-default}"

# Make sure there's a deployment to break — create one if missing.
if ! kubectl get deploy web -n "$NS" >/dev/null 2>&1; then
  echo "Setting up target deployment 'web' in namespace '$NS'..."
  kubectl create deployment web --image=nginx:1.25 --replicas=3 -n "$NS"
  kubectl expose deployment web --port=80 -n "$NS" 2>/dev/null || true
  kubectl rollout status deploy/web -n "$NS" --timeout=120s
fi

FAILURES=(
  'random_pod_kill'
  'scale_to_zero'
  'bad_image'
  'cpu_chaos'
  'deny_all_netpol'
  'broken_readiness_probe'
  'wrong_service_selector'
)

random_pod_kill() {
  P=$(kubectl get pods -n "$NS" -o name 2>/dev/null | shuf -n 1)
  echo "Failure: deleting pod $P"
  kubectl delete -n "$NS" "$P" --grace-period=0 --force >/dev/null 2>&1
}

scale_to_zero() {
  echo "Failure: scaling deploy/web to 0"
  kubectl scale -n "$NS" deploy/web --replicas=0 >/dev/null
}

bad_image() {
  echo "Failure: pushing bad image to deploy/web"
  kubectl set image -n "$NS" deploy/web web=nginx:does-not-exist >/dev/null
}

cpu_chaos() {
  echo "Failure: starting cpu-stress chaos pod"
  kubectl run chaos-cpu --image=polinux/stress -n "$NS" --restart=Never \
    -- stress --cpu 4 --timeout 600s >/dev/null 2>&1 || true
}

deny_all_netpol() {
  echo "Failure: applying deny-all NetworkPolicy in $NS"
  kubectl apply -n "$NS" -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: chaos-deny-all}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF
}

broken_readiness_probe() {
  echo "Failure: patching deploy/web with readiness probe at /does-not-exist"
  kubectl patch -n "$NS" deploy/web --type=merge -p '{
    "spec":{"template":{"spec":{"containers":[{
      "name":"web",
      "readinessProbe":{"httpGet":{"path":"/does-not-exist","port":80},
                        "initialDelaySeconds":1,"periodSeconds":3,"failureThreshold":2}
    }]}}}}' >/dev/null
}

wrong_service_selector() {
  echo "Failure: changing service web selector to non-matching label"
  if kubectl get svc web -n "$NS" >/dev/null 2>&1; then
    kubectl patch -n "$NS" svc/web --type=merge \
      -p '{"spec":{"selector":{"app":"nope"}}}' >/dev/null
  else
    echo "(no svc/web present, skipping)"
    return 1
  fi
}

INDEX=$((RANDOM % ${#FAILURES[@]}))
F=${FAILURES[$INDEX]}

PAGE_TIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
echo "=========================================="
echo "[PAGE - SEV?] aks-lab / unknown-failure"
echo "Triggered: $PAGE_TIME"
echo "Cluster: $CTX"
echo "Namespace: $NS"
echo "Symptom: investigate"
echo "On-call: you"
echo "Bridge: zoom://platform-incident-bridge"
echo "=========================================="
echo "Internal note (failure injected: $F) — DO NOT PEEK; this stays printed but cover it"
echo
$F || true
echo
echo "Failure injected. Set a 30-min timer. Triage now."
echo "Open a fresh incident log:  vi 07-pe-sim/incidents/incident-$(date +%F-%H%M).md"

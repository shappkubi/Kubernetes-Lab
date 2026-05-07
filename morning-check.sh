#!/usr/bin/env bash
# Daily K8s cluster health check — run every morning.
# Builds the same reflexes you'd use at a real platform job.
set -uo pipefail
ALERT=0
LOGDIR="$(dirname "$0")/logs"
mkdir -p "$LOGDIR"
LOG="$LOGDIR/health-$(date +%F).log"

# Tee everything to both stdout and the day's log so you can compare day-to-day.
exec > >(tee -a "$LOG") 2>&1

echo "=== K8s Health Check $(date -u +'%Y-%m-%dT%H:%M:%SZ') ==="
echo "Context: $(kubectl config current-context 2>/dev/null || echo NONE)"

echo
echo "--- Nodes ---"
kubectl get nodes -o wide 2>/dev/null || { echo "ALERT: kubectl get nodes failed"; ALERT=1; }
NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2!="Ready"' | wc -l)
[[ "$NOT_READY" -gt 0 ]] && { echo "ALERT: $NOT_READY node(s) not Ready"; ALERT=1; }

echo
echo "--- Pods not Running/Completed ---"
BAD=$(kubectl get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l)
if [[ "$BAD" -gt 0 ]]; then
  kubectl get pods -A --no-headers 2>/dev/null | grep -vE 'Running|Completed'
  echo "ALERT: $BAD pod(s) unhealthy"; ALERT=1
else
  echo "All pods Running/Completed"
fi

echo
echo "--- Recent Warning/Error events (last 15) ---"
kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null \
  | grep -E 'Warning|Error' | tail -15 \
  || echo "(none)"

echo
echo "--- Latest 10 events overall ---"
kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | tail -10

echo
echo "--- Top nodes by usage ---"
kubectl top nodes 2>/dev/null | sort -rk3 | head -5 || echo "(metrics-server not ready)"

echo
echo "--- Top pods by memory ---"
kubectl top pods -A 2>/dev/null | sort -rk4 -n | head -10 || echo "(metrics-server not ready)"

echo
echo "--- PDBs at risk (DISRUPTIONS_ALLOWED == 0) ---"
PDB_AT_RISK=$(kubectl get pdb -A --no-headers 2>/dev/null | awk '$5=="0"' | wc -l)
if [[ "$PDB_AT_RISK" -gt 0 ]]; then
  kubectl get pdb -A --no-headers 2>/dev/null | awk '$5=="0"'
  echo "ALERT: $PDB_AT_RISK PDB(s) with no disruption budget left"; ALERT=1
else
  echo "OK"
fi

echo
echo "--- Deployments not at desired replicas ---"
DEPLOY_DRIFT=$(kubectl get deploy -A --no-headers 2>/dev/null \
  | awk '$3!=$4 || $5!=$4 {print}' | wc -l)
if [[ "$DEPLOY_DRIFT" -gt 0 ]]; then
  kubectl get deploy -A --no-headers 2>/dev/null | awk '$3!=$4 || $5!=$4 {print}'
  echo "ALERT: $DEPLOY_DRIFT Deployment(s) not at desired replicas"; ALERT=1
else
  echo "OK"
fi

echo
echo "--- ArgoCD apps (if installed) ---"
kubectl get applications -n argocd 2>/dev/null \
  | grep -vE '^NAME|Synced.*Healthy' \
  || echo "(none / all synced)"

echo
echo "--- Restart counts > 3 (last 24h) ---"
kubectl get pods -A --no-headers 2>/dev/null \
  | awk '{ if ($5+0 > 3) print $0 }' | head -10 \
  || echo "OK"

echo
if [[ "$ALERT" -eq 0 ]]; then
  echo "RESULT: cluster healthy ✅"
  exit 0
else
  echo "RESULT: ⚠️  ATTENTION — investigate alerts above"
  exit 1
fi

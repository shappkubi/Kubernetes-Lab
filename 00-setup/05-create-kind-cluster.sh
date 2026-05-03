#!/usr/bin/env bash
# Optional 4-node kind cluster — only for labs flagged "kind required" (topology spread, etc.).
# Costs ~3 GB; tear down immediately after.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker info >/dev/null 2>&1; then echo "Docker not running"; exit 1; fi

if kind get clusters 2>/dev/null | grep -q '^lab-kind$'; then
  echo "kind cluster 'lab-kind' already exists. Tear down first if recreating."
  exit 0
fi

echo "==> Creating kind cluster 'lab-kind' (~90s, ~3 GB disk)..."
kind create cluster --config "${HERE}/04-kind-config.yaml" --wait 5m

kubectl config use-context kind-lab-kind
kubectl get nodes -o wide

echo
echo "When the lab is done:  kind delete cluster --name lab-kind"

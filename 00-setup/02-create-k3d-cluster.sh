#!/usr/bin/env bash
# Creates the lab cluster from 01-k3d-config.yaml. Idempotent.
# Footprint in Codespace: ~1 GB disk, ~1 GB RAM.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Checking Docker..."
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker isn't running."
  echo "  - On Codespaces: this should be automatic via docker-in-docker feature. Try restarting the codespace."
  echo "  - Locally: start Docker Desktop / Rancher Desktop."
  exit 1
fi

echo "==> Existing k3d clusters:"
k3d cluster list || true

if k3d cluster list --output json | grep -q '"name": *"lab"'; then
  echo "Cluster 'lab' already exists. Run ./99-teardown.sh first to recreate."
  kubectl config use-context k3d-lab
  exit 0
fi

echo "==> Creating k3d cluster 'lab' (~30s, ~1 GB disk)..."
k3d cluster create --config "${HERE}/01-k3d-config.yaml"

kubectl config use-context k3d-lab
kubectl cluster-info
kubectl get nodes -o wide

echo
echo "✅ Cluster 'lab' is ready. Next: ./03-install-addons-k3d.sh"

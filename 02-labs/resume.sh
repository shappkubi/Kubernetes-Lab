#!/usr/bin/env bash
# Run me at the start of every Codespace session.
# Idempotent — safe to run if the cluster's already up.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Checking required CLI tools..."
need_install=false
for t in kind k3d stern kubectx; do
  if ! command -v "$t" &>/dev/null; then
    need_install=true; break
  fi
done

if $need_install; then
  echo "    Installing missing tools (one-time)..."
  KIND_VER=v0.23.0
  curl -fsSL -o /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-amd64"
  sudo install -m 0755 /tmp/kind /usr/local/bin/kind
  curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  STERN_VER=1.30.0
  curl -fsSL -o /tmp/stern.tgz "https://github.com/stern/stern/releases/download/v${STERN_VER}/stern_${STERN_VER}_linux_amd64.tar.gz"
  tar -C /tmp -xzf /tmp/stern.tgz stern
  sudo install -m 0755 /tmp/stern /usr/local/bin/stern
  sudo curl -fsSL -o /usr/local/bin/kubectx https://raw.githubusercontent.com/ahmetb/kubectx/master/kubectx
  sudo curl -fsSL -o /usr/local/bin/kubens  https://raw.githubusercontent.com/ahmetb/kubectx/master/kubens
  sudo chmod +x /usr/local/bin/kubectx /usr/local/bin/kubens
fi

echo "==> Creating k3d cluster (if not already up)..."
if k3d cluster list --output json 2>/dev/null | grep -q '"name": *"lab"'; then
  echo "    Cluster 'lab' already exists — using it."
else
  k3d cluster create --config 00-setup/01-k3d-config.yaml
fi
kubectl config use-context k3d-lab

echo "==> Installing ingress-nginx (if not already installed)..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update >/dev/null
if ! helm status -n ingress-nginx ingress-nginx >/dev/null 2>&1; then
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.replicaCount=1 \
    --set controller.service.type=LoadBalancer \
    --set controller.resources.requests.cpu=50m \
    --set controller.resources.requests.memory=64Mi \
    --set controller.admissionWebhooks.enabled=false
  kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
else
  echo "    ingress-nginx already installed."
fi

echo ""
echo "==> Cluster state:"
kubectl get nodes
echo ""
kubectl get pods -A
echo ""
echo "✅ Ready. Open 02-labs/WEEKn.md and continue your sprint."
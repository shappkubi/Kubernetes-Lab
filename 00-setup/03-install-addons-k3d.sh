#!/usr/bin/env bash
# Installs lab addons into the k3d 'lab' cluster:
#   - NGINX Ingress Controller (lightweight values)
#   - metrics-server (HPA + kubectl top)
# k3s already ships local-path-provisioner as the default StorageClass.
set -euo pipefail

kubectl config use-context k3d-lab >/dev/null

echo "==> Adding helm repos..."
helm repo add ingress-nginx  https://kubernetes.github.io/ingress-nginx       2>/dev/null || true
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
helm repo update >/dev/null

echo "==> Installing NGINX Ingress Controller (lab-tuned, single replica)..."
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.replicaCount=1 \
  --set controller.service.type=LoadBalancer \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=64Mi \
  --set controller.admissionWebhooks.enabled=false

echo "==> Installing metrics-server..."
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system \
  --set 'args={--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}' \
  --set resources.requests.cpu=20m \
  --set resources.requests.memory=64Mi

echo "==> Waiting for addons..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl -n kube-system  rollout status deployment/metrics-server            --timeout=180s

echo
echo "==> Cluster state:"
kubectl get nodes
kubectl get pods -A
kubectl get storageclass

echo
echo "✅ Addons installed. Smoke test:"
echo "  kubectl run web --image=nginx --port=80"
echo "  kubectl expose pod web --port=80"
echo "  kubectl create ingress web --rule='localhost/*=web:80'"
echo "  curl http://localhost"

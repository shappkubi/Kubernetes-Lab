# Installs the small set of addons we actually need into the k3d 'lab' cluster:
#   - NGINX Ingress Controller (chart, lab values)
#   - metrics-server (HPA + kubectl top)
# k3s already ships local-path-provisioner as the default StorageClass, so no extra storage install.
# MetalLB is intentionally NOT installed by default to save disk; the few labs that need it spin it up locally.

$ErrorActionPreference = "Stop"

# Make sure we're aimed at the lab cluster
kubectl config use-context k3d-lab | Out-Null

Write-Host "==> Adding helm repos..." -ForegroundColor Cyan
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>$null | Out-Null
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>$null | Out-Null
helm repo update | Out-Null

Write-Host "==> Installing NGINX Ingress Controller (lab-tuned, single replica)..." -ForegroundColor Cyan
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx `
  --namespace ingress-nginx --create-namespace `
  --set controller.replicaCount=1 `
  --set controller.service.type=LoadBalancer `
  --set controller.resources.requests.cpu=50m `
  --set controller.resources.requests.memory=64Mi `
  --set controller.admissionWebhooks.enabled=false

Write-Host "==> Installing metrics-server..." -ForegroundColor Cyan
helm upgrade --install metrics-server metrics-server/metrics-server `
  --namespace kube-system `
  --set args="{--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}" `
  --set resources.requests.cpu=20m `
  --set resources.requests.memory=64Mi

Write-Host "==> Waiting for addons to become Ready..." -ForegroundColor Cyan
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=180s
kubectl -n kube-system rollout status deployment/metrics-server --timeout=180s

Write-Host "`n==> Cluster state:" -ForegroundColor Cyan
kubectl get nodes
kubectl get pods -A
kubectl get storageclass

Write-Host "`nAddons installed. Smoke test:" -ForegroundColor Green
Write-Host "  kubectl run web --image=nginx --port=80" -ForegroundColor DarkGray
Write-Host "  kubectl expose pod web --port=80" -ForegroundColor DarkGray
Write-Host "  kubectl create ingress web --rule='localhost/*=web:80'" -ForegroundColor DarkGray
Write-Host "  curl http://localhost" -ForegroundColor DarkGray

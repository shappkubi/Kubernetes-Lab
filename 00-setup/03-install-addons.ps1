# Installs production-shaped addons into the lab cluster:
#   - NGINX Ingress Controller (kind-tuned)
#   - metrics-server (with --kubelet-insecure-tls for kind)
#   - local-path-provisioner (default StorageClass)
#   - MetalLB (real LoadBalancer Service support)
# Re-runnable: applies are idempotent.

$ErrorActionPreference = "Stop"

function Wait-ForCondition {
    param([string]$Namespace, [string]$Selector, [string]$Condition = "ready", [int]$TimeoutSec = 300)
    Write-Host "    waiting for $Selector in $Namespace..." -ForegroundColor DarkGray
    kubectl wait --namespace $Namespace --for=condition=$Condition pod --selector=$Selector --timeout=${TimeoutSec}s
}

# --- 1. NGINX Ingress (kind-specific manifest exposes 80/443 on the control plane host port)
Write-Host "==> Installing NGINX Ingress Controller..." -ForegroundColor Cyan
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
Wait-ForCondition -Namespace ingress-nginx -Selector "app.kubernetes.io/component=controller" -TimeoutSec 300

# --- 2. metrics-server — required for HPA, kubectl top
Write-Host "==> Installing metrics-server..." -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# kind nodes use self-signed kubelet certs; metrics-server needs to skip TLS verify in lab.
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
Wait-ForCondition -Namespace kube-system -Selector "k8s-app=metrics-server" -TimeoutSec 300

# --- 3. local-path-provisioner — auto-provisions hostPath PVs so PVCs actually bind
Write-Host "==> Installing local-path-provisioner..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite

# --- 4. MetalLB — gives us real LoadBalancer Services in the local docker network
Write-Host "==> Installing MetalLB..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
Wait-ForCondition -Namespace metallb-system -Selector "app=metallb" -TimeoutSec 300

# Find the docker subnet kind is on, then carve a small range for MetalLB.
$dockerNet = docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind | ForEach-Object { $_.Trim().Split(' ')[0] }
# e.g. 172.18.0.0/16 -> use 172.18.255.200-172.18.255.250 (safely outside kind's container range)
$base = $dockerNet.Split('.')[0..1] -join '.'
$ipPool = "$base.255.200-$base.255.250"

$metallbConfig = @"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - $ipPool
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - lab-pool
"@
$metallbConfig | kubectl apply -f -

Write-Host ""
Write-Host "==> Cluster state:" -ForegroundColor Cyan
kubectl get nodes
kubectl get pods -A
kubectl get storageclass

Write-Host ""
Write-Host "All addons installed." -ForegroundColor Green
Write-Host "Smoke test:  kubectl run web --image=nginx --port=80 ; kubectl expose pod web --type=LoadBalancer ; kubectl get svc web -w" -ForegroundColor DarkGray

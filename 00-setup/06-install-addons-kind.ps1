# Addons for the heavier kind cluster (NGINX ingress kind manifest, metrics-server, MetalLB, local-path).
# Only run after 05-create-kind-cluster.ps1.

$ErrorActionPreference = "Stop"
kubectl config use-context kind-lab-kind | Out-Null

Write-Host "==> NGINX Ingress (kind manifest)..." -ForegroundColor Cyan
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod `
  --selector=app.kubernetes.io/component=controller --timeout=300s

Write-Host "==> metrics-server..." -ForegroundColor Cyan
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json `
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

Write-Host "==> local-path-provisioner..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite

Write-Host "==> MetalLB..." -ForegroundColor Cyan
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s

$dockerNet = (docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind).Trim().Split(' ')[0]
$base = $dockerNet.Split('.')[0..1] -join '.'
@"
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: { name: lab-pool, namespace: metallb-system }
spec:
  addresses: [ "$base.255.200-$base.255.250" ]
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: { name: lab-l2, namespace: metallb-system }
spec:
  ipAddressPools: [ lab-pool ]
"@ | kubectl apply -f -

kubectl get nodes
kubectl get pods -A

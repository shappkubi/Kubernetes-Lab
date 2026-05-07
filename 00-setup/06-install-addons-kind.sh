#!/usr/bin/env bash
# Addons for the heavier kind cluster.
set -euo pipefail
kubectl config use-context kind-lab-kind >/dev/null

echo "==> NGINX Ingress (kind manifest)..."
kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/deploy-ingress-nginx.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

echo "==> metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo "==> local-path-provisioner..."
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite

echo "==> MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=300s

DOCKER_NET="$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}} {{end}}' kind | awk '{print $1}')"
BASE="$(echo "$DOCKER_NET" | awk -F. '{print $1"."$2}')"
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata: { name: lab-pool, namespace: metallb-system }
spec:
  addresses: [ "${BASE}.255.200-${BASE}.255.250" ]
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata: { name: lab-l2, namespace: metallb-system }
spec:
  ipAddressPools: [ lab-pool ]
EOF

kubectl get nodes
kubectl get pods -A

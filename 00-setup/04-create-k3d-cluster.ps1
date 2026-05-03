# Backup option: k3d (k3s in Docker). Faster than kind, slightly thinner architecture
# (single binary control plane, sqlite by default), still real enough for 90% of labs.
# Use this if Docker Desktop on your Windows is sluggish under kind, or if you want a
# second cluster in parallel (kind-lab + k3d-lab).

$ErrorActionPreference = "Stop"

if ((k3d cluster list --output json | ConvertFrom-Json).name -contains "lab2") {
    Write-Warning "k3d cluster 'lab2' already exists. Delete first: k3d cluster delete lab2"
    exit 0
}

Write-Host "==> Creating k3d cluster 'lab2' (3 agents, traefik disabled so we can install nginx-ingress)..." -ForegroundColor Cyan
k3d cluster create lab2 `
  --servers 1 `
  --agents 3 `
  --port "8080:80@loadbalancer" `
  --port "8443:443@loadbalancer" `
  --k3s-arg "--disable=traefik@server:0" `
  --wait

kubectl config use-context k3d-lab2
kubectl get nodes -o wide

Write-Host ""
Write-Host "k3d cluster 'lab2' is up. Reach Ingress at http://localhost:8080" -ForegroundColor Green

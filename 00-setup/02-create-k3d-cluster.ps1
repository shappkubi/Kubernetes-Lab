# Creates the lab cluster from 01-k3d-config.yaml. Idempotent.
# Footprint: ~1 GB disk, ~1 GB RAM.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Docker is up..." -ForegroundColor Cyan
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker doesn't seem to be running. Start Docker Desktop / Rancher Desktop and try again."
    exit 1
}

Write-Host "==> Existing k3d clusters:" -ForegroundColor Cyan
k3d cluster list

if ((k3d cluster list --output json | ConvertFrom-Json).name -contains "lab") {
    Write-Warning "k3d cluster 'lab' already exists. Run ./99-teardown.ps1 first to recreate."
    kubectl config use-context k3d-lab
    exit 0
}

Write-Host "==> Creating k3d cluster 'lab' (~30s, ~1 GB disk)..." -ForegroundColor Cyan
k3d cluster create --config "$here\01-k3d-config.yaml"

Write-Host "==> Cluster info:" -ForegroundColor Cyan
kubectl config use-context k3d-lab
kubectl cluster-info
kubectl get nodes -o wide

Write-Host ""
Write-Host "Cluster 'lab' is ready. Next: ./03-install-addons-k3d.ps1" -ForegroundColor Green

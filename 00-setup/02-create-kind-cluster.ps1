# Creates the lab cluster from 01-kind-config.yaml.
# Idempotent: if a 'lab' cluster already exists it'll abort. Use 99-teardown.ps1 first.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Docker is up..." -ForegroundColor Cyan
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker doesn't seem to be running. Start Docker Desktop and try again."
    exit 1
}

Write-Host "==> Existing kind clusters:" -ForegroundColor Cyan
kind get clusters

if ((kind get clusters) -contains "lab") {
    Write-Warning "Cluster 'lab' already exists. Run ./99-teardown.ps1 first if you want to recreate."
    exit 0
}

Write-Host "==> Creating kind cluster 'lab' (this takes ~60–90s)..." -ForegroundColor Cyan
kind create cluster --config "$here\01-kind-config.yaml" --wait 5m

Write-Host "==> Setting kubectl context to kind-lab..." -ForegroundColor Cyan
kubectl config use-context kind-lab

Write-Host "==> Cluster info:" -ForegroundColor Cyan
kubectl cluster-info
kubectl get nodes -o wide

Write-Host ""
Write-Host "Cluster 'lab' is ready. Next: ./03-install-addons.ps1" -ForegroundColor Green

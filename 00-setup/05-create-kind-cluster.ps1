# Optional heavier 4-node kind cluster — only for labs that say "kind required".
# Costs ~3 GB disk; tear down immediately after the lab.

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

docker info | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Error "Docker not running."; exit 1 }

if ((kind get clusters 2>$null) -contains "lab-kind") {
    Write-Warning "kind cluster 'lab-kind' already exists. Tear down first if recreating."
    exit 0
}

Write-Host "==> Creating kind cluster 'lab-kind' (~90s, ~3 GB disk)..." -ForegroundColor Cyan
kind create cluster --config "$here\04-kind-config.yaml" --wait 5m

kubectl config use-context kind-lab-kind
kubectl get nodes -o wide

Write-Host "`nWhen the lab is done, run:  kind delete cluster --name lab-kind" -ForegroundColor Yellow

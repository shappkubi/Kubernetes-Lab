# Tears down lab clusters and reclaims disk. Run at the end of EVERY session.

$ErrorActionPreference = "Continue"

Write-Host "==> Deleting k3d cluster 'lab' (if present)..." -ForegroundColor Cyan
k3d cluster delete lab 2>$null

Write-Host "==> Deleting kind cluster 'lab-kind' (if present)..." -ForegroundColor Cyan
kind delete cluster --name lab-kind 2>$null

Write-Host "==> Pruning dangling Docker volumes + stopped containers..." -ForegroundColor Cyan
docker container prune -f
docker volume prune -f

Write-Host "`n==> Disk after teardown:" -ForegroundColor Cyan
docker system df

Write-Host "`nTeardown complete." -ForegroundColor Green
Write-Host "If still tight on disk:  docker image prune -a -f  (removes ALL unused images)" -ForegroundColor DarkGray

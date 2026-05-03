#!/usr/bin/env bash
# Tears down lab clusters and reclaims disk. Run at the end of EVERY session.
set +e

echo "==> Deleting k3d cluster 'lab' (if present)..."
k3d cluster delete lab 2>/dev/null

echo "==> Deleting kind cluster 'lab-kind' (if present)..."
kind delete cluster --name lab-kind 2>/dev/null

echo "==> Pruning dangling Docker volumes + stopped containers..."
docker container prune -f
docker volume prune -f

echo
echo "==> Disk after teardown:"
docker system df

echo
echo "Teardown complete."
echo "If still tight on disk:  docker image prune -a -f  (removes ALL unused images)"

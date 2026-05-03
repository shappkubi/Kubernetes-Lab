#!/usr/bin/env bash
# Codespaces / Linux disk check and Docker cleanup helper.
set +e

echo "==> Free space:"
df -h / | sed -n '1,2p'

echo
echo "==> Docker disk usage:"
docker system df

echo
echo "==> kind clusters:"
kind get clusters 2>/dev/null

echo
echo "==> k3d clusters:"
k3d cluster list 2>/dev/null

echo
echo "Reclaim options:"
echo "  1) Light prune  - stopped containers + dangling images (safe)"
echo "  2) Heavy prune  - also unused images + build cache (most space recovered)"
echo "  3) Skip"
read -r -p "Choose [1/2/3]: " choice

case "$choice" in
  1)
    docker container prune -f
    docker image prune -f
    docker volume prune -f
    ;;
  2)
    docker container prune -f
    docker image prune -a -f
    docker volume prune -f
    docker builder prune -a -f
    ;;
  *)
    echo "Skipped."
    ;;
esac

echo
echo "==> After cleanup:"
docker system df

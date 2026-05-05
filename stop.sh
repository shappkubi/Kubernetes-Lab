#!/usr/bin/env bash
# Run me at the end of every Codespace session.
set +e
cd "$(dirname "$0")"

echo "==> Tearing down cluster..."
k3d cluster delete lab 2>/dev/null
docker container prune -f >/dev/null
docker volume prune -f >/dev/null

echo ""
echo "✅ Cluster torn down."
echo ""
echo "Don't forget to commit your notes if you wrote any:"
echo "    git add . && git commit -m 'Day N: <topic>' && git push"
echo ""
echo "Then stop the Codespace: ≡ menu → Codespaces: Stop Current Codespace"

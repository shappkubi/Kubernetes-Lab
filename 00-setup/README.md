# 00 — Lab Setup

Limited laptop disk? Three ways to run this lab, ranked for your situation:

| Path | Disk on your laptop | Best for | Setup |
|---|---|---|---|
| **GitHub Codespaces** ⭐ recommended | **0 GB** | Disk-constrained laptop. Full Linux, real Docker-in-Docker. | See `CODESPACES.md` |
| Local k3d | ~1 GB | Offline work; want everything local | `./02-create-k3d-cluster.ps1` |
| Killercoda (browser) | 0 GB | Quick destructive drills, HA / etcd / upgrades | Linked in `04-production-scenarios/` |

The labs themselves are identical regardless of where the cluster runs — the only difference is which setup script you use to create it.

## Quick start: Codespaces (recommended)

1. Push this folder to a GitHub repo (instructions in `CODESPACES.md`).
2. On github.com → your repo → green "Code" button → "Codespaces" → "Create codespace on main".
3. Wait ~3 min for first boot (kind, k3d, helm, stern, k9s, kubectx are auto-installed by `.devcontainer/post-create.sh`).
4. In the Codespace terminal:
   ```bash
   cd 00-setup
   ./02-create-k3d-cluster.sh
   ./03-install-addons-k3d.sh
   kubectl get nodes -o wide
   ```

That's it. Stop the Codespace when done for the day to preserve free-tier hours.

## Quick start: local on your Windows laptop

Footprint: ~1 GB for the cluster + ~1–2 GB for cached lab images.

Prereqs (one time):

```powershell
winget install -e --id Docker.DockerDesktop      # or Suse.RancherDesktop
winget install -e --id Kubernetes.kubectl
winget install -e --id Rancher.k3d
winget install -e --id Helm.Helm
winget install -e --id stern.stern               # optional but recommended
winget install -e --id Derailed.k9s              # optional
```

Verify:

```powershell
docker version
kubectl version --client
k3d version
helm version
```

Then:

```powershell
cd "C:\Users\admin\Documents\Claude\Projects\Kubernetes Lab\00-setup"
./00-disk-check-and-cleanup.ps1     # see Docker disk usage
./02-create-k3d-cluster.ps1         # ~30s, ~1 GB
./03-install-addons-k3d.ps1
kubectl get nodes -o wide
```

End-of-session habit (frees disk):

```powershell
./99-teardown.ps1
```

## Files in this folder

| File | Purpose | Codespaces (.sh) | Windows (.ps1) |
|---|---|---|---|
| `00-disk-check-and-cleanup` | See Docker disk usage; reclaim space | ✅ | ✅ |
| `01-k3d-config.yaml` | k3d cluster definition (1 server + 1 agent) | shared | shared |
| `02-create-k3d-cluster` | Spins up the primary cluster | ✅ | ✅ |
| `03-install-addons-k3d` | Installs ingress-nginx, metrics-server | ✅ | ✅ |
| `04-kind-config.yaml` | Heavier kind config (1 + 3 nodes) | shared | shared |
| `05-create-kind-cluster` | Creates the kind cluster (only when a lab needs it) | ✅ | ✅ |
| `06-install-addons-kind` | Addons for kind (incl. MetalLB) | ✅ | ✅ |
| `99-teardown` | Destroys all lab clusters and frees disk | ✅ | ✅ |
| `CODESPACES.md` | Detailed Codespaces setup guide | — | — |

In Codespaces, run the `.sh` versions. On Windows, run the `.ps1` versions. They do the same thing.

## When to use kind instead of k3d

Most labs work fine on k3d (1 server + 1 agent). A few — topology spread, multi-zone scheduling, DaemonSet visibility — really want ≥3 worker nodes. Those labs call this out explicitly. Spin up kind, do the lab, tear it down:

```bash
./05-create-kind-cluster.sh        # ~3 GB, ~90s (or .ps1 on Windows)
./06-install-addons-kind.sh        # adds MetalLB for LoadBalancer Services
# ...do the lab...
kind delete cluster --name lab-kind
```

## When to use Killercoda

Some scenarios need a real HA control plane, kubeadm-from-scratch, or destructive operations you don't want on your own machine. Run them in a Killercoda scenario instead:

- HA control plane setup (3 control plane nodes + LB)
- `kubeadm` install from scratch
- Cluster upgrades (1.29 → 1.30)
- etcd backup, restore, disaster recovery
- Node failure drills (`poweroff` a node)
- CNI swap (kindnet → Calico → Cilium)

Direct links per scenario are inlined in `02-labs/WEEK5.md` and `04-production-scenarios/SCENARIOS.md`.

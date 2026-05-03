# Running the lab in GitHub Codespaces

This is the recommended path for a disk-constrained laptop. Codespaces gives you a Linux container in the cloud with Docker-in-Docker — kind and k3d run there, **zero disk impact on your laptop**. You only need a browser.

## What you get on the free tier

| Tier | Hours/month | Storage | Machine |
|---|---|---|---|
| GitHub Free (personal) | 60 core-hours | 15 GB-month | Up to 4-core / 16 GB |
| GitHub Pro | 90 core-hours | 20 GB-month | Up to 8-core / 32 GB |

A 2-core Codespace counts as 2 core-hours per real hour. So 60 core-hours = 30 real hours per month on a 2-core, or 15 real hours on a 4-core. For this 6-week sprint at ~1.5 hr/day × 5 days/week, you'll fit comfortably on free.

> Tip: **stop your Codespace when you're done for the day** (not just close the browser). Idle Codespaces auto-stop after 30 min by default, but stopping manually is faster and cleaner.

## One-time setup

### 1. Push this folder to a private GitHub repo

In a terminal on your laptop:

```powershell
cd "C:\Users\admin\Documents\Claude\Projects\Kubernetes Lab"
git init
git add .
git commit -m "Kubernetes Lab pack"
# Create a new private repo called kubernetes-lab on github.com first.
git remote add origin https://github.com/<your-username>/kubernetes-lab.git
git branch -M main
git push -u origin main
```

The `.devcontainer/` folder at the repo root is what makes this a Codespaces project.

### 2. Open the repo as a Codespace

On github.com → your repo → green "Code" button → "Codespaces" tab → "Create codespace on main".

Pick the machine type:
- **2-core / 8 GB** — fine for weeks 1–3 (k3d 1+1, single-replica labs).
- **4-core / 16 GB** — recommended; comfortable for everything including kind, Argo CD, multi-replica labs.

First boot takes ~3–5 min while it builds the container, installs `kind`, `k3d`, `helm`, `stern`, `k9s`, `kubectx`, `kubent`, and runs the post-create script. After that, every reopen is ~30 seconds.

### 3. Create the cluster

Inside the Codespace's integrated terminal:

```bash
cd 00-setup
./02-create-k3d-cluster.sh
./03-install-addons-k3d.sh
kubectl get nodes -o wide
kubectl get pods -A
```

You should see 2 nodes Ready and pods Running in `kube-system`, `ingress-nginx`, `local-path-storage`.

## Smoke test (30 seconds)

```bash
kubectl run web --image=nginx --port=80
kubectl expose pod web --port=80
kubectl create ingress web --rule='localhost/*=web:80'
curl http://localhost
```

The `localhost` Ingress works because Codespaces auto-forwards port 80 from your container to a public URL it generates. Look at the "PORTS" tab in VS Code (bottom panel) — port 80 will show a forwarded URL you can also open in a browser.

## Daily workflow

| When | What |
|---|---|
| Start of session | Open the Codespace from github.com (or `gh codespace code` from your terminal) |
| Working | Run lab steps in the integrated terminal; edit YAML in VS Code |
| Mid-session if needed | `./00-disk-check-and-cleanup.sh` to free Docker layers |
| End of session | `./99-teardown.sh`, then **STOP** the Codespace (Cmd/Ctrl-Shift-P → "Codespaces: Stop Current Codespace") |

Stopping (vs deleting) preserves your files between days. Deleting wipes them.

## Cost-saving habits

- Pick 2-core for reading/exploring labs, 4-core only when you actually need it.
- Stop the Codespace at end of session — half-an-hour idle = 0.5 core-hours wasted.
- Tear down k3d cluster (`./99-teardown.sh`) at end of session — frees layered storage in the Codespace.
- One Codespace at a time — multiple stopped Codespaces still consume the storage GB-month.

## When to NOT use Codespaces

- You need to test something against a real cloud (EKS/GKE/AKS) — Codespaces gives you a Linux container, not a cloud account.
- You want offline/airplane work — Codespaces is browser-based.
- You're past your free monthly quota — fall back to local k3d (the PowerShell scripts in this folder still work) or to Killercoda for the heavy drills.

## Troubleshooting

**"Port 80 says it's listening but I can't reach it"** — VS Code → PORTS tab → right-click the row for port 80 → "Port Visibility: Public" (default is Private; only your GitHub identity can reach it). For curl-from-terminal tests, `curl http://localhost` works regardless.

**"Docker socket permission denied"** — happens occasionally if the docker-in-docker feature wasn't fully ready. `sudo systemctl restart docker` then retry. Or rebuild the container: VS Code → Cmd-Shift-P → "Codespaces: Rebuild Container".

**"helm install hangs forever"** — usually Codespace is on the smallest machine and metrics-server / ingress-nginx pods are CPU-starved. Bump to 4-core or scale `replicaCount=1` (already done in our scripts).

**"My Codespace is slow even at 4-core"** — check `kubectl top pod -A`. Often a forgotten polling loop or a leftover lab pod is using all the CPU. `./99-teardown.sh` and recreate.

## Pushing your work back

Codespaces share the same git history as the underlying repo. As you take notes (`01-curriculum/notes/dayNN.md`), commit and push from inside the Codespace:

```bash
git add .
git commit -m "week 1 notes"
git push
```

Your notes survive whether or not the Codespace is alive.

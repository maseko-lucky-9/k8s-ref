# M1 — Homelab Bootstrap Kickoff Runbook

**Goal:** Stand up a working MicroK8s cluster with ArgoCD running App-of-Apps, and one sample workload deployed via GitOps.

**Time budget:** ~6 hours focused work (single session).

**Definition of done:**
- `kubectl get nodes` returns a Ready node
- `kubectl get pods -n argocd` shows all pods Running
- `argocd/apps/` contains a working ApplicationSet manifest committed to this repo
- A sample workload (`nginx-demo` or equivalent) is deployed via ArgoCD sync, accessible over the homelab ingress
- 3 screenshots captured for the eventual portfolio case study (cluster, ArgoCD UI, sample app)

If any step blocks for >30 min, **stop and write an ADR** describing the decision point — don't grind.

---

## Pre-flight (30 min)

| Check | Command | Pass criterion |
|---|---|---|
| Host OS | `cat /etc/os-release` | Ubuntu 22.04+ |
| RAM | `free -h` | ≥8 GB total, ≥6 GB available |
| Disk | `df -h /` | ≥20 GB free |
| Snap | `snap version` | snap installed |
| Network | `ping -c 3 8.8.8.8` | Internet OK |
| Local IP | `ip -4 addr show \| grep inet` | Stable (not DHCP-ephemeral if possible) |
| `cloudflared` (optional) | `which cloudflared` | If exposing via Cloudflare Tunnel |

**If any check fails:** fix before proceeding. Don't skip.

---

## Phase 1 — MicroK8s install (~1 h)

> **ADR-0002 status:** This phase finalises the MicroK8s vs k3s vs kind decision. If MicroK8s addons cover ESO + cert-manager + monitoring with sane defaults → mark ADR-0002 Accepted with MicroK8s. Otherwise pause and re-evaluate.

```bash
cd ~/Repo/apps/k8s-ref
./scripts/bootstrap-microk8s.sh
```

The script:
1. Pre-flight checks (RAM, snap, sudo)
2. `snap install microk8s --classic --channel=1.30/stable`
3. Adds your user to the `microk8s` group (you'll need to re-login + re-run once)
4. Waits for cluster ready
5. Enables addons: dns, hostpath-storage, ingress, helm3, rbac, metrics-server
6. Exports kubeconfig to `~/.kube/config-microk8s`

**After re-login + second run completes, verify:**

```bash
export KUBECONFIG=~/.kube/config-microk8s
kubectl get nodes                # 1 Ready node
kubectl get pods -A              # CoreDNS, hostpath-provisioner, ingress-nginx Running
kubectl top node                 # metrics-server returning data
```

**Stop here and screenshot:** `kubectl get nodes -o wide` + `kubectl get pods -A` for the case study.

**ADR-0002 update:** if all six addons enabled cleanly within 15 min, mark MicroK8s as Accepted. Commit the ADR change.

---

## Phase 2 — ArgoCD install (~1 h)

Two install options. **Recommendation: Helm** (matches how you'd ship to a client).

### Option A — Helm (recommended)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd

helm install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.7.x \
  --set server.service.type=ClusterIP \
  --set configs.params."server\.insecure"=true \
  --wait
```

### Option B — Static manifests

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment --all -n argocd
```

### Verify

```bash
kubectl get pods -n argocd                                 # all Running
kubectl get svc -n argocd                                  # argocd-server ClusterIP

# Initial admin password (Helm install)
kubectl get secret -n argocd argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Port-forward UI
kubectl port-forward -n argocd svc/argocd-server 8081:80 &
# UI now at http://localhost:8081  (login: admin / <password>)
```

**Stop here and screenshot:** ArgoCD login screen + empty Applications list.

**Decision:** keep ArgoCD on `ClusterIP` + port-forward (lowest exposure) **or** wire up an Ingress + cert-manager TLS (more realistic but pulls Phase 3 work earlier). For M1, port-forward is acceptable — capture an ADR if you choose Ingress.

---

## Phase 3 — App-of-Apps bootstrap (~1.5 h)

Goal: this Git repo becomes the source of truth. ArgoCD watches `argocd/apps/` and self-syncs everything declared there.

### 3a — Create the bootstrap kustomization

In `argocd/bootstrap/`:

- `kustomization.yaml` — references namespace + the root Application
- `namespace.yaml` — `argocd` namespace (idempotent)
- `root-application.yaml` — single ArgoCD `Application` whose `path` is `argocd/apps/`, recursively syncing every manifest in there

The root Application points at this repo's `main` branch, which means **once bootstrapped, you never `kubectl apply` again** — every change is a Git commit.

### 3b — Create the first ApplicationSet

In `argocd/apps/`, create one ApplicationSet per logical group. Start with one:

- `infra-apps.yaml` — empty list initially (will grow with cert-manager, ESO etc. in M2)

### 3c — Apply the bootstrap ONCE

```bash
kubectl apply -k argocd/bootstrap
kubectl get applications -n argocd -w   # watch for sync
```

The root Application syncs first; it then triggers the ApplicationSets. If everything is wired correctly, deleting the root Application later would tear down everything declaratively (don't actually do this in M1).

### Gotchas

- **Repo URL must be reachable from the cluster.** If the repo is private, set up `argocd repo add` with SSH or HTTPS PAT.
- **Sync waves matter** — use `argocd.argoproj.io/sync-wave: "-1"` on namespace manifests so they apply before the workloads that need them.
- **Don't use `--prune` on the root app yet.** Wait until M2 when you're more confident.

**Stop here and screenshot:** ArgoCD UI showing the root Application synced + healthy.

---

## Phase 4 — First sample app (~1 h)

Add `argocd/apps/sample-nginx.yaml` (an Application or ApplicationSet entry) that deploys a trivial workload. Recommended:

- A 1-replica `nginx` Deployment + Service + Ingress
- Hello-world HTML mounted via ConfigMap
- Ingress hostname: `hello.k8s-ref.local` (add to your /etc/hosts pointing at the homelab IP)

Commit + push the manifest. Within ~30s ArgoCD detects the change and syncs.

### Verify

```bash
kubectl get pods -n sample           # 1 Running
kubectl get ingress -n sample        # ADDRESS populated

# From homelab host:
curl -H "Host: hello.k8s-ref.local" http://<homelab-ip>/
# Should return the hello-world HTML
```

**Stop here and screenshot:** browser showing `hello.k8s-ref.local` working.

---

## Phase 5 — Capture + commit (~30 min)

### Screenshots for the portfolio case study

Save to a local `case-study-assets/` folder (NOT committed to this repo — they belong on the portfolio site):

1. `01-cluster-ready.png` — `kubectl get nodes -o wide` terminal
2. `02-pods-all-namespaces.png` — `kubectl get pods -A` terminal
3. `03-argocd-ui-empty.png` — ArgoCD login + empty app list
4. `04-argocd-root-synced.png` — ArgoCD UI with root Application synced + healthy
5. `05-sample-nginx-running.png` — browser showing hello-world page
6. `06-arch-diagram.png` — Mermaid → SVG of the M1 cluster topology

### Loom walkthrough (optional but high-leverage)

5–7 min screen recording: bootstrap script → cluster up → ArgoCD UI → sample app accessible. Will live on the portfolio case-study page.

### Final commits to k8s-ref

```bash
git add scripts/bootstrap-microk8s.sh \
        argocd/bootstrap/ \
        argocd/apps/ \
        docs/architecture/cluster-topology.md \
        docs/decisions/0002-*.md   # Update ADR-0002 status if MicroK8s won
git commit -m "feat(m1): homelab bootstrap + ArgoCD App-of-Apps + nginx sample"
git push
```

### Update the README roadmap

Tick M1 in `README.md`:

```diff
-- [ ] **M1**: MicroK8s bootstrap + ArgoCD up + first sample app deployed
++ [x] **M1**: MicroK8s bootstrap + ArgoCD up + first sample app deployed
```

---

## Common gotchas

| Symptom | Likely cause | Fix |
|---|---|---|
| `kubectl: command not found` | snap shim not aliased, or kubectl not installed | `alias kubectl='microk8s kubectl'` OR `sudo snap install kubectl --classic` |
| `dial tcp: i/o timeout` calling cluster | Group membership not refreshed | Re-login or `newgrp microk8s` |
| ArgoCD pods stuck in `Pending` | hostpath-storage addon not enabled or RAM exhausted | `microk8s enable hostpath-storage`; check `kubectl describe pod` for events |
| ArgoCD UI returns 404 | Service type wrong (NodePort vs ClusterIP mismatch with port-forward) | Re-check `kubectl get svc -n argocd` |
| Sample app `Ingress ADDRESS` empty | ingress-nginx not ready or NetworkPolicy blocking | `kubectl get pods -n ingress`; restart if needed |
| Repo URL not reachable from cluster | Cluster can't pull from GitHub (firewall) | Run from inside cluster: `kubectl run -it --rm test --image=alpine -- sh -c "wget https://github.com"` |

---

## Stop conditions

Stop the M1 session and re-plan if:

- After Phase 1, MicroK8s + 6 addons used >50% of available RAM → re-evaluate ADR-0002 (k3s might fit better)
- After Phase 2, ArgoCD pods crashloop → don't grind; capture logs, file an issue, switch to ADR work for the rest of the session
- After Phase 3, App-of-Apps bootstrap fails twice → walk away; the wiring is wrong, fresh eyes needed

---

## After M1

- Mark M1 complete in README + tick the box in the roadmap
- Open M2 (cert-manager + ESO + Vault) — separate session
- Update the launch plan in `wiki/career/project/launch-plan-6mo.md`: M1 took N hours of the 40h project budget — recalibrate if needed
- Push case-study screenshots to `portfolio-website/portfolio-ui/public/images/projects/k8s-ref-arch/` (replace the placeholder thumbnail)

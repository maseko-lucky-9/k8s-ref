# M2 Apply Runbook — ESO Vault Swap (namespace-isolated)

> Consolidated apply sequence for Slice 4 of the M2 portfolio milestone.
> Code committed; this runbook is the human-driven apply step.
>
> **Reference**: [ADR-0004](../decisions/0004-vault-dev-mode-for-eso-migration.md), commits `485797a` / `829179c` / `e500c2c` / `5bc40ef` / `1e9a8e2` + the 2026-05-18 namespace-isolation refactor.

> **Why a separate namespace?** The homelab already runs a production Vault at namespace `vault` (deployed 2026-04-08, 12 ExternalSecret consumers). The M2 demo Vault is dev-mode (in-memory, root token `"root"`, no persistence) and lives in `vault-k8s-ref-demo` so it cannot collide with or destroy production data. See ADR-0004 § Namespace isolation.

---

## Prereqs

1. Cluster reachability — **pick ONE of two transports** (the homelab API cert SAN includes both):

   **Option A — Tailscale-direct (preferred; no SSH tunnel needed):**
   ```bash
   export KUBECONFIG=$HOME/.kube/config-homelab-ts
   # config-homelab-ts points server: at https://100.114.75.127:16443
   kubectl get nodes   # should show `homelab` Ready
   ```

   **Option B — SSH tunnel (legacy):**
   ```bash
   ssh -L 16443:127.0.0.1:16443 -N homelab-tunnel
   # tunnel uses svc-ai-agent because dev has AllowTcpForwarding no per 99-hardened.conf
   export KUBECONFIG=$HOME/.kube/config-homelab
   kubectl get nodes
   ```

2. Commits pushed to `origin/main` so ArgoCD can pull from `repoURL` with `targetRevision: HEAD`:
   ```bash
   git push origin main
   ```

3. Sanity check — confirm namespace `vault-k8s-ref-demo` does NOT already exist (it should NOT):
   ```bash
   kubectl get ns vault-k8s-ref-demo 2>&1 | grep -q NotFound && echo "OK — namespace clean"
   ```

---

## Step 1 — Deploy demo Vault + bootstrap config

```bash
kubectl apply -f argocd/apps/vault.yaml
kubectl apply -f argocd/apps/vault-bootstrap.yaml
```

Watch sync progress:

```bash
kubectl get applications -n argocd vault-k8s-ref-demo vault-k8s-ref-demo-bootstrap -w
# Wait for both: SYNC STATUS=Synced, HEALTH STATUS=Healthy
```

Bootstrap Job (runs in wave 1):

```bash
kubectl get job -n vault-k8s-ref-demo vault-bootstrap-config -w
# Wait for COMPLETIONS=1/1
```

Inspect bootstrap logs (one-time):

```bash
kubectl logs -n vault-k8s-ref-demo job/vault-bootstrap-config --tail=50
# Expect: enable k8s auth → write config → write policy → bind role → seed secret → done
```

**Failure path:** if the Job pod fails, `kubectl describe job -n vault-k8s-ref-demo vault-bootstrap-config` reveals which step. The Job is idempotent; a re-sync runs it again.

---

## Step 2 — Flip ExternalSecret backend to Vault

Edit `helm/charts/k8s-ref-demo/values.yaml`:

```yaml
eso:
  enabled: true
  serviceAccountName: eso-reader
  useVault: true   # ← was false
  vault:
    server: "http://vault-k8s-ref-demo.vault-k8s-ref-demo.svc.cluster.local:8200"
    kvMount: "secret"
    kvVersion: "v2"
    role: "k8s-ref-demo"
```

Commit + push:

```bash
git add helm/charts/k8s-ref-demo/values.yaml
git commit -m "feat(eso): activate Vault backend — M2 cutover"
git push origin main
```

ArgoCD reconciles `k8s-ref-demo` Application automatically (auto-sync enabled). Watch:

```bash
kubectl get application -n argocd k8s-ref-demo -w
```

---

## Step 3 — Verify

Run the verifier:

```bash
./scripts/verify-eso-vault-migration.sh
```

Expected output (all 6 checks pass):

```
OK vault-k8s-ref-demo  Synced/Healthy
OK vault-k8s-ref-demo-bootstrap  Synced/Healthy
OK vault-bootstrap-config Job Complete=True
OK Vault-backed ClusterSecretStore present
OK ExternalSecret secretStoreRef = k8s-ref-demo-vault-store
OK ExternalSecret Ready=True
OK Secret tenant-config.app-env = 'production-vault'
OK Rotation propagated: app-env = 'rotated-<unix-ts>' after Nx2s polls
```

If step (F) rotation roundtrip fails, the migration is functionally complete (read works) but ESO can't refresh — likely a Vault role binding mismatch. Re-run `kubectl logs -n vault-k8s-ref-demo job/vault-bootstrap-config` and confirm the role's `bound_service_account_namespaces` matches the chart namespace (`k8s-ref-demo`, not the Vault namespace).

---

## Step 4 — Capture P8 (Vault UI proof for portfolio)

Port-forward the demo Vault UI:

```bash
kubectl port-forward -n vault-k8s-ref-demo svc/vault-k8s-ref-demo 8200:8200
```

Open `http://127.0.0.1:8200` → log in with token `root` → browse to `secret/eso-source-config`.

Screenshot the seeded data. Save to `docs/portfolio-item-assets/p8-vault-ui.png`.

Update `docs/portfolio-item.md` and `docs/case-study/k8s-ref.md` to flip P8 status to ✅.

---

## Step 5 — Cleanup commit (after verification passes)

Once Slice 4 verification is green, the old kubernetes-backed `ClusterSecretStore` template is dead code:

```bash
git rm helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store.yaml
git commit -m "chore(eso): remove kubernetes-backed ClusterSecretStore — Vault is now sole backend"
git push origin main
```

Move ADR-0004 from `Proposed` → `Accepted` in the same series of commits (edit `docs/decisions/0004-vault-dev-mode-for-eso-migration.md` `## Status` line).

---

## Rollback path

**Tier 1 (ESO only — preferred):** flip the flag, ArgoCD reconciles back to the kubernetes provider.

```bash
# Option A — revert the commit
git revert <commit-that-flipped-useVault>
git push origin main
# ExternalSecret returns to in-cluster source within one reconcile.
# tenant-config Secret keeps the last successfully synced values until then.

# Option B — manual hot-swap (faster, doesn't wait for ArgoCD)
kubectl patch externalsecret -n k8s-ref-demo tenant-config \
  --type=merge -p '{"spec":{"secretStoreRef":{"name":"k8s-ref-demo-store"}}}'
# Then revert the git commit at your own pace.
```

**Tier 2 (full demo-Vault removal):** when Vault itself is broken or you want to start over.

```bash
kubectl delete -f argocd/apps/vault-bootstrap.yaml
kubectl delete -f argocd/apps/vault.yaml
kubectl delete namespace vault-k8s-ref-demo --wait=false
```

Production Vault at namespace `vault` is **never touched** by either rollback tier — its consumers (`affiliate-yt`, `n8n-live`, `observability`, `prod`) remain healthy throughout.

Vault dev-mode uses ephemeral storage — Tier 2 loses all seeded data, which is fine for a demo restart.

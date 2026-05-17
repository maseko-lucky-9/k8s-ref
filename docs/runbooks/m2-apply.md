# M2 Apply Runbook — ESO Vault Swap

> Consolidated apply sequence for Slice 4 of the 2026-05-17 resume plan.
> Code committed; this runbook is the human-driven apply step.
>
> **Reference**: [ADR-0004](../decisions/0004-vault-dev-mode-for-eso-migration.md), [tasks/todo.md](../../tasks/todo.md), commits `485797a` / `829179c` / `e500c2c` / `5bc40ef`.

---

## Prereqs

1. SSH tunnel to the homelab apiserver open (Vault auth + ESO controller live in-cluster — your local kubectl only needs API access):
   ```bash
   ssh -L 16443:127.0.0.1:16443 -N homelab-tunnel
   ```
   Tunnel uses `svc-ai-agent` because `dev` user has `AllowTcpForwarding no` per `99-hardened.conf`.

2. Kubeconfig exported:
   ```bash
   export KUBECONFIG=$HOME/.kube/config-homelab
   kubectl get nodes   # sanity check — should show `homelab` Ready
   ```

3. Commits pushed to `origin/main` so ArgoCD can pull from `repoURL` with `targetRevision: HEAD`:
   ```bash
   git push origin main
   ```

---

## Step 1 — Deploy Vault dev mode + bootstrap config

```bash
kubectl apply -f argocd/apps/vault.yaml
kubectl apply -f argocd/apps/vault-bootstrap.yaml
```

Watch sync progress:

```bash
kubectl get applications -n argocd vault vault-bootstrap -w
# Wait for both: SYNC STATUS=Synced, HEALTH STATUS=Healthy
```

Bootstrap Job (runs in wave 1):

```bash
kubectl get job -n vault vault-bootstrap-config -w
# Wait for COMPLETIONS=1/1
```

Inspect bootstrap logs (one-time):

```bash
kubectl logs -n vault job/vault-bootstrap-config --tail=50
# Expect: enable k8s auth → write config → write policy → bind role → seed secret → done
```

**Failure path:** if the Job pod fails, `kubectl describe job -n vault vault-bootstrap-config` reveals which step. The Job is idempotent; a re-sync runs it again.

---

## Step 2 — Flip ExternalSecret backend to Vault

Edit `helm/charts/k8s-ref-demo/values.yaml`:

```yaml
eso:
  enabled: true
  serviceAccountName: eso-reader
  useVault: true   # ← was false
  vault:
    server: "http://vault.vault.svc.cluster.local:8200"
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
OK vault  Synced/Healthy
OK vault-bootstrap  Synced/Healthy
OK vault-bootstrap-config Job Complete=True
OK Vault-backed ClusterSecretStore present
OK ExternalSecret secretStoreRef = k8s-ref-demo-vault-store
OK ExternalSecret Ready=True
OK Secret tenant-config.app-env = 'production-vault'
OK Rotation propagated: app-env = 'rotated-<unix-ts>' after Nx2s polls
```

If step (F) rotation roundtrip fails, the migration is functionally complete (read works) but ESO can't refresh — likely Vault role binding mismatch. Re-run `kubectl logs -n vault job/vault-bootstrap-config` and confirm the role's `bound_service_account_namespaces` matches the chart namespace.

---

## Step 4 — Capture P8 (Vault UI proof for portfolio)

Port-forward Vault UI:

```bash
kubectl port-forward -n vault svc/vault 8200:8200
```

Open `http://127.0.0.1:8200` → log in with token `root` → browse to `secret/eso-source-config`.

Screenshot the seeded data. Save to `docs/portfolio-item-assets/p8-vault-secrets.png`.

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

If Vault becomes unreliable mid-migration:

```bash
# Option A — revert the flag, ArgoCD reconciles back to the kubernetes provider
git revert <commit-that-flipped-useVault>
git push origin main
# ExternalSecret returns to in-cluster source within one reconcile.
# tenant-config Secret keeps the last successfully synced values until then.

# Option B — manual hot-swap (faster, doesn't wait for ArgoCD)
kubectl patch externalsecret -n k8s-ref-demo tenant-config \
  --type=merge -p '{"spec":{"secretStoreRef":{"name":"k8s-ref-demo-store"}}}'
# Then revert the git commit at your own pace.
```

The `vault` and `vault-bootstrap` Applications can stay deployed (idle) or be deleted:

```bash
kubectl delete -f argocd/apps/vault-bootstrap.yaml
kubectl delete -f argocd/apps/vault.yaml
```

Vault uses ephemeral storage in dev mode — deleting the Application loses all seeded data, which is fine for a demo restart.

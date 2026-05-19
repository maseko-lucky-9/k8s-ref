# Vault prod-mode migration runbook (M3, ADR-0005)

> **What this does:** flips the demo Vault from dev-mode (`inmem`, root token `root`, auto-unsealed) to prod-shape (Raft storage + PVC, Shamir 1-of-1 unseal, init keys stored in K8s Secret `vault-init-keys`).
>
> **Blast radius:** ESO `ClusterSecretStore` flips to `InvalidProviderConfig` for ~1–2 minutes between teardown and the bootstrap Job re-running. Already-synced K8s Secrets (e.g., `tenant-config` in `k8s-ref-demo`) continue to serve their last value until ESO reconciles again. tenant-a and tenant-b pods see no interruption because podinfo loaded env at start.
>
> **Data loss:** YES — dev-mode's `inmem` storage is wiped on pod termination. The bootstrap Job re-seeds the same KV path (`secret/eso-source-config`) with the same key set; consumers see eventual consistency within one ESO refresh cycle (default 1h, force-refresh annotation cuts to seconds).
>
> **Reversibility:** Tier 1 — flip the chart values back; ArgoCD re-syncs to dev-mode. Tier 2 — `kubectl delete namespace vault-k8s-ref-demo`.

## Preflight

```bash
# Tailscale-direct kubeconfig (no SSH tunnel required)
export KUBECONFIG=$HOME/.kube/config-homelab-ts
kubectl get nodes                                        # READY
kubectl get app -n argocd | grep vault-k8s-ref           # current dev Vault state
kubectl get pvc -n vault-k8s-ref-demo                    # should be empty (dev = inmem)
kubectl get storageclass | grep microk8s-hostpath        # exists, default reclaim Delete OK for demo
```

## Step 1 — Land the chart changes via PR

1. Open the feature-branch PR (this runbook lives on that branch).
2. Review:
   - `argocd/apps/vault.yaml` — values flip dev → HA + Raft + PVC.
   - `argocd/apps/vault-init.yaml` — new ArgoCD App for the init+unseal Job.
   - `helm/charts/vault-init/` — new chart, ~80 LOC.
   - `helm/charts/vault-bootstrap/templates/job-config.yaml` + `values.yaml` — root token now read from Secret.
   - ADR-0005 (Proposed at PR time).
3. Squash-merge to `main`.

ArgoCD's auto-sync on `vault-k8s-ref-demo-bootstrap` and the bootstrap Job's `Sync` hook + `BeforeHookCreation` policy will pick up the new flow. The `vault-k8s-ref-demo` Application has `automated: { prune: false, selfHeal: false }` — needs a manual sync to apply the Vault chart change.

## Step 2 — Trigger the Vault migration (controlled, post-merge)

```bash
export KUBECONFIG=$HOME/.kube/config-homelab-ts

# 2a. Tear down the dev Vault StatefulSet (and its pod). The PVC is empty
#     (inmem); no data to back up. Re-sync below recreates the StatefulSet
#     with the new HA+Raft+PVC spec from the merged values.
kubectl delete sts vault-k8s-ref-demo -n vault-k8s-ref-demo --ignore-not-found

# 2b. Trigger ArgoCD to apply the new Vault chart values.
kubectl annotate app vault-k8s-ref-demo -n argocd argocd.argoproj.io/refresh=hard --overwrite
# Manual sync (auto-sync is off on this App by design — Vault is the keystone).
# Use the ArgoCD UI's "Sync" button, or:
kubectl patch app vault-k8s-ref-demo -n argocd --type=merge \
  --subresource=operation \
  -p '{"operation":{"sync":{"prune":false}}}'

# 2c. Wait for the new StatefulSet to come up + the pod to be Running.
kubectl get pods -n vault-k8s-ref-demo -w
# Expected: vault-k8s-ref-demo-0 Running 0/1 (sealed; Vault HEALTH liveness fails until unsealed).
```

## Step 3 — Init + unseal (automated by vault-init chart)

The `vault-k8s-ref-demo-init` ArgoCD Application is sync-waved at 0 alongside the Vault chart. Its Job:
1. Polls Vault `/v1/sys/health` until reachable.
2. If uninitialised → POST `/v1/sys/init` with shares=1, threshold=1.
3. Writes the unseal key + root token to K8s Secret `vault-init-keys`.
4. If sealed → POST `/v1/sys/unseal` using the key from the Secret.
5. Idempotent on re-run (every ArgoCD sync re-triggers the hook).

Watch:

```bash
kubectl get jobs -n vault-k8s-ref-demo -w           # vault-init Job Complete
kubectl logs -n vault-k8s-ref-demo -l app.kubernetes.io/name=vault-init --tail=50
kubectl get secret vault-init-keys -n vault-k8s-ref-demo -o jsonpath='{.data}' | base64 -d 2>/dev/null
#   should contain `unseal-key` + `root-token` keys
kubectl exec -n vault-k8s-ref-demo vault-k8s-ref-demo-0 -- vault status
#   Initialized=true, Sealed=false, Storage Type=raft
```

## Step 4 — Re-run vault-bootstrap (writes kubernetes auth + KV seed)

The bootstrap Job is at sync-wave 1. It'll re-run on next sync (the `Sync` hook + `BeforeHookCreation` policy). Force it:

```bash
kubectl annotate app vault-k8s-ref-demo-bootstrap -n argocd argocd.argoproj.io/refresh=hard --overwrite
kubectl patch app vault-k8s-ref-demo-bootstrap -n argocd --type=merge \
  --subresource=operation \
  -p '{"operation":{"sync":{}}}'

# Watch the bootstrap Job
kubectl get jobs -n vault-k8s-ref-demo -w
kubectl logs -n vault-k8s-ref-demo -l app.kubernetes.io/name=vault-bootstrap --tail=80
```

The Job now reads `VAULT_TOKEN` from `vault-init-keys` (not the hardcoded "root"). Steps inside the Job:
1. Wait for Vault reachable.
2. `vault auth enable kubernetes` (idempotent).
3. `vault write auth/kubernetes/config` with the long-lived `token_reviewer_jwt` from the SA-token Secret (ADR-0004 § Follow-up — unchanged).
4. `vault policy write k8s-ref-demo-read ...` (read KV path).
5. `vault write auth/kubernetes/role/k8s-ref-demo ...` bind to `eso-reader@k8s-ref-demo` SA.
6. `vault kv put secret/eso-source-config ...` re-seed the demo data.

## Step 5 — Verify ESO reconnects

```bash
# ClusterSecretStore must return to Valid
kubectl get clustersecretstore k8s-ref-demo-vault-store
# Force re-poll
kubectl annotate clustersecretstore k8s-ref-demo-vault-store force-sync=$(date +%s) --overwrite

# ExternalSecret resync
kubectl get externalsecret -n k8s-ref-demo
# tenant-config should report SecretSynced

# Full smoke check
./scripts/verify-eso-vault-migration.sh
# Expected: 6/6 PASS (script is reused — no prod-vs-dev branching)
```

## Step 6 — Capture P11 evidence + promote ADR-0005

```bash
cat > docs/portfolio-item-assets/p11-vault-prod-mode-evidence.txt <<EOF
...vault status (Initialized=true, Sealed=false, Storage Type=raft)
...kubectl get pvc -n vault-k8s-ref-demo (10Gi RWO Bound)
...kubectl exec ... vault operator raft list-peers (1 voter)
...ClusterSecretStore Valid + ExternalSecret SecretSynced
EOF
```

Then edit `docs/decisions/0005-vault-prod-mode-and-shamir-unseal-for-demo.md` Status → Accepted + add a "Consequences confirmed" paragraph referencing the verify run.

## Rollback paths

### Tier 1 — flip back to dev-mode

Revert the values change in `argocd/apps/vault.yaml`:

```yaml
server:
  dev: { enabled: true, devRootToken: "root" }
  ha: { enabled: false }
  dataStorage: { enabled: false }
```

Commit + PR + merge → ArgoCD reconciles. `vault-init-keys` Secret stays (harmless; bootstrap Job will read `root-token=<old root>` which dev-mode also accepts). PVC stays bound; manual `kubectl delete pvc data-vault-k8s-ref-demo-0` if you want a fully clean slate.

### Tier 2 — nuke the namespace

```bash
kubectl delete namespace vault-k8s-ref-demo
# Re-apply the Applications: vault.yaml + vault-init.yaml + vault-bootstrap.yaml
# Production Vault at namespace `vault` is untouched.
```

## Failure modes (and how to recover)

| Symptom | Likely cause | Fix |
|---|---|---|
| `vault-init` Job pod stuck `ImagePullBackOff` on `hashicorp/vault:1.19.0` | Docker Hub rate-limit / DNS hiccup | Wait, or pre-pull on the node, or pin a different tag in `helm/charts/vault-init/values.yaml` |
| Init succeeds, unseal returns 400 "key not in base64" | `unseal-key` in Secret got corrupted (manual edit) | `kubectl delete secret vault-init-keys -n vault-k8s-ref-demo` + `kubectl delete pvc data-vault-k8s-ref-demo-0` + re-sync (full re-init) |
| Bootstrap Job logs `permission denied` writing auth/kubernetes/config | Root token in Secret is stale (init re-ran without bootstrap re-running) | `kubectl annotate app vault-k8s-ref-demo-bootstrap -n argocd argocd.argoproj.io/refresh=hard --overwrite` + manual sync |
| ESO CSS stays `InvalidProviderConfig` | TokenReview JWT is now from a different SA UID after init churned things | `kubectl rollout restart deploy/external-secrets -n external-secrets` |
| Pod restart leaves Vault Sealed and stays sealed | `vault-init` Job's hook didn't re-run after pod restart | Manual sync the `vault-k8s-ref-demo-init` Application — Job re-creates and unseals from the existing Secret |

## What this does NOT do (deferred)

- **AWS KMS auto-unseal.** EKS recipe target; opens ADR-0007 when that lands.
- **3-replica Raft quorum.** Single-node MicroK8s; flip when cluster grows.
- **Audit log to PVC.** `auditStorage.enabled=true` in `argocd/apps/vault.yaml`; turn on once the demo proves stable.
- **Backup of unseal key off-cluster.** ADR-0005 § Open questions.

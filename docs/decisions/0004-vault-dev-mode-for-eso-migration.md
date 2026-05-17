# 4. Vault dev-mode for the ESO migration demo (M2)

Date: 2026-05-17

## Status

Proposed

## Context

ADR-0003 committed to demonstrating that the `k8s-ref-demo` `ExternalSecret`
spec is identical regardless of secret backend — that the migration from an
in-cluster Kubernetes `ClusterSecretStore` to a Vault-backed one changes
*only* the `ClusterSecretStore` resource. M1 closed with the kubernetes
provider live and the demo workload pulling secrets from a source Secret in
the same namespace.

M2's job is to land the actual migration: deploy Vault, wire it to ESO,
flip the backend without touching the `ExternalSecret`, and prove the
rotation flow end-to-end. The migration must be done in a way that:

1. Doesn't put the existing demo at risk while the new backend is being
   stood up.
2. Stays inside the project's constraint of no paid external services and
   no synthetic-data exfiltration.
3. Stays bounded in operational complexity — this is a portfolio demo, not
   a production Vault deployment.
4. Documents the production-swap path clearly so a reviewer can see what
   would change for a real Vault rollout.

The Vault deployment posture is the central choice. Three realistic
options exist for an in-cluster Vault used purely to demo the ESO swap.

## Options considered

| Posture | Initialization | Storage | Operational complexity | Production realism |
|---|---|---|---|---|
| **Dev mode** (`server.dev.enabled=true`) | Auto-unsealed, in-memory, fixed root token | ephemeral (pod restart = data loss) | Very low — single pod, no init ceremony | Low — diverges from production unseal flow |
| **Standalone with file storage** | Manual init + unseal on every pod restart | persistent volume on the node | Medium — unseal key/token management, restart pain | Medium — same Vault binary, different unseal flow than HA |
| **HA with integrated Raft** | Manual init, auto-unseal via cloud KMS (or manual) | persistent volume per replica | High — 3 pods, leader election, peer-set membership, KMS dependency | High — production-shaped |

## Decision

**Vault dev mode** (`server.dev.enabled=true`) with a fixed root token,
deployed as ArgoCD Application `vault` (Helm chart
`hashicorp/vault@0.30.0`). A second Application `vault-bootstrap` runs a
one-shot Job in sync wave 1 that enables Kubernetes auth, writes the
read-only policy on the demo path, binds the role to the existing
`eso-reader` ServiceAccount, and seeds the KV-v2 secret.

The `ClusterSecretStore` migration is gated behind a single Helm value
`eso.useVault` (default `false`). When set to `true`:

- A new `k8s-ref-demo-vault-store` `ClusterSecretStore` (Vault provider)
  is rendered.
- The existing kubernetes-provider store stops rendering.
- The `ExternalSecret`'s `secretStoreRef.name` flips to the Vault store.
- Nothing else in the chart changes.

The rotation demo flips a key in Vault (`vault kv put`) and confirms the
synced `tenant-config` Secret picks up the new value via ESO's refresh
cycle (annotation-forced for the demo).

## Why dev mode for this demo

- **The decision under test is the *ESO swap*, not the Vault deployment.**
  Standalone or HA Vault would add unseal ceremony complexity that
  distracts from what the migration actually demonstrates.
- **Reviewers can reproduce.** A fresh `kubectl apply -f argocd/apps/vault.yaml`
  yields a working Vault in seconds with no operator intervention.
- **Failure recovery is trivial.** Pod restart → bootstrap Job re-runs
  (idempotent) → fresh seed values. No locked-out state.
- **The production swap path is explicit.** Both this ADR and ADR-0003
  document exactly which fields change for HA-with-integrated-Raft
  (unseal config, storage block, replicas, auto-unseal) — same chart,
  different values.

## Consequences

### Positive
- ESO + Vault wiring proven end-to-end (auth method, policy, role,
  refresh, target Secret update) without taking the demo out of the
  hands of a one-laptop reviewer.
- ADR-0003's claim that `ExternalSecret` spec is invariant under backend
  swap is now mechanically verifiable.
- Cluster-side migration is fully reversible: `helm upgrade
  --set eso.useVault=false` reverts to the kubernetes provider in one
  reconcile.

### Negative
- Dev-mode Vault is **not** suitable for any non-demo workload. Repo
  README + case study must state this explicitly to avoid setting
  reviewer expectations wrong.
- Bootstrap Job stores the dev root token in the Helm values for
  simplicity; in a production rollout the equivalent would be an
  auto-unseal flow with KMS, never a static token.
- Single-replica, ephemeral storage — restarting the Vault pod loses all
  seeded data until the bootstrap Job re-runs. Mitigated by the Job's
  idempotency + ArgoCD's Sync hook re-running on every reconcile.

### Neutral
- Adds two new ArgoCD Applications (`vault`, `vault-bootstrap`) and one
  new in-repo Helm chart (`helm/charts/vault-bootstrap`). All scoped to
  the `vault` namespace.
- `eso.useVault` flag stays in the chart as a permanent migration toggle
  — useful for the ADR-0003 claim demonstration in future
  walkthroughs and for the case study.

## Production migration path (for the case study)

The chart's Vault block already names the production knobs:

- `eso.vault.server` → real Vault address (LB, ingress, or
  per-cluster service URL).
- `eso.vault.kvMount` / `kvVersion` → match the production KV mount
  layout.
- `eso.vault.role` → role bound to the appropriate workload SA in
  Vault.

A production migration replaces the `vault` Application with an HA
Vault chart and removes the `vault-bootstrap` Application — the
ExternalSecret + ClusterSecretStore-vault resources stay byte-identical.

## Implementation summary

Files added/changed (commit landing this ADR):

| File | Change |
|---|---|
| `argocd/apps/vault.yaml` | New — hashicorp/vault Application, dev mode, wave 0 |
| `argocd/apps/vault-bootstrap.yaml` | New — vault-bootstrap Application, wave 1 |
| `helm/charts/vault-bootstrap/` | New — Chart.yaml, values.yaml, Job + SA + RBAC |
| `helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store-vault.yaml` | New — Vault ClusterSecretStore (gated on `useVault`) |
| `helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store.yaml` | Edit — gate render off when `useVault=true` |
| `helm/charts/k8s-ref-demo/templates/eso/external-secret.yaml` | Edit — `secretStoreRef.name` switches on `useVault` |
| `helm/charts/k8s-ref-demo/values.yaml` | Edit — add `eso.useVault` + `eso.vault.*` |
| `helm/charts/k8s-ref-demo/values.schema.json` | Edit — extend schema |

## Operational runbook (apply sequence)

1. Commit + push to `main`.
2. Apply Application CRs:
   ```
   kubectl apply -f argocd/apps/vault.yaml
   kubectl apply -f argocd/apps/vault-bootstrap.yaml
   ```
3. Wait for Vault Application `Synced + Healthy` and bootstrap Job
   `Complete`.
4. Flip the feature flag:
   ```
   # In argocd/apps/k8s-ref-demo.yaml or via Helm value override, set:
   #   eso.useVault: true
   # Commit + push. ArgoCD reconciles k8s-ref-demo.
   ```
5. Verify:
   ```
   kubectl get clustersecretstore
   kubectl get externalsecret -n k8s-ref-demo
   kubectl get secret -n k8s-ref-demo tenant-config -o jsonpath='{.data.app-env}' | base64 -d
   ```
6. Rotation demo:
   ```
   kubectl exec -n vault vault-0 -- vault kv put secret/eso-source-config \
     app-env=demo-vault-rotated feature-flags='...' log-level=debug
   kubectl annotate externalsecret -n k8s-ref-demo tenant-config \
     force-sync=$(date +%s) --overwrite
   kubectl get secret -n k8s-ref-demo tenant-config -o jsonpath='{.data.app-env}' | base64 -d
   ```
7. Cleanup commit: delete
   `helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store.yaml`
   once the Vault-backed flow is proven.

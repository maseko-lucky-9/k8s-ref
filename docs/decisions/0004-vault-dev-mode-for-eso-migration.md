# 4. Vault dev-mode for the ESO migration demo (M2)

Date: 2026-05-17 · Revised: 2026-05-18 (namespace-isolation refactor) · Accepted: 2026-05-18

## Status

**Accepted** (2026-05-18) — Phase 2c verify-eso-vault-migration.sh returned 6/6 PASS. Rotation roundtrip: wrote new value to demo Vault → ExternalSecret picked it up → materialised K8s Secret updated in 1×2s polls. Migration functionally complete on the homelab cluster.

## Consequences confirmed (2026-05-18 apply)

- ESO → Vault wiring works end-to-end. `kubectl exec -n vault-k8s-ref-demo vault-k8s-ref-demo-0 -- vault kv put …` propagated through to the `tenant-config` K8s Secret in `k8s-ref-demo` within the first ESO refresh cycle (annotation-forced).
- Namespace isolation held: production Vault at namespace `vault` was never touched. The 12 production ExternalSecrets across `affiliate-yt`, `n8n-live`, `observability`, `prod` remained `SecretSynced` throughout (where they were already synced — the 3 `SecretSyncedError`s in `affiliate-yt` and `n8n-live/reelsmith-youtube` predate this work).
- Helm release name pinned to ArgoCD App name (`vault-k8s-ref-demo`) — discovered mid-apply that pinning to `vault` collided with production's `vault-server-binding` ClusterRoleBinding. Fixed via templated service-DNS in the bootstrap chart (commit `3a583fc`). This refinement strengthens the namespace-isolation guarantee — every chart-rendered resource now carries the App-name prefix, including cluster-scoped ones.
- Two-tier rollback verified workable but not exercised: namespace-scoped resources + project-scoped ClusterRoleBinding name mean `kubectl delete namespace vault-k8s-ref-demo` cleanly removes everything without touching production. Force-delete + finalizer-strip required when ArgoCD's hook-finalizer on the bootstrap Job hung the namespace termination — captured in `docs/runbooks/m2-apply.md` as Tier 2 recovery.

## Follow-up — `token_reviewer_jwt` expiry (caught post-apply)

~4 hours after the verify passed, the `ClusterSecretStore` flipped to `InvalidProviderConfig` with Vault returning `403 permission denied` on every `auth/kubernetes/login`. Root cause: the bootstrap Job's first version used the pod's *projected* SA token (`/var/run/secrets/kubernetes.io/serviceaccount/token`) for Vault's `token_reviewer_jwt`. The kubelet rotates projected tokens on a ~1h cadence — the token Vault had stored became invalid, so every TokenReview Vault issued to the apiserver was rejected, and Vault rejected the inbound ESO login in turn.

**Fix landed in the chart:** a long-lived `Secret` of type `kubernetes.io/service-account-token` (auto-populated by K8s with a non-expiring token for the bootstrap SA) is now mounted into the Job at `/var/run/vault-bootstrap-token`, and `token_reviewer_jwt` is read from there. Verified live: re-bootstrapped with the durable token, `ClusterSecretStore` flipped to `Valid` within seconds.

This is the canonical Vault-K8s-auth bootstrap pattern; the projected-token shortcut was a real gap, not a stylistic choice. Documented here rather than as a separate ADR because it doesn't change the M2 decision — it makes the original decision durable.

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
deployed as ArgoCD Application `vault-k8s-ref-demo` (Helm chart
`hashicorp/vault@0.30.0`) into namespace `vault-k8s-ref-demo`. A second
Application `vault-k8s-ref-demo-bootstrap` runs a one-shot Job in sync
wave 1 that enables Kubernetes auth, writes the read-only policy on the
demo path, binds the role to the existing `eso-reader` ServiceAccount,
and seeds the KV-v2 secret.

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
- Adds two new ArgoCD Applications (`vault-k8s-ref-demo`,
  `vault-k8s-ref-demo-bootstrap`) and one new in-repo Helm chart
  (`helm/charts/vault-bootstrap`). All scoped to the
  `vault-k8s-ref-demo` namespace (see § Namespace isolation).
- `eso.useVault` flag stays in the chart as a permanent migration toggle
  — useful for the ADR-0003 claim demonstration in future
  walkthroughs and for the case study.

## Namespace isolation

Discovered 2026-05-18 during the Phase 2.0 preflight: the homelab cluster
already runs a **production Vault** at namespace `vault` (deployed
2026-04-08, single-replica chart `hashicorp/vault@0.32.0` with HA-style
values from a separate `HashiCorp-Vault` repo). That Vault is referenced
by **12 `ExternalSecret`s** across `affiliate-yt`, `n8n-live`,
`observability`, and `prod` namespaces via a pre-existing
`vault-backend` `ClusterSecretStore`.

Applying the original M2 manifests as drafted — Application name
`vault`, destination namespace `vault` — would have:

1. Overwritten the production ArgoCD Application spec (same name).
2. Re-deployed dev-mode Vault (in-memory, root-token, no persistence)
   into the same namespace, **destroying all production KV data** and
   breaking 12 downstream consumers.
3. Disabled the `vault-agent-injector` (running 63 days), severing any
   injection-based consumers.

Mitigation: every M2 resource is renamed and rescoped so the demo
cannot collide with production state:

| Resource | Production state (untouched) | M2 demo |
|---|---|---|
| ArgoCD Application | `vault` (multi-source, `hashicorp/vault@0.32.0`) | `vault-k8s-ref-demo` (single-source, `0.30.0` dev) |
| Bootstrap Application | n/a | `vault-k8s-ref-demo-bootstrap` |
| Namespace | `vault` | `vault-k8s-ref-demo` (CreateNamespace=true) |
| Vault service DNS | `vault.vault.svc.cluster.local:8200` | `vault.vault-k8s-ref-demo.svc.cluster.local:8200` |
| ClusterRoleBinding (cluster-scoped) | n/a | `vault-k8s-ref-demo-bootstrap-token-reviewer` (project-scoped name) |
| `ClusterSecretStore` (cluster-scoped) | `vault-backend` (in use by 12 ES) | `k8s-ref-demo-vault-store` (project-scoped name) |

Rollback (per `docs/runbooks/m2-apply.md` Tier 2) safely deletes the
entire `vault-k8s-ref-demo` namespace without touching production —
verified by the namespace-scoped destination and the project-scoped
ClusterRoleBinding name. The two `ClusterSecretStore`s are
cluster-scoped resources but use disjoint names so they coexist
without collision.

This refactor was driven by adversarial review against live cluster
state, not theoretical risk. The original manifests (greenfield
assumption) were unsafe for this homelab.

## Production migration path (for the case study)

The chart's Vault block already names the production knobs:

- `eso.vault.server` → real Vault address (LB, ingress, or
  per-cluster service URL).
- `eso.vault.kvMount` / `kvVersion` → match the production KV mount
  layout.
- `eso.vault.role` → role bound to the appropriate workload SA in
  Vault.

A production migration replaces the `vault-k8s-ref-demo` Application
with an HA Vault chart (or repoints `eso.vault.server` at the existing
production `vault.vault.svc.cluster.local:8200`) and removes the
`vault-k8s-ref-demo-bootstrap` Application — the ExternalSecret +
ClusterSecretStore-vault resources stay byte-identical.

## Implementation summary

Files added/changed (commit landing this ADR):

| File | Change |
|---|---|
| `argocd/apps/vault.yaml` | New — `vault-k8s-ref-demo` Application, dev mode, wave 0, namespace `vault-k8s-ref-demo` |
| `argocd/apps/vault-bootstrap.yaml` | New — `vault-k8s-ref-demo-bootstrap` Application, wave 1, namespace `vault-k8s-ref-demo` |
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
   kubectl exec -n vault-k8s-ref-demo vault-0 -- vault kv put secret/eso-source-config \
     app-env=demo-vault-rotated feature-flags='...' log-level=debug
   kubectl annotate externalsecret -n k8s-ref-demo tenant-config \
     force-sync=$(date +%s) --overwrite
   kubectl get secret -n k8s-ref-demo tenant-config -o jsonpath='{.data.app-env}' | base64 -d
   ```
7. Cleanup commit: delete
   `helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store.yaml`
   once the Vault-backed flow is proven.

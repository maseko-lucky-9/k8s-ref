# 5. Vault prod-mode (Raft + Shamir) for the demo

Date: 2026-05-18

## Status

**Proposed** — promote to **Accepted** after a clean migration from the dev-mode demo Vault to a prod-shaped (HA chart + Raft storage + Shamir unseal) demo Vault on the homelab cluster, with ESO `ClusterSecretStore` returning to `Valid` and the `tenant-config` `ExternalSecret` resyncing successfully.

## Context

ADR-0004 explicitly scoped the M2 demo Vault to **dev-mode** (`server.dev.enabled=true`, `inmem` storage, root token `root`, no init/unseal flow, no persistence) to bound migration complexity for the ESO swap. The decision was always to revisit prod-mode after M2 had run stably for a while.

M2 has now been stable for ~4 hours of live traffic (PR #3 merged earlier today + canary cycles via the M3 Argo Rollouts work). Time to take the next architectural step: stand the demo Vault up on a prod-shape config that survives pod restarts, persists KV data, and demonstrates the canonical init + unseal flow.

The two real gaps the dev-mode Vault leaves on the table:

1. **State is ephemeral.** Every pod restart wipes the KV store, the auth methods, the policies, the roles. The 4-hour-post-verify SA-token-expiry bug from M2 (now fixed via ADR-0004 § Follow-up) wasn't even the worst case — a node reboot would have been catastrophic. Prod-shape needs Raft + a PVC.
2. **No init/unseal demonstration.** The root token "root" works because dev mode auto-unseals with a hardcoded key. A real Vault is initialised once (`vault operator init`) to produce Shamir key-shares + a root token, and **must be unsealed on every pod start** before it serves any request. The portfolio story is hollow without this loop visible.

What this ADR does NOT do:
- It does NOT pull in AWS KMS auto-unseal (cost + no AWS account active for the homelab).
- It does NOT use Vault transit auto-unseal against the production homelab Vault (ADR-0004 § Namespace isolation: demo Vault must not depend on production Vault).
- It does NOT introduce a service mesh, Cloud HSM, or any paid SaaS.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Stay on dev-mode forever** | Zero migration cost. Works for the screenshot bundle. | Dishonest portfolio claim ("we run prod-shape Vault"). State ephemeral. No init/unseal demonstration. Already chosen as M2's bounded scope; this ADR's whole point is to retire it. |
| **B. HA chart + Raft + Shamir (manual unseal, key stored in K8s Secret)** | Greenfield-pragmatic. Real Raft persistence. Real init/unseal loop. Survives pod restarts via an init-container that reads the unseal key from a Secret. Honest trade-off documented (key-at-rest in K8s etcd is weaker than KMS but adequate for homelab demo). | Unseal key sits in an etcd-encrypted K8s Secret + RBAC-gated; not as strong as Cloud KMS. Single-key Shamir (1-of-1) is the simplest path; multi-share Shamir adds operator complexity without changing security posture for a single-operator homelab. |
| **C. HA chart + Raft + AWS KMS auto-unseal** | Production-grade. No manual unseal. Survives any restart. | Paid (KMS billable per use). No AWS account active for the homelab. Document as the EKS-recipe target instead. |
| **D. HA chart + Raft + Vault transit auto-unseal** | Cleanest auto-unseal without cloud KMS. | Requires a *second* Vault (the unsealer) — and per ADR-0004 the demo Vault must not depend on the production homelab Vault. Standing up a third Vault just to unseal the second creates a circular bootstrap. |

## Decision

**Option B — HA chart + Raft single-node + Shamir 1-of-1 unseal, key stored in a K8s Secret, init+unseal automated via a new `vault-init` chart (one-shot Job).**

Specifically:
- `argocd/apps/vault.yaml` flips: `server.dev.enabled=false`, `server.ha.enabled=true`, `server.ha.raft.enabled=true`, `server.dataStorage.enabled=true` with `microk8s-hostpath` storage class. 1 replica (single-node MicroK8s — Raft works fine as single-node quorum; 3-replica HA is a config knob, not a code knob).
- New chart `helm/charts/vault-init` deploys a Job that:
  1. Polls Vault until reachable (max 30 × 2s).
  2. If Vault is uninitialised: runs `vault operator init -key-shares=1 -key-threshold=1` and stores the resulting unseal key + root token in a K8s Secret `vault-init-keys` in `vault-k8s-ref-demo` namespace.
  3. If Vault is sealed: reads the Secret + runs `vault operator unseal <key>`.
  4. Re-runs idempotently on every ArgoCD sync (Sync hook) — safe because both branches are guarded by the current Vault state.
- The existing `vault-bootstrap` chart no longer hardcodes `VAULT_TOKEN: "root"`. It reads the root token from the `vault-init-keys` Secret. This decouples bootstrap from dev-mode and works for both Shamir-initialised and future KMS-unsealed Vaults.
- The existing **long-lived `kubernetes.io/service-account-token` Secret** (ADR-0004 § Follow-up) for `token_reviewer_jwt` carries over unchanged — that fix is orthogonal to the dev → prod migration.

## Why this shape

- **Single-replica Raft instead of 3-replica HA.** This is a single-node MicroK8s homelab. 3 Raft replicas on one node consume 3× the disk + RAM + CPU for zero availability gain (they all die together when the node dies). 1 replica with persistence demonstrates the Raft *storage* property (state survives restarts) without the *replication* theatre. The chart values toggle between 1 and 3 with a single number change — the cloud-recipe `values-eks.yaml` (future) sets 3.
- **Shamir 1-of-1.** Multi-share Shamir is the right call when multiple humans hold key-shares. For a single-operator homelab demo, 5-of-3 or 5-of-2 just makes the runbook longer without changing the security boundary. The trade-off is the same: lose the Secret, lose Vault.
- **Unseal key in K8s Secret.** Not KMS-grade. Honest in the README + ADR. The portfolio story is "I chose Secret-storage for homelab and KMS for EKS, here's the ADR-0005 documenting both". That's a stronger signal than pretending homelab can do KMS.
- **One-shot Job for init, init-container for unseal.** The init-container pattern guarantees the unseal step runs before Vault accepts traffic, on every pod start. This is the canonical pattern for self-managed Vault on K8s without an external auto-unseal provider.

## Consequences

**Good**:
- Real persistence. KV data, auth methods, policies, roles all survive pod restarts.
- Real init/unseal loop. Portfolio shows the actual production bootstrap procedure.
- No paid services. Works on the homelab as-is.
- Chart values switchable to AWS KMS for the EKS recipe (`server.ha.raft.config` accepts a `seal "awskms"` stanza).
- The `vault-bootstrap` chart becomes generic — no longer dev-mode-coupled.

**Costs**:
- Brief data loss on migration: dev-mode `inmem` state cannot be exported to Raft directly. The bootstrap Job re-seeds the same KV path, so consumer-visible state is reconstructed; no Secret consumer loses its rendered Secret because ESO's reconcile loop refreshes from the new Vault within minutes.
- Unseal-key-in-K8s-Secret is a real trade-off. Documented honestly in this ADR + the runbook.
- One more chart (`vault-init`) to maintain. Small (~80 LOC), self-contained, replay-safe.
- 10 GiB persistent volume claim against `microk8s-hostpath` on the homelab node. Same storage class production Vault uses.

**Reversible**:
- Tier 1: flip `server.ha.enabled=false`, `server.dev.enabled=true` in values.yaml, commit, ArgoCD sync. Demo reverts to dev-mode; `vault-init` Job's init-if-needed branch becomes a no-op (Vault auto-initialises in dev mode); the unseal-if-sealed branch becomes a no-op.
- Tier 2: `kubectl delete namespace vault-k8s-ref-demo` — pulls everything (Vault + init + bootstrap + Secrets + PVC). Production Vault in namespace `vault` untouched.

## Rollback plan during the migration

If any of the following fails, abort to dev-mode (Tier 1 above) and document the gap as a follow-up ticket:

- Raft init fails for any reason after 3 retries.
- Unseal-after-restart loop fails to keep Vault unsealed.
- ESO `ClusterSecretStore` doesn't return to `Valid` within 5 minutes of the bootstrap Job completing.
- `verify-eso-vault-migration.sh` returns non-6/6 after migration.

## Open questions for follow-up ADRs

- **Move to KMS auto-unseal.** The EKS recipe (`terraform/`) should default to AWS KMS auto-unseal. Add an ADR-0007 when that recipe goes live.
- **Backup of unseal key.** Today the unseal key only exists in the K8s Secret `vault-init-keys` and on the homelab host's etcd snapshot. Adding a backup to an external password manager (1Password, Bitwarden) is operationally sensible but outside the demo's automation surface.
- **3-replica Raft.** When the cluster gets a second node, flip `server.ha.replicas=3` and watch Raft establish quorum. Worth its own ADR because it changes the unseal automation (each replica needs unsealing on start; the init-container pattern still handles this).

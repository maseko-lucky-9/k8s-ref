# 3. Secret management: ESO vs Sealed Secrets vs SOPS vs Vault

Date: 2026-05-06

## Status

Accepted

## Context

The `k8s-ref-demo` workload requires a runtime secret (`tenant-config`) injected as environment variables into the podinfo Deployments. Four production-realistic options exist for managing this secret in a GitOps workflow without committing plaintext to the repo:

- **Sealed Secrets** (Bitnami) — encrypt secrets client-side; SealedSecret CR lives in Git; controller decrypts at apply-time
- **SOPS + age/GPG** — encrypt secret files with `sops`; decrypt at apply-time via a Kustomize plugin or manual pre-processing
- **External Secrets Operator + Kubernetes SecretStore** — ESO controller fetches the secret from a live Kubernetes Secret in a source namespace; the ExternalSecret CRD lives in Git
- **External Secrets Operator + HashiCorp Vault** — same ESO controller; SecretStore backend is a Vault instance with per-path policies and audit trail

The project constraint is that the demo must run on a single homelab node with no paid external services, yet the architecture must be production-swappable to an enterprise secret backend without re-engineering the workload.

## Decision

**ESO with an in-cluster Kubernetes SecretStore** for the demo cluster. The `ClusterSecretStore` reads from a single `eso-source-config` Secret in a dedicated namespace. The `ExternalSecret` spec is identical to what production Vault/AWS Secrets Manager wiring would use — only the `ClusterSecretStore` backend definition changes in a migration.

The Vault swap is explicitly scoped to **M2** and requires only:
1. Deploy Vault (or point at an existing enterprise Vault).
2. Update `ClusterSecretStore.spec.provider` from `kubernetes` to `vault`.
3. Create a Vault auth method + policy. No ExternalSecret changes.

## Options considered

| Solution | Blast radius | Rotation story | Operational complexity |
|---|---|---|---|
| Sealed Secrets | Cluster-scoped controller key; key compromise = re-seal all secrets | Manual `kubeseal` re-encrypt per change; no TTL enforcement | Low — one controller, one CLI (`kubeseal`) |
| SOPS + age | Per-file key; granular blast radius | Manual re-encrypt + commit every rotation | Medium — editor tooling, key distribution, Kustomize plugin dependency |
| ESO + K8s SecretStore (**this**) | Source-namespace blast radius; same-cluster secret store | ESO pulls on configurable refresh interval; rotation = update source Secret | Low — ESO controller + a plain Secret; no external infrastructure |
| ESO + Vault | Per-path Vault policies; cluster-external blast radius; full audit trail | Native Vault rotation engine / PKI; TTL-enforced leases | High — Vault HA, unseal ceremony, auth-method config, network policy |

## Trade-offs

**Why ESO + K8s SecretStore now:**
- Zero new infrastructure; runs fully in-cluster on the homelab node
- Demonstrates the ESO controller pattern (ClusterSecretStore CRD, ExternalSecret ownership, drift correction) which is identical to what a Vault-backed production deployment uses
- The production migration is a single `ClusterSecretStore` CRD change — a hiring manager reviewing the code can see that clearly
- Avoids the Sealed Secrets footgun: a cluster key rotation requires re-sealing every secret in the repo; ESO just needs the source Secret updated

**Why not Sealed Secrets:**
- Cluster key rotation is destructive to all sealed secrets simultaneously
- No path to a cloud secret backend — SealedSecrets always decrypt on-cluster; there is no "swap to Vault" story
- Less common in enterprise environments than ESO

**Why not SOPS:**
- No native Kubernetes reconcile loop — you need a Kustomize plugin or custom controller, adding fragility
- Key distribution across CI/CD pipelines adds operational overhead disproportionate to a demo project

**Why Vault is deferred to M2:**
- Vault HA on a single homelab node adds ~500MB RAM and unseal ceremony complexity
- The demo purpose is to prove the pattern, not to run production Vault; the ESO abstraction already proves the pattern
- M2 scope: deploy Vault in dev mode (or point at an existing enterprise instance), update the SecretStore, document the auth-method config

## Consequences

**Positive:**
- ESO controller + ExternalSecret ownership + drift correction demonstrated end-to-end
- Production swap path is documented and bounded
- No paid external service required for M1

**Negative:**
- The demo secret store is in-cluster — a compromised cluster means the secret store is also compromised. Acceptable for a demo; not for production.
- `docs/` and `README.md` must explicitly state "in-cluster K8s SecretStore for demo" to avoid misleading reviewers

**Neutral:**
- All future ADRs involving secrets should reference this decision for the chosen ESO baseline

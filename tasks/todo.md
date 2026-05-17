# k8s-ref — Resume Plan Tracker (2026-05-17)

Source plan: `/Users/ltmas/.claude/plans/let-resume-with-k8s-ref-stateless-moore.md`

## Slice 1 — M1 W2: P5/P6 capture
- [x] 1.0 Pre-check: kubeconfig + LAN + DNS + CA trust
  - Tunnel via `svc-ai-agent` (per `99-hardened.conf` — `dev` user has `AllowTcpForwarding no`; only `svc-ai-agent` has `AllowTcpForwarding local`). Use SSH alias `homelab-tunnel`.
- [x] 1.1 ArgoCD CLI Synced+Healthy verification
  - `k8s-ref-demo` Synced+Healthy at revision `cb7d91e06a355266713e0a4cc8153b4f3a1c4b69` (matches git HEAD exactly).
- [~] 1.2 P5 capture — **CLI evidence done, UI screenshot blocked**
  - `docs/portfolio-item-assets/p5-argocd-cli-evidence.txt` committed.
  - UI screenshot blocked: `argocd-initial-admin-secret` returns a password but UI returns 401. Password rotated post-install, not reflected in K8s secret.
  - **To unblock**: run `./scripts/reset-ui-admin-passwords.sh --only argocd` (with SSH tunnel open + KUBECONFIG exported per script header), then capture UI.
- [~] 1.3 P6 capture — **CLI evidence done, UI screenshot blocked**
  - `docs/portfolio-item-assets/p6-grafana-cli-evidence.txt` committed — shows Prometheus scraping all 3 tenant pods `health=up`, live HTTP rate + memory metrics returning data.
  - UI screenshot blocked: `grafana-admin-credentials` secret password returns 401 against Grafana login. Same rotation pattern.
  - **To unblock**: run `./scripts/reset-ui-admin-passwords.sh --only grafana`, then capture UI.
- [x] 1.6 ADR-0003 invariance proof — `docs/portfolio-item-assets/adr-0003-invariance-proof.diff` shows the byte-level diff between `eso.useVault=false` and `eso.useVault=true` rendering. Out of 633 lines, ONLY the `ClusterSecretStore` provider block and the single field `ExternalSecret.spec.secretStoreRef.name` differ. This is the mechanical proof of ADR-0003's central claim and is portfolio-grade case-study material.
- [x] 1.4 Update portfolio docs + commit
- [ ] 1.5 Session note via `/vault-session-end` (deferred until full M1 close)

## Slice 2 — M1 W3: Cloudflare Tunnel
- [ ] 2.0 HARD PAUSE: confirm Cloudflare domain + API token availability before starting
- [ ] 2.1 Topology decision (ADR-next)
- [ ] 2.2 ArgoCD Application + ExternalSecret + Ingress route
- [ ] 2.3 Verify from cellular network
- [ ] 2.4 Commit

## Slice 3 — M1 W4: Case study + portfolio publish
- [ ] 3.1 Drop screenshots into case-study
- [ ] 3.2 Mirror entry to portfolio-website repo
- [ ] 3.3 HARD PAUSE: confirm before `wrangler deploy`
- [ ] 3.4 Commit + session log

## Slice 4 — M2: ESO Vault swap (cert-manager already deployed by homelab-infra repo)
- [x] 4.1 Code: new `argocd/apps/vault.yaml` Application (hashicorp/vault@0.30.0 dev mode, wave 0)
- [x] 4.1b Code: new `argocd/apps/vault-bootstrap.yaml` Application + in-repo chart `helm/charts/vault-bootstrap/` (idempotent Job, wave 1; enables k8s auth, writes policy, binds role to `eso-reader` SA, seeds `secret/eso-source-config`)
- [x] 4.2 Code: parallel `ClusterSecretStore` gated by Helm value `eso.useVault` — false renders existing kubernetes store, true renders new `k8s-ref-demo-vault-store`. ExternalSecret `secretStoreRef.name` switches automatically.
- [x] 4.2b Code: `helm/charts/k8s-ref-demo/values.yaml` + `values.schema.json` updated with `eso.useVault` + `eso.vault.*` block
- [x] 4.3 ADR-0004 (`docs/decisions/0004-vault-dev-mode-for-eso-migration.md`) — Proposed status; documents posture, options, decision, consequences, runbook
- [x] 4.4 Validation: `helm lint` passes both charts; `helm template` renders correctly for `useVault=false` and `useVault=true`
- [ ] **APPLY STEP (user must run interactively)** — code work is complete; cluster mutation is deferred so user owns the Vault deploy decision:
  ```
  export KUBECONFIG=~/.kube/config-homelab
  kubectl apply -f argocd/apps/vault.yaml
  kubectl apply -f argocd/apps/vault-bootstrap.yaml
  # Wait for both Synced+Healthy and the bootstrap Job to Complete
  kubectl get applications -n argocd vault vault-bootstrap -w
  kubectl get job -n vault vault-bootstrap-config -w
  ```
- [ ] Flip the feature flag: edit `helm/charts/k8s-ref-demo/values.yaml` → `eso.useVault: true`, commit + push, watch `k8s-ref-demo` Application reconcile.
- [ ] Verify rotation: `vault kv put secret/eso-source-config app-env=demo-rotated …` → `kubectl annotate externalsecret -n k8s-ref-demo tenant-config force-sync=$(date +%s) --overwrite` → check `kubectl get secret -n k8s-ref-demo tenant-config -o jsonpath='{.data.app-env}' \| base64 -d`.
- [ ] P8 screenshot: Vault UI (`http://127.0.0.1:8200` via port-forward, root token `root`) showing seeded data at `secret/eso-source-config`. Save to `docs/portfolio-item-assets/p8-vault-secrets.png`.
- [ ] Cleanup commit: delete `helm/charts/k8s-ref-demo/templates/eso/cluster-secret-store.yaml` once Vault flow is proven.
- [ ] Move ADR-0004 from Proposed → Accepted.

## Notable corrections vs original plan
- Asset directory: `docs/portfolio-item-assets/` (not `docs/portfolio/screenshots/`).
- ExternalSecret name: `tenant-config` (not `k8s-ref-demo`).
- ClusterSecretStore name: `k8s-ref-demo-store`.
- Tunnel user: `svc-ai-agent` via `homelab-tunnel` SSH alias.
- Grafana location: namespace `observability`, service `kube-prom-stack-grafana` port 80; secret `grafana-admin-credentials`.

# k8s-ref — Resume Plan Tracker (2026-05-17)

Source plan: `/Users/ltmas/.claude/plans/let-resume-with-k8s-ref-stateless-moore.md`

## Slice 1 — M1 W2: P5/P6 capture
- [x] 1.0 Pre-check: kubeconfig + LAN + DNS + CA trust
  - Tunnel via `svc-ai-agent` (per `99-hardened.conf` — `dev` user has `AllowTcpForwarding no`; only `svc-ai-agent` has `AllowTcpForwarding local`). Use SSH alias `homelab-tunnel`.
- [x] 1.1 ArgoCD CLI Synced+Healthy verification
  - `k8s-ref-demo` Synced+Healthy at revision `cb7d91e06a355266713e0a4cc8153b4f3a1c4b69` (matches git HEAD exactly).
- [~] 1.2 P5 capture — **CLI evidence done, UI screenshot blocked**
  - `docs/portfolio-item-assets/p5-argocd-cli-evidence.txt` committed.
  - UI screenshot blocked: `argocd-initial-admin-secret` returns `VBpeJvI7-C8An64u` but UI returns 401. Password rotated post-install, not reflected in K8s secret.
  - To unblock: reset ArgoCD admin password back to the secret value (`argocd admin initial-password -n argocd` documents the flow), or update the secret to match the current UI password.
- [~] 1.3 P6 capture — **CLI evidence done, UI screenshot blocked**
  - `docs/portfolio-item-assets/p6-grafana-cli-evidence.txt` committed — shows Prometheus scraping all 3 tenant pods `health=up`, live HTTP rate + memory metrics returning data.
  - UI screenshot blocked: `grafana-admin-credentials` secret password `?abretewR5*R+p` returns 401 against the Grafana login API. Same rotation-not-reflected-in-secret pattern.
  - To unblock: reset Grafana admin via `kubectl exec -n observability deploy/kube-prom-stack-grafana -- grafana-cli admin reset-admin-password <value-in-secret>`.
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
- [ ] 4.1 Deploy Vault dev-mode via new `argocd/apps/vault.yaml` Application
- [ ] 4.2 Parallel `ClusterSecretStore` pattern — add Vault-backed store alongside existing kubernetes-backed store
- [ ] 4.3 Flip ExternalSecret `secretStoreRef.name` (real name: `tenant-config`, target Secret: per ExternalSecret spec)
- [ ] 4.4 Rotation demo + screenshot P8 + ADR-next

## Notable corrections vs original plan
- Asset directory: `docs/portfolio-item-assets/` (not `docs/portfolio/screenshots/`).
- ExternalSecret name: `tenant-config` (not `k8s-ref-demo`).
- ClusterSecretStore name: `k8s-ref-demo-store`.
- Tunnel user: `svc-ai-agent` via `homelab-tunnel` SSH alias.
- Grafana location: namespace `observability`, service `kube-prom-stack-grafana` port 80; secret `grafana-admin-credentials`.

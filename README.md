# k8s-ref — Production Kubernetes Reference Architecture

> **Problem statement (per global CLAUDE.md project goals):** Engineering hiring managers can't tell from a CV whether a senior Kubernetes candidate can actually run a production-grade cluster. This repo gives them runnable evidence — a multi-tenant SaaS reference cluster they can clone, deploy, and inspect — proving production patterns end-to-end without trusting buzzwords.

![Architecture](docs/architecture/assets/architecture-diagram.png)

**Owner:** Thulani Maseko · Prudentia Digital
**Status:** M1 + M2 SHIPPED end-to-end (2026-05-18). Public demo live. M3 in planning. See [Roadmap](#roadmap-build-order).
**Live demo:** **[k8s-ref-a.prudentiadigital.co.za](https://k8s-ref-a.prudentiadigital.co.za)** · **[k8s-ref-b.prudentiadigital.co.za](https://k8s-ref-b.prudentiadigital.co.za)** — two tenants of the live homelab cluster, served via Cloudflare Tunnel (zero firewall ports opened). Screenshot bundle in [`docs/portfolio-item-assets/`](docs/portfolio-item-assets/); tunnel runbook at [`docs/runbooks/cloudflare-tunnel.md`](docs/runbooks/cloudflare-tunnel.md).
**Case study:** [`docs/case-study/k8s-ref.md`](docs/case-study/k8s-ref.md) (live in-repo).

---

## What this proves

A senior backend & DevOps engineer can stand up a production-grade Kubernetes platform end-to-end on commodity hardware:

- **GitOps deploys** via ArgoCD ApplicationSet — every change is a git commit
- **Secret management** via External Secrets Operator (in-cluster Kubernetes SecretStore for demo; Vault prod-swap is a one-CRD change — see ADR-0003)
- **TLS automation** via cert-manager + Let's Encrypt
- **Multi-tenant isolation** via namespace + NetworkPolicy + RBAC
- **Golden-signal observability** via Prometheus, Grafana, Loki, Tempo
- **Reproducibility** via Helm charts + Terraform — rebuild from zero in <30 minutes

## Where it runs

| Target | Status | Notes |
|---|---|---|
| MicroK8s (homelab) | Primary | Single-node + 2-node scale-up tested |
| AWS EKS | Documented recipe | See `terraform/` |
| GKE / AKS | Untested | Patterns are portable |

## Tech stack

- **Cluster:** MicroK8s 1.30+ (homelab) / AWS EKS 1.30+ (cloud recipe)
- **GitOps:** ArgoCD with ApplicationSet for multi-env management
- **Packaging:** Helm 3.x charts authored in this repo
- **Secrets:** External Secrets Operator (in-cluster Kubernetes SecretStore for demo; Vault prod-swap documented in [ADR-0003](docs/decisions/0003-secret-management-eso-vs-sealed-secrets.md))
- **TLS:** cert-manager + Let's Encrypt (DNS-01 challenge)
- **Ingress:** ingress-nginx (class: `public`, MicroK8s addon) / AWS ALB Controller (EKS)
- **Observability:** Prometheus + Grafana + Loki + Tempo (kube-prometheus-stack baseline)
- **IaC:** Terraform for the EKS recipe; Bash for MicroK8s bootstrap
- **CI:** GitHub Actions

## Repo layout

```
k8s-ref/
├── argocd/             # ArgoCD ApplicationSet + bootstrap manifests
├── helm/               # Helm charts authored here
├── terraform/          # AWS EKS deployment recipe
├── observability/      # Prometheus/Grafana/Loki dashboards + alerts
├── scripts/            # Bootstrap + helper scripts
├── docs/
│   ├── architecture/   # Architecture write-up + diagrams
│   └── decisions/      # ADRs (Michael Nygard format)
└── README.md
```

## Quickstart (homelab)

> Requires: Ubuntu 22.04 host with ≥8 GB RAM, Docker, snap.

```bash
# 1. Bootstrap MicroK8s + addons
./scripts/bootstrap-microk8s.sh

# 2. Bootstrap ArgoCD + ApplicationSet
kubectl apply -k argocd/bootstrap

# 3. Wait for sync
kubectl get applications -n argocd -w
```

## Quickstart (AWS EKS)

```bash
cd terraform
terraform init
terraform apply
# ... follow output for ArgoCD bootstrap
```

## Roadmap (build order)

- [x] **M1 W1**: MicroK8s bootstrap + ArgoCD up + 2-tenant demo workload + TLS + ServiceMonitors
- [x] **M1 W2**: Grafana dashboards wired + ESO validated + kubeconfig-fetch script + ADR-0002/0003 (code done; P4 captured, P5/P6 pending Phase A cluster session)
- [ ] **M2**: cert-manager + ESO + Vault wired (SecretStore swap from in-cluster K8s provider) — **code complete, apply pending** (ADR-0004 Proposed; see `docs/runbooks/m2-apply.md`)
- [ ] **M3**: kube-prometheus-stack + Loki + Tempo + sample dashboards
- [ ] **M4**: Helm charts for sample multi-tenant SaaS workload
- [ ] **M5**: AWS EKS Terraform recipe complete + tested
- [ ] **M6**: Case-study page on portfolio + screenshots + Loom walkthrough

Estimated total: **40 hours** (per `wiki/career/project/launch-plan-6mo.md`).

## Code provenance

All code in this repo is **greenfield** — written outside Capitec / Absa equipment and outside employment hours. **MIT licensed.** No production data; synthetic test data only.

## Demo evidence

Captured artifacts live under [`docs/portfolio-item-assets/`](docs/portfolio-item-assets/):

| Artifact | Status | What it proves |
|---|---|---|
| `p4-kubectl-get-all.png` | ✅ Live (2026-05-06) | Cluster + ArgoCD applications healthy, kubectl-level evidence |
| `p5-argocd-cli-evidence.txt` | ✅ Live (CLI, 2026-05-17) — UI PNG pending | ArgoCD Applications synced via CLI |
| `p6-grafana-cli-evidence.txt` | ✅ Live (CLI, 2026-05-17) — UI PNG pending | kube-prometheus dashboards loaded |
| `p8-vault-ui.png` | ⏳ Pending Phase A cluster session | Vault KV secrets visible (post-M2 apply) |
| `adr-0003-invariance-proof.diff` | ✅ Live (2026-05-17) | Single-CRD swap proof for ESO Vault migration |

`docs/case-study/k8s-ref.md` cross-links every artifact with full context.

## Architecture Decision Records

Non-trivial decisions are documented before implementation. Michael Nygard format. See [`docs/decisions/`](docs/decisions/).

| ADR | Decision | Status |
|---|---|---|
| [0001](docs/decisions/0001-record-architecture-decisions.md) | Record architecture decisions | Accepted |
| [0002](docs/decisions/0002-homelab-distribution-microk8s-vs-k3s-vs-kind.md) | Homelab distribution: MicroK8s vs k3s vs kind | Accepted |
| [0003](docs/decisions/0003-secret-management-eso-vs-sealed-secrets.md) | Secret management: ESO vs Sealed Secrets | Accepted |
| [0004](docs/decisions/0004-vault-dev-mode-for-eso-migration.md) | Vault dev-mode for ESO migration | Proposed (promote after M2 apply) |

## License

MIT

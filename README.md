# k8s-ref — Production Kubernetes Reference Architecture

> **Problem statement (per global CLAUDE.md project goals):** Engineering hiring managers can't tell from a CV whether a senior Kubernetes candidate can actually run a production-grade cluster. This repo gives them runnable evidence — a multi-tenant SaaS reference cluster they can clone, deploy, and inspect — proving production patterns end-to-end without trusting buzzwords.

**Owner:** Thulani Maseko · Prudentia Digital
**Status:** In progress (Project #1 of the freelance launch portfolio — see `wiki/career/project/portfolio-projects-shortlist.md` in the Obsidian vault)
**Live demo:** TBD (homelab Cloudflare Tunnel — pending project completion)
**Case study:** TBD (will live at `prudentiadigital.co.za/case-studies/k8s-ref-arch`)

---

## What this proves

A senior backend & DevOps engineer can stand up a production-grade Kubernetes platform end-to-end on commodity hardware:

- **GitOps deploys** via ArgoCD ApplicationSet — every change is a git commit
- **Secret management** via External Secrets Operator pulling from Vault
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
- **Secrets:** External Secrets Operator + HashiCorp Vault
- **TLS:** cert-manager + Let's Encrypt (DNS-01 challenge)
- **Ingress:** ingress-nginx (homelab) / AWS ALB Controller (EKS)
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

- [ ] **M1**: MicroK8s bootstrap + ArgoCD up + first sample app deployed
- [ ] **M2**: cert-manager + ESO + Vault wired
- [ ] **M3**: kube-prometheus-stack + Loki + Tempo + sample dashboards
- [ ] **M4**: Helm charts for sample multi-tenant SaaS workload
- [ ] **M5**: AWS EKS Terraform recipe complete + tested
- [ ] **M6**: Case-study page on portfolio + screenshots + Loom walkthrough

Estimated total: **40 hours** (per `wiki/career/project/launch-plan-6mo.md`).

## Code provenance

All code in this repo is **greenfield** — written outside Capitec / Absa equipment and outside employment hours. **MIT licensed.** No production data; synthetic test data only.

## License

MIT

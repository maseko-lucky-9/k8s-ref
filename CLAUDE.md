# CLAUDE.md — k8s-ref

> Minimal project instructions per global CLAUDE.md bootstrap rule.

## Purpose

Production-grade Kubernetes reference cluster — Project #1 of the Prudentia Digital freelance launch portfolio. Greenfield code only; all changes off-hours.

## Status (as of M1 W2, 2026-05-06)

- **M1 W1** ✅ ArgoCD Helm deploy, 2 tenants, TLS, ServiceMonitors — complete
- **M1 W2** 🔄 ADR-0002 Accepted, ADR-0003 written, README reconciled, kubeconfig-fetch + verify scripts added, observability docs cleaned — code complete; screenshots (P4/P5/P6) pending Phase A cluster session
- **ADRs:** 0001 (ADR practice), 0002 (MicroK8s — Accepted), 0003 (ESO secret management — Accepted)
- **Scripts:** `bootstrap-microk8s.sh` (existing), `fetch-kubeconfig.sh` (new), `verify-cluster.sh` (new)

## Tech stack

- MicroK8s (homelab) + AWS EKS (cloud recipe)
- ArgoCD GitOps · Helm 3.x · External Secrets Operator · cert-manager
- kube-prometheus-stack · Loki · Tempo
- Terraform (AWS) · Bash (homelab bootstrap)
- GitHub Actions

## Primary entry points

| Path | What it does |
|---|---|
| `scripts/bootstrap-microk8s.sh` | One-shot homelab bootstrap |
| `argocd/bootstrap/` | ArgoCD bootstrap kustomization |
| `argocd/apps/` | ApplicationSet declarations |
| `helm/<chart>/` | Authored Helm charts |
| `terraform/` | AWS EKS deployment recipe |
| `docs/decisions/` | ADRs (Michael Nygard format) |

## Build / test / deploy commands

- **Lint Helm:** `helm lint helm/<chart>`
- **Render Helm:** `helm template helm/<chart>`
- **Terraform plan:** `cd terraform && terraform plan`
- **Apply ArgoCD bootstrap:** `kubectl apply -k argocd/bootstrap`
- **Watch sync:** `kubectl get applications -n argocd -w`

## Constraints

- **Greenfield only.** No code lifted from prior employers (Capitec, Absa).
- **Synthetic data only.** No production secrets, no real customer data.
- **ADR before implementation** for any non-trivial decision (per global CLAUDE.md).
- **MIT licensed.** Public repo at `github.com/maseko-lucky-9/k8s-ref`.

## Out of scope (defer)

- Multi-cluster federation
- Service mesh (Istio/Linkerd) — keep complexity bounded for the demo
- Custom CRDs / operators

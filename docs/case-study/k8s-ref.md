# Case Study — Production Kubernetes Reference Architecture

> **Status:** Live on homelab (MicroK8s). Public exposure via Cloudflare Tunnel pending.
> **Repo:** https://github.com/maseko-lucky-9/k8s-ref

---

## Problem

Small-to-medium engineering teams adopting Kubernetes typically hit the same wall: they can get a cluster running, but the gap between "cluster up" and "production-grade, observable, secrets-safe, GitOps-driven" is 60–100 hours of undocumented work. There is no single reference they can fork, study, and adapt.

**This project is that reference.** Built on a real homelab (not mocked), open-sourced under MIT, and maintained as a living codebase.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      MicroK8s (single node)             │
│                                                         │
│  ┌──────────┐   GitOps    ┌────────────────────────┐   │
│  │  GitHub  │ ──────────► │       ArgoCD           │   │
│  │ k8s-ref  │             │  App-of-Apps pattern   │   │
│  └──────────┘             └───────────┬────────────┘   │
│                                       │ manages         │
│            ┌──────────────────────────┼───────────┐     │
│            │                          │           │     │
│    ┌───────▼──────┐     ┌─────────────▼─────┐    │     │
│    │  k8s-ref-demo│     │  observability    │    │     │
│    │  namespace   │     │  namespace        │    │     │
│    │              │     │                   │    │     │
│    │  ┌─────────┐ │     │ Prometheus        │    │     │
│    │  │tenant-a │ │◄────│ Loki             │    │     │
│    │  │(2 pods) │ │     │ Grafana           │    │     │
│    │  └─────────┘ │     │ Tempo             │    │     │
│    │  ┌─────────┐ │     └───────────────────┘    │     │
│    │  │tenant-b │ │                               │     │
│    │  │(1 pod)  │ │     ┌───────────────────┐    │     │
│    │  └─────────┘ │     │  external-secrets │    │     │
│    │              │     │  namespace        │    │     │
│    │  ExternalSecret◄───│ ClusterSecretStore│    │     │
│    │  tenant-config     │ (K8s provider)    │    │     │
│    └──────────────┘     └───────────────────┘    │     │
│                                                   │     │
│  ingress-nginx ◄── TLS (cert-manager homelab-ca)  │     │
│       │                                           │     │
└───────┼───────────────────────────────────────────┘     │
        │                                                  │
   Cloudflare Tunnel ──► k8s-ref-a.prudentiadigital.co.za
                    └──► k8s-ref-b.prudentiadigital.co.za
```

---

## Key Components

| Layer | Technology | Purpose |
|---|---|---|
| **Cluster** | MicroK8s 1.30 | Self-hosted single-node, snap-managed |
| **GitOps** | ArgoCD | Pull-based CD; all changes via Git |
| **Demo workload** | stefanprodan/podinfo 6.7 | Multi-tenant HTTP + /metrics endpoints |
| **Ingress** | ingress-nginx (class: public) | TLS termination, host-based routing |
| **TLS** | cert-manager + homelab-ca ClusterIssuer | Automated cert issuance per ingress |
| **Secrets** | External Secrets Operator v1 | Kubernetes provider; ownership + drift correction |
| **Metrics** | Prometheus + ServiceMonitors | Scraped from both tenants (all-namespace selector) |
| **Dashboards** | Grafana (sidecar auto-load) | ConfigMap-driven; GitOps-provisioned |
| **Logs** | Loki + Alloy | Cluster-wide log aggregation |
| **Public access** | Cloudflare Tunnel (cloudflared) | Zero-trust, no open firewall ports |

---

## What This Demonstrates

### 1. GitOps-Driven Delivery
Every resource — deployments, ingresses, certificates, ServiceMonitors, Grafana dashboards, ESO stores — is declared in Git and applied by ArgoCD. Nothing is `kubectl apply`-ed by hand in production.

### 2. Multi-Tenant Namespace Isolation
Two tenants (`tenant-a`, `tenant-b`) share the cluster but are logically isolated. Different replica counts, colour-coded UIs, independent ingress routes and TLS certificates. Extendable via Helm values to N tenants.

### 3. Automated TLS
`cert-manager` with a local CA (`homelab-ca` ClusterIssuer) issues per-ingress certificates automatically on annotation. No manual certificate management.

### 4. Secrets Management with ESO
An `ExternalSecret` reconciles the `tenant-config` Secret from the `ClusterSecretStore`. If the secret is deleted, ESO recreates it within 1 hour. In production, swap the Kubernetes provider for Vault or AWS Secrets Manager — same ExternalSecret spec.

### 5. Observability Out of the Box
`ServiceMonitor` resources register both tenants with Prometheus automatically (all-namespace selector). A Grafana dashboard ConfigMap (label `grafana_dashboard: "1"`) is auto-loaded by the sidecar — no Grafana UI interaction needed.

### 6. Zero-Trust Public Exposure
`cloudflared` runs as a 2-replica Deployment inside the cluster. It connects outbound to Cloudflare's edge — no inbound firewall rules opened. Public URLs (`k8s-ref-a/b.prudentiadigital.co.za`) route through Cloudflare to the ingress-nginx service.

---

## Metrics

| Metric | Value |
|---|---|
| Cluster bootstrap (MicroK8s + ArgoCD already running) | Existing homelab |
| Time to first ArgoCD sync (demo workload live) | < 5 min |
| TLS cert issuance time (cert-manager homelab-ca) | < 30s per cert |
| Prometheus scrape latency (ServiceMonitor → active target) | < 2 min |
| Pod resource footprint (both tenants) | ~96Mi RAM, ~30m CPU |
| Monthly hosting cost | R0 (homelab) |

---

## Screenshots

> Captured during M1 W2/W3 homelab sessions — see `docs/portfolio-item.md` for status.

| Screenshot | File | Status |
|---|---|---|
| `kubectl get pods,ingress,certificate -n k8s-ref-demo` | `docs/portfolio-item-assets/p4-kubectl-get-all.png` | Pending |
| ArgoCD UI — k8s-ref-demo app Synced/Healthy tree | `docs/portfolio-item-assets/p5-argocd-healthy.png` | Pending |
| Grafana dashboard — HTTP request rate + memory panels | `docs/portfolio-item-assets/p6-grafana-golden-signals.png` | Pending |

---

## Code Provenance

This project is:
- **Greenfield** — no existing employer codebase reused
- **MIT licensed** — free to fork and adapt
- **Written outside employment hours** — compliant with Capitec moonlighting policy
- **No NDA-sensitive data** — all config values are demo placeholders

---

## Repo Structure

```
k8s-ref/
├── argocd/apps/        # ArgoCD Application manifests
├── docs/
│   ├── architecture/   # Architecture diagrams
│   ├── case-study/     # This document
│   ├── decisions/      # ADRs (0001 practice, 0002 distribution choice)
│   └── runbooks/       # m1-kickoff.md — reproducible setup guide
├── helm/charts/
│   └── k8s-ref-demo/   # Helm chart: multi-tenant demo workload
│       ├── templates/
│       │   ├── cloudflared/   # Tunnel deployment (disabled until creds)
│       │   ├── eso/           # ClusterSecretStore + ExternalSecret
│       │   └── ...            # Deployments, Services, Ingresses, ServiceMonitors
│       └── values.yaml
├── observability/      # Prometheus rules, Grafana config (planned W5+)
├── scripts/
│   ├── bootstrap-microk8s.sh
│   └── install-cloudflared.sh
└── terraform/          # EKS equivalent (planned W5+)
```

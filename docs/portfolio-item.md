# Portfolio Item — Production Kubernetes Reference Architecture

> This document is the source for the Freelancer.com portfolio entry.
> Upload all three images below and use the title + description verbatim.

---

## Title (≤80 chars)

**Production K8s Reference Architecture — ArgoCD · ESO · Prometheus · Cloudflare**

---

## Description (paste into Freelancer.com portfolio item)

Built a production-grade Kubernetes reference cluster on a real homelab (not a mock environment) to demonstrate end-to-end platform engineering capability:

- **GitOps delivery** — ArgoCD App-of-Apps pattern: every cert, secret, dashboard, and workload is a Git commit. Nothing applied by hand.
- **Multi-tenant namespace isolation** — two independent tenants sharing a cluster with separate ingress routes, TLS certs, Prometheus scrape targets, and ESO-managed secrets.
- **Automated TLS** — cert-manager with a homelab CA ClusterIssuer issues per-ingress certificates on annotation — no manual cert management.
- **External Secrets Operator** — ClusterSecretStore + ExternalSecret pattern with drift correction. Production-swap to Vault/AWS Secrets Manager requires no ExternalSecret changes.
- **Full observability stack** — Prometheus (ServiceMonitor auto-registration), Grafana (ConfigMap-sidecar dashboard loading), Loki + Alloy (cluster-wide log aggregation), Tempo (distributed traces).
- **Zero-trust public exposure** — cloudflared runs as a 2-replica Deployment, outbound only — no firewall ports opened. Public URLs route via Cloudflare Edge.
- **Architecture Decision Records** — every non-trivial choice (MicroK8s vs k3s vs kind, ESO vs Sealed Secrets, etc.) documented before implementation.

**Stack:** MicroK8s 1.30 · ArgoCD · Helm · External Secrets Operator · cert-manager · Prometheus · Grafana · Loki · Tempo · Cloudflare Tunnel · GitHub Actions

**Repo:** https://github.com/maseko-lucky-9/k8s-ref (MIT licensed, greenfield, no employer code)

---

## Skills to tag

Kubernetes · DevOps · Amazon Web Services · Terraform · Docker · Helm · Microservices · CI/CD · .NET · Apache Kafka

---

## Images to upload (in order)

| Order | File | What it shows |
|---|---|---|
| 1 (cover) | `docs/architecture/assets/architecture-diagram.png` | Full cluster architecture — GitOps flow, namespaces, observability, tunnel |
| 2 | `docs/architecture/assets/github-repo.png` | GitHub repo — README, tech stack, quickstart, roadmap |
| 3 | `docs/architecture/assets/github-adr-0002.png` | ADR-0002 — MicroK8s vs k3s vs kind decision with comparison table |

---

## Upload checklist

- [x] Portfolio item created on Freelancer.com profile (`/portfolio-items/11362809-k8s-reference-architecture-gitops`)
- [x] Title pasted
- [x] Description pasted
- [x] All 3 images uploaded; `architecture-diagram.png` set as cover
- [x] Tags: kubernetes, devops, gitops, helm, argocd
- [x] GitHub repo URL in description (`Repo: https://github.com/maseko-lucky-9/k8s-ref`) — Freelancer.com has no separate external URL field; description is the correct location
- [x] Item visible on public profile (`freelancer.com/u/ThulaniMaseko`)

## Pending additions (gated on M1 W2–W4 homelab screenshots)

- [ ] P4 — `kubectl get pods,ingress,certificate -n k8s-ref-demo` (M1 W2)
- [ ] P5 — ArgoCD UI Synced/Healthy tree (M1 W2)
- [ ] P6 — Grafana golden-signals dashboard (M1 W3)
- [ ] P7 — Cloudflare Tunnel public URL (M1 W3)
- [ ] P8 — Populate metrics table in `docs/case-study/k8s-ref.md` (M1 W4)

# Architecture

> High-level architecture lives here once components land. Update this file as each milestone (M1–M6) ships.

## Status

Skeleton — populate alongside M1.

## Planned sections

- **System overview** — ASCII or Mermaid diagram of cluster + workloads + control plane
- **Control plane** — MicroK8s addons enabled / disabled, sizing, HA story
- **GitOps flow** — ArgoCD ApplicationSet pattern, source of truth, sync waves
- **Networking** — ingress, internal traffic, NetworkPolicy default-deny
- **Secrets flow** — Vault → ESO → Kubernetes Secret → Pod env/volume
- **Observability flow** — golden-signal SLOs, alert routing, log retention
- **Backup / DR** — etcd snapshots, PV backup, restore drill cadence

## Relevant ADRs

See [`../decisions/`](../decisions/).

## Diagrams

`assets/` (TBD) — Mermaid sources rendered to SVG.

# Observability

> Prometheus + Grafana + Loki + Tempo stack with golden-signal SLOs. Populated alongside M3.

## Stack

- **Metrics:** kube-prometheus-stack (Prometheus + Alertmanager + Grafana)
- **Logs:** Loki + Promtail
- **Traces:** Tempo + OpenTelemetry collector
- **Synthetic checks:** Blackbox exporter for HTTP probes

## Conventions

- Every workload exposes `/metrics` (Prometheus format) on a dedicated `metrics` port
- Structured JSON logs only — Loki labels: `namespace`, `app`, `severity`
- SLO targets per workload tracked in `observability/slos/<workload>.yaml`
- Alert routes split: warning → Slack channel; critical → PagerDuty
- Dashboards live in `observability/dashboards/` as JSON, deployed via the Grafana sidecar

## Layout (planned)

```
observability/
├── dashboards/           # Grafana JSON dashboards
├── slos/                 # SLO definitions per workload
├── alerts/               # PrometheusRule manifests
└── README.md
```

## Quickstart

Stack deploys via ArgoCD (`argocd/apps/observability.yaml`). After sync:

```bash
# Port-forward Grafana
kubectl port-forward -n observability svc/grafana 3000:80
# Open http://localhost:3000 (admin / generated password in Vault)
```

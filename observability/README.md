# Observability

> Prometheus + Grafana + Loki + Tempo stack with golden-signal visibility.

## Stack

- **Metrics:** kube-prometheus-stack (Prometheus + Alertmanager + Grafana)
- **Logs:** Loki + Alloy
- **Traces:** Tempo + OpenTelemetry collector
- **Synthetic checks:** Blackbox exporter for HTTP probes (planned M3)

## What lives where

**kube-prometheus-stack** (Prometheus, Grafana, Alertmanager) is a cluster-wide concern managed out of the `homelab-infra` repo (per the homelab-infra-first rule). It is not deployed by this repo.

**Tenant-scoped observability artefacts live in the Helm chart** and are what this repo owns:

| Artefact | Path | Purpose |
|---|---|---|
| ServiceMonitor | `helm/charts/k8s-ref-demo/templates/servicemonitor.yaml` | Registers both podinfo tenants with Prometheus (all-namespace selector) |
| Grafana dashboard ConfigMap | `helm/charts/k8s-ref-demo/templates/grafana-dashboard.yaml` | Sidecar-discovered dashboard (label `grafana_dashboard: "1"`) — auto-loaded with no Grafana UI interaction |

## Dashboard sidecar pattern

Grafana's sidecar container watches for ConfigMaps with the label `grafana_dashboard: "1"`. The chart ships a ConfigMap with this label containing the golden-signals dashboard JSON (request rate, 5xx rate, CPU, memory, goroutines, replicas for podinfo). ArgoCD GitOps provisions the dashboard — no manual Grafana import needed.

## Accessing Grafana (homelab)

```bash
# Via port-forward (after fetch-kubeconfig.sh + SSH tunnel)
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# Open http://localhost:3000
# admin password: kubectl -n monitoring get secret kube-prometheus-stack-grafana \
#   -o jsonpath='{.data.admin-password}' | base64 -d
```

## Planned (M3+)

- SLO definitions per workload (PrometheusRule)
- Alert routing: warning → Slack, critical → PagerDuty
- etcd snapshot cron
- NetworkPolicy default-deny per namespace

# Canary rollout runbook — tenant-a via Argo Rollouts

> **Status:** live since 2026-05-18 (M3, see [ADR-0006](../decisions/0006-progressive-delivery-argo-rollouts.md)).
> **Scope:** `tenant-a` in namespace `k8s-ref-demo`. `tenant-b` stays a plain Deployment.
> **Strategy:** replica-count canary (no service mesh) · 25% → analysis → 50% → analysis → 100%.

## What it is

`tenant-a` is an Argo Rollouts `Rollout` resource. On every image-tag bump, Argo Rollouts:

1. Spins up canary pods alongside stable pods (replica count: `replicas * setWeight / 100`).
2. Pauses for 30s for the new pods to warm up.
3. Runs an `AnalysisRun` against Prometheus: HTTP success rate over the last 60s must be ≥ 95%.
4. If pass → promote to next step. If fail → auto-rollback to stable, mark Rollout `Degraded`.

The `tenant-a` Service uses the same `app: tenant-a` label across stable + canary pods, so the in-cluster Service splits traffic proportionally to replica count — no service-mesh required.

## Trigger a canary

Edit `helm/charts/k8s-ref-demo/values.yaml`:

```yaml
image:
  tag: "6.7.1"   # bump from 6.7.0
```

Commit, PR, merge → ArgoCD reconciles → Rollout starts the canary state machine.

For local development without a PR, you can `kubectl set image rollout/tenant-a podinfo=stefanprodan/podinfo:6.7.1 -n k8s-ref-demo` — but ArgoCD will revert on next sync, so prefer the GitOps path.

## Watch a canary in flight

```bash
# CLI
kubectl argo rollouts get rollout tenant-a -n k8s-ref-demo --watch
# Or the dashboard (cluster-internal only)
kubectl port-forward -n argo-rollouts svc/argo-rollouts-dashboard 3100:3100
# → http://127.0.0.1:3100
```

Expected progression (happy path, ~90s wall-clock):

```
Step 0: setWeight 25       → 1 canary + 2 stable (5s)
Step 1: pause 30s          → AnalysisRun waiting
Step 2: AnalysisRun         → success-rate query, must be ≥ 0.95
Step 3: setWeight 50       → 2 canary + 2 stable
Step 4: pause 30s          → AnalysisRun waiting
Step 5: AnalysisRun         → success-rate query again
Step 6: setWeight 100      → all canary, stable scaled to 0
        Promoted → Healthy
```

## Trigger a deliberate-fail (rollback demo)

To demonstrate auto-rollback for the portfolio screenshot:

```yaml
# In values.yaml — point at a non-existent tag
image:
  tag: "does-not-exist"
```

The canary pods will ImagePullBackOff, never become Ready, Prometheus will see no traffic from the canary path → AnalysisRun fails the success-rate threshold → Argo Rollouts marks the Rollout `Degraded` and auto-rolls back to the previous stable revision. No human intervention.

```bash
kubectl argo rollouts get rollout tenant-a -n k8s-ref-demo
# Status: Degraded · Message: RolloutAborted: Rollout aborted update to revision N
```

Recover by reverting the values.yaml change + re-syncing.

## Promote a paused canary manually

If you replace one of the `pause: { duration: 30s }` steps with `pause: {}` (no duration), the canary stops at that step and waits for explicit promotion:

```bash
kubectl argo rollouts promote tenant-a -n k8s-ref-demo
# Or pause/abort:
kubectl argo rollouts pause tenant-a -n k8s-ref-demo
kubectl argo rollouts abort tenant-a -n k8s-ref-demo
```

## AnalysisTemplate — `tenant-success-rate`

Defined in `helm/charts/k8s-ref-demo/templates/analysistemplate.yaml`. Args:
- `tenant`: tenant name (e.g., `tenant-a`)
- `namespace`: namespace (e.g., `k8s-ref-demo`)

PromQL:

```promql
sum(rate(http_request_duration_seconds_count{
  kubernetes_namespace="<ns>",
  app="<tenant>",
  status="200"
}[1m]))
/
sum(rate(http_request_duration_seconds_count{
  kubernetes_namespace="<ns>",
  app="<tenant>"
}[1m]))
```

`successCondition: result[0] >= 0.95` · `failureLimit: 1` (one failure aborts).

Tune the threshold per workload — 0.95 is conservative for podinfo (which is always healthy when up). For real workloads with known transient error rates, drop to 0.99 or add additional metrics (p95 latency, etc.).

## Failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Rollout stuck in `Progressing` at step 0 | Canary pod never reaches Ready | `kubectl describe pod` — image pull, readinessProbe, resource limits |
| AnalysisRun `Inconclusive` with no measurements | Prometheus address wrong or scrape target missing | Check ServiceMonitor exists for tenant; check `http://...:9090/api/v1/query?query=...` returns data |
| AnalysisRun `Failed` immediately | PromQL returns NaN (divide by zero — no traffic yet) | Add a `count: 3` + `interval: 30s` so analysis waits for traffic, OR increase pause before analysis |
| Rollout `Healthy` but old stable replicas linger | `revisionHistoryLimit` higher than needed | Reduce in `rollout.yaml` |

## Decommission

To remove the Rollout pattern from tenant-a (rollback to plain Deployment):

1. Flip `rollout: false` on the tenant in `values.yaml`.
2. Commit, PR, merge.
3. ArgoCD sync: `Rollout/tenant-a` gets pruned, `Deployment/tenant-a` is created. The Service is untouched (same selector).

To uninstall Argo Rollouts entirely:

1. `kubectl delete -f argocd/apps/argo-rollouts.yaml`
2. CRDs persist intentionally (preserves any in-flight rollouts elsewhere). Manually `kubectl delete crd rollouts.argoproj.io analysistemplates.argoproj.io analysisruns.argoproj.io experiments.argoproj.io` if a full uninstall is needed.

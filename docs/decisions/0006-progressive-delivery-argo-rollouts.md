# 6. Progressive delivery via Argo Rollouts

Date: 2026-05-18

## Status

**Accepted** (2026-05-18) — canary completed end-to-end on the homelab cluster: tenant-a image transition `6.7.0 → 6.7.1 → 6.7.2` proceeded through all 7 canary steps; AnalysisRun returned `Successful` against live Prometheus metrics. P10 evidence captured at `docs/portfolio-item-assets/p10-argo-rollouts-canary-evidence.txt`.

## Consequences confirmed (2026-05-18 apply)

- Argo Rollouts controller landed via ArgoCD Application (chart `argo-helm/argo-rollouts` v2.40.9, app v1.9.0). 5 CRDs installed: `rollouts`, `analysisruns`, `analysistemplates`, `clusteranalysistemplates`, `experiments`. Controller + dashboard pods Healthy.
- `tenant-a` is now a `Rollout` resource; `tenant-b` stays a plain `Deployment` (side-by-side migration pattern, as decided).
- Replica-count canary works with the existing single Service: the in-cluster `tenant-a` Service routes to all pods bearing `app: tenant-a` regardless of which ReplicaSet owns them. No service-mesh required.
- **Auto-rollback verified in flight.** The first canary attempt errored on an empty Prometheus result (`reflect: slice index out of range`) — the Rollout aborted automatically to the stable revision without human intervention. This is the safety property the pattern adds over a plain Deployment.
- **Two PromQL gotchas surfaced + fixed:**
  - Labels from kube-prometheus-stack relabeling are `namespace` + `job` (not `kubernetes_namespace` + `app`). The AnalysisTemplate now uses the correct labels.
  - Empty rate() results (idle workload, fresh canary pod) cause the analysis to error. The query now ends with `or on() vector(1)` so a zero-traffic state evaluates to 1.0 (healthy by default). Documented in the template comment.
- ArgoCD Application `argo-rollouts` hits a transient Helm-chart fetch failure (DNS to `release-assets.githubusercontent.com` timing out on the ArgoCD repo-server pod). Resources land regardless; ArgoCD oscillates between `Synced/Healthy` and `Unknown/Healthy` until DNS settles. Tracking under a future ArgoCD-repo-server DNS-tuning ticket if it recurs.

## Context

The reference architecture demonstrates GitOps, multi-tenancy, secret management (M2: ESO + Vault), TLS, observability, and zero-trust public exposure (M1 W3: Cloudflare Tunnel). Every meaningful production cluster ALSO needs progressive delivery — the ability to ship a new container image *without* the blast radius of a rolling update that puts 100% of traffic on the new revision the moment the readiness probe goes green.

Plain Kubernetes Deployments give us `strategy: RollingUpdate` with `maxUnavailable`/`maxSurge`. That's a *speed* control, not a *correctness* control — it just spaces the cutover out over a few seconds. Real progressive delivery means:

1. Shift a small fraction of traffic to the new version.
2. Watch SLI metrics (success rate, latency) for a defined window.
3. If the SLIs hold, shift more traffic. Otherwise auto-rollback to the stable version.
4. Repeat until 100%.

The portfolio story this enables: "I can ship to production with automated safety — bad images don't reach 100% of users; analysis metrics decide the cutover."

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Argo Rollouts** (Argo project, K8s-native CRDs: `Rollout`, `AnalysisTemplate`, `Experiment`) | Already in the Argo ecosystem alongside ArgoCD. Strong analysis integrations (Prometheus, Datadog, Wavefront, NewRelic). Doesn't require a service mesh for replica-count canary. Active maintenance, mature project. | New CRDs to install. UI requires a separate dashboard (or `argo rollouts dashboard`). |
| **B. Flagger** (Flux ecosystem) | Mature, widely used. Strong support for Istio/Linkerd/NGINX traffic splitting. | Pairs naturally with FluxCD (we use ArgoCD); doesn't bring the same UI integration. Requires a service mesh OR ingress controller traffic-split for percentage routing. |
| **C. In-house canary** (manual: 2 Deployments + Service selector tweaks + bash) | Zero new tools. Fully under the team's control. | Re-invents the wheel; no analysis automation; no rollback automation; not portfolio-meaningful. |
| **D. Service-mesh-native** (Istio VirtualService weighted routing) | Decouples canary from replica counts, gives true traffic-percentage routing. | Pulls in Istio — explicitly out of scope per `CLAUDE.md` ("Service mesh (Istio/Linkerd) — keep complexity bounded for the demo"). |

## Decision

**Option A — Argo Rollouts**, using **replica-count canary** (not traffic-split mesh routing), with **Prometheus AnalysisTemplate** wired to the existing `kube-prometheus-stack` install for metric checks.

Specifically:
- Install the `argo-rollouts` controller via a new ArgoCD `Application` (`argocd/apps/argo-rollouts.yaml`), sourced from the upstream Helm chart `argo-rollouts` in the `argoproj` repo. Namespace `argo-rollouts`. CRDs land via the chart.
- Convert **only `tenant-a`** in `helm/charts/k8s-ref-demo` from a `Deployment` to a `Rollout`. `tenant-b` stays a plain `Deployment` — the cluster now demonstrates BOTH patterns side-by-side, which is a stronger portfolio story than full conversion ("here's how you'd transition incrementally").
- Canary steps: `25% → analysis (1×30s) → 50% → analysis (1×30s) → 100%`. Total wall-clock: ~70-90 seconds for the happy path. Failed analysis auto-rolls back.
- `AnalysisTemplate` `tenant-success-rate` queries Prometheus for the rate of `http_request_duration_seconds_count{status="200"}` divided by the rate of all `http_request_duration_seconds_count{...}` over the last 1 minute. Success threshold: `>= 0.95`. (Stable threshold for podinfo, which is always healthy unless deliberately broken.)
- The existing `Service` `tenant-a` keeps a single label selector. Argo Rollouts' replica-count strategy means stable + canary pods share the Service and traffic distributes proportionally to replica count. No `Ingress` changes needed.

## Why this shape

- **Replica-count over mesh**: keeps the demo small. Adding Istio for canary alone is a 10x complexity jump. Replica-count canary is "production grade" for any workload that's at least 4-replica scale; podinfo demo scales to 4 transiently during the canary.
- **Only convert one tenant**: portfolio screenshot value > consistency. The "before/after side-by-side" narrative is more honest about a real migration path.
- **Prometheus analysis already wired**: we have a working ServiceMonitor scraping podinfo metrics into `kube-prometheus-stack`. No new scrape setup. Rollouts queries Prometheus directly via in-cluster Service DNS.
- **Rollback automation is the point**: a bad image (deliberately broken tag) MUST roll back without human intervention. The AnalysisTemplate's failureLimit + failureCondition do that — that's the assertion to demonstrate in the runbook.

## Consequences

**Good**:
- New CRDs (`Rollout`, `AnalysisTemplate`, `AnalysisRun`, `Experiment`) bring real progressive-delivery semantics.
- Portfolio P10 candidate: ArgoCD Rollouts dashboard showing a canary mid-flight with analysis metrics ticking up.
- Clean side-by-side comparison: tenant-a is `Rollout`, tenant-b is `Deployment`. Demonstrates incremental migration.
- Prometheus-driven analysis ties together M1 (observability) and M3 (progressive delivery) — coherent reference architecture story.
- Rollback automation: a broken `podinfo` image tag self-heals without human intervention.

**Costs**:
- ~10 new K8s objects in the cluster (Rollouts CRD definitions + 1 controller Deployment + 1 RBAC bundle + AnalysisTemplates).
- `argocd-rollouts-dashboard` is a separate pod / port-forward — adds one more UI surface to manage (kept cluster-internal; no public exposure).
- During a canary, replica count temporarily exceeds the configured stable count (e.g., 2 stable + 2 canary = 4 pods peak). For larger workloads this needs cluster headroom planning; for the demo workload it's negligible.
- A failed canary leaves a `replicasets/<rollout>-<hash>` in `Failed` state — needs cleanup logic or `revisionHistoryLimit` tuning.

**Reversible** — flip `rollout: false` in `values.yaml`, re-render → `Rollout` removed, `Deployment` returns. The `Service` stays unchanged either way.

## Rollback plan

If progressive delivery turns out to be ill-fitting (e.g., podinfo metric variance breaks analysis stability):

- **Tier 1**: flip `rollout: false` on tenant-a in `values.yaml`, commit, ArgoCD sync. Rollout → Deployment within one sync cycle. `AnalysisTemplate` resource stays (harmless without Rollouts referencing it).
- **Tier 2**: delete the `argocd/apps/argo-rollouts.yaml` Application. ArgoCD prunes the controller; CRDs persist (intentionally — deleting CRDs would destroy any in-flight rollouts). Manually `kubectl delete crd rollouts.argoproj.io analysistemplates.argoproj.io ...` if a full uninstall is needed.

## Open question for a future ADR

If `tenant-a` proves stable on Rollouts and a second canary use-case appears (e.g., the cloudflared Deployment itself, or a future workload), revisit traffic-split routing via NGINX Ingress annotations (`nginx.ingress.kubernetes.io/canary-weight`) before pulling in a service mesh. Replica-count canary scales fine for the demo; traffic-split is the next rung if/when needed.

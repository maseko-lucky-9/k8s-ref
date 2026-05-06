# 2. Homelab Kubernetes distribution: MicroK8s vs k3s vs kind

Date: 2026-04-26

## Status

Accepted — MicroK8s chosen. Validated during M1 W1 (2026-04-26 to 2026-05-06).

## Context

This repo's M1 milestone is "MicroK8s bootstrap + ArgoCD up + first sample app deployed" (per `README.md` roadmap). The README assumes MicroK8s, but the choice has not been formally evaluated against alternatives. Three production-realistic options exist for a single-node homelab demo cluster that's also defensible to a hiring manager:

- **MicroK8s** (Canonical) — snap-installed, addon-driven, single-binary
- **k3s** (Rancher / SUSE) — lightweight, single-binary, very popular at the edge
- **kind** (Kubernetes-in-Docker, sig-testing) — runs the cluster inside Docker containers

Constraints driving the choice:

1. **Hosting cost cap** — ≤ R500/mo (~$27 USD), per Risk Register. Implies running on existing homelab hardware, NOT a cloud K8s service.
2. **Reproducibility** — a hiring manager / Toptal vetter must be able to clone the repo and stand up an equivalent cluster on their own machine.
3. **Production realism** — the demo must demonstrate patterns I'd ship at Capitec / EKS, not "toy cluster" tricks.
4. **Resource ceiling** — the homelab host has finite RAM (~16 GB shared with other services per `wiki/projects/homelab_nas_unversioned.md`). Cluster + workloads must run in <8 GB.
5. **Reuse existing homelab** — the homelab already runs MicroK8s with ArgoCD per `wiki/reference/infrastructure_stack.md` (P1 status). Switching distros means rebuilding tested infra.

## Decision

**MicroK8s.** M1 W1 (2026-04-26) confirmed the leading candidate: all four target addons (ArgoCD, ESO, cert-manager, kube-prometheus-stack via Helm) deployed without custom config; RAM headroom remained >4 GB after the observability stack landed. The existing homelab already ran MicroK8s, so switching to k3s would have consumed the project time we needed for workload content and portfolio artefacts.

## Options considered

| Dimension | MicroK8s | k3s | kind |
|---|---|---|---|
| **Install footprint** | Snap, ~600 MB | Single binary, ~100 MB | Docker images, ~1 GB |
| **Single-node baseline RAM** | ~1.5 GB | ~700 MB | ~2 GB (Docker overhead) |
| **HA story** | 3-node HA built-in | Embedded etcd (3+ nodes) | None — local only |
| **Addon ecosystem** | One-command addons (cert-manager, ingress, registry, observability) | Manifests via `kubectl apply` from third-party charts | Manifests only |
| **Ingress story** | `microk8s enable ingress` → ingress-nginx | Bundled Traefik (or disable + install your own) | None default — install MetalLB + ingress-nginx manually |
| **Storage** | `microk8s enable hostpath-storage` | Built-in local-path provisioner | hostPath via Docker volumes |
| **CNI** | Calico (default) or Cilium | flannel (default) or Calico | kindnet (basic) |
| **GPU support** | Yes via addon | Limited | No |
| **Production realism** | High — runs in Canonical prod environments | High — runs at the edge in production | **Low** — designed for testing/CI, not prod |
| **Ease of teardown / restart** | `microk8s reset` or snap remove | `k3s-uninstall.sh` | `kind delete cluster` (instant) |
| **Hiring-manager familiarity** | Common in K8s shops, less so in pure devops shops | Very common at edge / IoT / lightweight prod | Common only as test infra |
| **Existing homelab fit** | ✓ Already running | Would replace existing | Could co-exist (Docker on host) |

## Trade-offs

**Why MicroK8s (current homelab) is the leading candidate:**
- Already running; existing addons (ArgoCD, ESO, cert-manager, kube-prometheus-stack) tested and working (Vault wiring deferred to M2 per ADR-0003)
- Repo time saved goes to actual workloads + observability content
- Snap-based addons are unusual but Canonical-native — defensible in interview ("this matches what I'd run for a small SaaS that values one-command ops")

**Why k3s deserves serious consideration:**
- Smaller footprint frees RAM for richer demo workloads
- More common in hiring conversations as an "edge / lightweight production" choice
- Switching loses the existing addon work but gains a cleaner story for "I evaluated alternatives"

**Why kind is rejected outright:**
- "Local Docker test cluster" undersells the project — clients reviewing the repo will read it as a toy
- No realistic path from this demo to a production EKS deploy (different networking model, different storage)
- Doesn't match how I'd actually ship to a client

## Decision criteria (to apply at M1)

Choose **MicroK8s** if:
- ≥2 of the planned addons (ArgoCD, ESO, cert-manager, monitoring) are confirmed-working under MicroK8s without custom config
- Total RAM headroom remains >4 GB after observability stack lands

Choose **k3s** if:
- MicroK8s addon footprint exceeds RAM budget once Loki/Tempo land
- A hiring conversation reveals strong preference for k3s (record those signals during weeks 1–4 PPH/Upwork bids)

**Never choose kind** for this repo (production realism trumps speed of iteration).

## Consequences

**Positive (whichever K8s distro wins)**
- Decision is documented and defensible in interviews
- Future ADRs can reference this decision when justifying cluster-wide constraints
- Switching cost is bounded — the workloads (Helm charts) and ArgoCD ApplicationSet manifests should be portable across MicroK8s / k3s

**Negative**
- Decision deferred to M1 kickoff means README current reads as "MicroK8s" without a recorded rationale until M1 lands

**Neutral**
- Accepted on M1 W1 close-out (2026-05-06). If cluster RAM becomes a constraint as Loki/Tempo mature (M3), a k3s migration would be captured in a superseding ADR rather than editing this one in place.

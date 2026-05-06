# Scripts

> Bootstrap + helper scripts. All Bash; all idempotent; all `set -euo pipefail`.

## Conventions

- Every script begins with `#!/usr/bin/env bash` + `set -euo pipefail`
- Every script is idempotent — re-running must not break a working setup
- Every script logs what it's about to do BEFORE doing it
- Scripts are checked with `shellcheck` in CI

## Implemented scripts

- `bootstrap-microk8s.sh` — One-shot homelab bootstrap (MicroK8s install + addons + ArgoCD seed)
- `fetch-kubeconfig.sh` — Fetch homelab kubeconfig via Tailscale SSH; rewrites server URL for SSH-tunnel use
- `verify-cluster.sh` — Read-only health probes: nodes ready, pods running, certs issued, ArgoCD synced; exits non-zero on failure
- `install-cloudflared.sh` — Host-side cloudflared install + manual tunnel bootstrap runbook (see also `docs/runbooks/cloudflare-tunnel.md`)

## Planned scripts

- `bootstrap-eks.sh` — One-shot EKS bootstrap (terraform apply + ArgoCD seed)
- `teardown-eks.sh` — Idempotent EKS teardown (cost guard)
- `gen-readme-toc.sh` — Regenerate README table of contents (dev tool)

## Usage

```bash
./scripts/bootstrap-microk8s.sh
./scripts/verify-cluster.sh
```

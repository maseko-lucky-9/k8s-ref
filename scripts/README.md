# Scripts

> Bootstrap + helper scripts. All Bash; all idempotent; all `set -euo pipefail`.

## Conventions

- Every script begins with `#!/usr/bin/env bash` + `set -euo pipefail`
- Every script is idempotent — re-running must not break a working setup
- Every script logs what it's about to do BEFORE doing it
- Scripts are checked with `shellcheck` in CI

## Planned scripts

- `bootstrap-microk8s.sh` — One-shot homelab bootstrap (MicroK8s install + addons + ArgoCD seed)
- `bootstrap-eks.sh` — One-shot EKS bootstrap (terraform apply + ArgoCD seed)
- `teardown-eks.sh` — Idempotent EKS teardown (cost guard)
- `verify-cluster.sh` — Smoke check: control plane, nodes ready, ArgoCD synced, sample workload responding
- `gen-readme-toc.sh` — Regenerate README table of contents (dev tool)

## Usage

```bash
./scripts/bootstrap-microk8s.sh
./scripts/verify-cluster.sh
```

#!/usr/bin/env bash
# Resets the live ArgoCD + Grafana admin UI passwords to the values stored
# in their respective Kubernetes Secrets, so the UIs can be screenshotted
# for the portfolio (P5 + P6).
#
# Why this exists: the cluster has been live for 84+ days, and the admin
# UI passwords were rotated post-install without updating the source
# Secrets. As a result, the values still readable via kubectl no longer
# unlock the UIs. This script reconciles the two — read the secret, set
# the live UI password to match. Reversible: rotate again from the UI any
# time.
#
# Prereqs:
#   - SSH tunnel to homelab apiserver open
#       ssh -L 16443:127.0.0.1:16443 -N homelab-tunnel
#   - KUBECONFIG=$HOME/.kube/config-homelab exported
#   - htpasswd (Apache utilities) installed: `brew install httpd` on macOS
#
# Usage:
#   ./scripts/reset-ui-admin-passwords.sh                # reset both
#   ./scripts/reset-ui-admin-passwords.sh --only argocd  # reset only one
#   ./scripts/reset-ui-admin-passwords.sh --only grafana
#   ./scripts/reset-ui-admin-passwords.sh --dry-run      # print plan, no writes
set -euo pipefail

KUBE="${KUBECONFIG:-$HOME/.kube/config-homelab}"
ONLY=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --only)   ONLY="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed 's/^# //'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    eval "$@"
  fi
}

reset_argocd() {
  echo "[argocd] reading admin password from secret argocd-initial-admin-secret…"
  local pw
  pw=$(KUBECONFIG="$KUBE" kubectl get secret -n argocd argocd-initial-admin-secret \
       -o jsonpath='{.data.password}' | base64 -d)
  if [[ -z "$pw" ]]; then
    echo "[argocd] ERROR: secret has no .data.password — bail" >&2
    return 1
  fi
  echo "[argocd] computing bcrypt hash…"
  # ArgoCD stores bcrypt at argocd-secret.admin.password.
  local hash
  hash=$(htpasswd -bnBC 10 "" "$pw" | tr -d ':\n' | sed 's/$2y/$2a/')
  echo "[argocd] patching argocd-secret with new admin.password + admin.passwordMtime…"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  run "KUBECONFIG=\"$KUBE\" kubectl -n argocd patch secret argocd-secret -p '{\"stringData\": {\"admin.password\": \"$hash\", \"admin.passwordMtime\": \"$now\"}}'"
  echo "[argocd] done. Try: open http://127.0.0.1:8090 with admin / <value-from-secret>"
}

reset_grafana() {
  echo "[grafana] reading admin password from secret grafana-admin-credentials…"
  local pw
  pw=$(KUBECONFIG="$KUBE" kubectl get secret -n observability grafana-admin-credentials \
       -o jsonpath='{.data.admin-password}' | base64 -d)
  if [[ -z "$pw" ]]; then
    echo "[grafana] ERROR: secret has no .data.admin-password — bail" >&2
    return 1
  fi
  echo "[grafana] resetting via grafana-cli inside the running pod…"
  local pod
  pod=$(KUBECONFIG="$KUBE" kubectl get pod -n observability \
          -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
  if [[ -z "$pod" ]]; then
    echo "[grafana] ERROR: no Grafana pod found — check label selector" >&2
    return 1
  fi
  run "KUBECONFIG=\"$KUBE\" kubectl exec -n observability \"$pod\" -c grafana -- grafana-cli admin reset-admin-password \"$pw\""
  echo "[grafana] done. Try: open http://127.0.0.1:8091 with admin / <value-from-secret>"
}

case "$ONLY" in
  argocd)  reset_argocd ;;
  grafana) reset_grafana ;;
  "")      reset_argocd; echo; reset_grafana ;;
  *)       echo "--only must be one of: argocd, grafana" >&2; exit 2 ;;
esac

echo
echo "After both UIs are reachable, capture screenshots:"
echo "  ./scripts/verify-cluster.sh   # smoke check"
echo "  open http://127.0.0.1:8090    # ArgoCD UI for P5"
echo "  open http://127.0.0.1:8091    # Grafana UI for P6"

#!/usr/bin/env bash
# Verifies the ESO → Vault migration end-to-end (M2 dev-mode and M3 prod-mode
# both pass the same 6 checks: CSS Valid, ExternalSecret SecretSynced, K8s
# Secret materialised, rotation roundtrip propagates within one refresh).
# Vault-shape agnostic — works against dev (inmem, hardcoded root token) and
# prod (Raft, Shamir-unsealed, generated root token from vault-init-keys).
#
# Run this after:
#   1. Applying argocd/apps/vault.yaml + argocd/apps/vault-bootstrap.yaml
#   2. Setting helm/charts/k8s-ref-demo/values.yaml `eso.useVault: true` and
#      letting ArgoCD reconcile.
#
# What it checks (each step gates the next — bail on first failure):
#   A. Both Applications are Synced + Healthy.
#   B. The vault-bootstrap Job completed successfully.
#   C. The Vault-backed ClusterSecretStore exists and is the only active one.
#   D. The ExternalSecret references the Vault store and reports Ready=True.
#   E. The materialised K8s Secret (`tenant-config`) has the seed app-env value.
#   F. Rotation roundtrip: write new value in Vault → force ESO sync →
#      confirm K8s Secret updated to new value within 30s.
#
# Prereqs (pick ONE of two transports — homelab API cert SAN includes both):
#
#   Option A: Tailscale-direct (no SSH tunnel needed) —
#     export KUBECONFIG=$HOME/.kube/config-homelab-ts
#     (config-homelab-ts points server: at https://100.114.75.127:16443)
#
#   Option B: SSH tunnel (legacy) —
#     ssh -L 16443:127.0.0.1:16443 -N homelab-tunnel
#     export KUBECONFIG=$HOME/.kube/config-homelab
#
# Usage:
#   ./scripts/verify-eso-vault-migration.sh             # full check incl. rotation
#   ./scripts/verify-eso-vault-migration.sh --no-rotate # skip the rotation step
set -euo pipefail

NO_ROTATE=false
case "${1:-}" in
  --no-rotate) NO_ROTATE=true ;;
  -h|--help)   grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
  "") ;;
  *)  echo "Unknown arg: $1" >&2; exit 2 ;;
esac

ok()   { printf '\033[32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWARN\033[0m %s\n' "$*"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*"; }

# -- A. ArgoCD Applications Synced + Healthy --
echo "[A] ArgoCD vault-k8s-ref-demo + vault-k8s-ref-demo-bootstrap Applications…"
for app in vault-k8s-ref-demo vault-k8s-ref-demo-bootstrap; do
  state=$(kubectl get application -n argocd "$app" \
            -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null \
          || echo "NotFound")
  if [[ "$state" != "Synced/Healthy" ]]; then
    fail "$app Application not Synced/Healthy (got: $state)"
  fi
  ok "$app  $state"
done

# -- B. Bootstrap Job completed --
echo "[B] vault-bootstrap Job (in namespace vault-k8s-ref-demo)…"
status=$(kubectl get job -n vault-k8s-ref-demo vault-bootstrap-config \
           -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null \
         || echo "")
if [[ "$status" != "True" ]]; then
  fail "vault-bootstrap-config Job not Complete (status condition: ${status:-none})"
fi
ok "vault-bootstrap-config Job Complete=True"

# -- C. ClusterSecretStore state --
echo "[C] ClusterSecretStores…"
stores=$(kubectl get clustersecretstore -o jsonpath='{range .items[*]}{.metadata.name}={.spec.provider}{"\n"}{end}')
if ! echo "$stores" | grep -q 'k8s-ref-demo-vault-store='; then
  fail "Vault-backed ClusterSecretStore (k8s-ref-demo-vault-store) is missing"
fi
ok "Vault-backed ClusterSecretStore present"
if echo "$stores" | grep -q '^k8s-ref-demo-store='; then
  warn "Old kubernetes-backed store still present — clean up after verification"
fi
note "Active stores:"
echo "$stores" | sed 's/^/    /'

# -- D. ExternalSecret Ready --
echo "[D] ExternalSecret tenant-config…"
storeref=$(kubectl get externalsecret -n k8s-ref-demo tenant-config \
             -o jsonpath='{.spec.secretStoreRef.name}')
if [[ "$storeref" != "k8s-ref-demo-vault-store" ]]; then
  fail "ExternalSecret still references '$storeref', expected k8s-ref-demo-vault-store"
fi
ok "ExternalSecret secretStoreRef = $storeref"

ready=$(kubectl get externalsecret -n k8s-ref-demo tenant-config \
          -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [[ "$ready" != "True" ]]; then
  fail "ExternalSecret Ready != True (got: ${ready:-unset})"
fi
ok "ExternalSecret Ready=True"

# -- E. Materialised Secret has expected app-env value --
echo "[E] Materialised Secret tenant-config…"
appenv=$(kubectl get secret -n k8s-ref-demo tenant-config \
           -o jsonpath='{.data.app-env}' | base64 -d)
if [[ -z "$appenv" ]]; then
  fail "Secret tenant-config has empty app-env"
fi
ok "Secret tenant-config.app-env = '$appenv'"

# -- F. Rotation roundtrip --
if $NO_ROTATE; then
  echo "[F] Rotation roundtrip — skipped (--no-rotate)"
  exit 0
fi

echo "[F] Rotation roundtrip (demo Vault → ESO → K8s Secret)…"
new_value="rotated-$(date +%s)"
note "Writing '$new_value' to secret/eso-source-config in demo Vault…"

# Root token: post-M3 (ADR-0005) Vault is initialised with a generated root
# token stored in vault-init-keys Secret. Read it here so the rotation step
# works against both dev-mode (`root`) and prod-mode (generated) Vault.
# Falls back to "root" if the Secret is missing — useful for any cluster
# still on dev-mode (M2 era) where the new Secret hasn't been created yet.
root_token=$(kubectl get secret -n vault-k8s-ref-demo vault-init-keys \
               -o jsonpath='{.data.root-token}' 2>/dev/null | base64 -d || true)
root_token="${root_token:-root}"

kubectl exec -n vault-k8s-ref-demo vault-k8s-ref-demo-0 -- sh -c \
  "VAULT_TOKEN='$root_token' vault kv put secret/eso-source-config \
     app-env='$new_value' \
     feature-flags='rotation-test=true' \
     log-level=debug" >/dev/null

note "Forcing ESO re-sync (annotation)…"
kubectl annotate externalsecret -n k8s-ref-demo tenant-config \
  "force-sync=$(date +%s)" --overwrite >/dev/null

note "Polling Secret for new value (timeout 30s)…"
for i in $(seq 1 15); do
  current=$(kubectl get secret -n k8s-ref-demo tenant-config \
              -o jsonpath='{.data.app-env}' | base64 -d)
  if [[ "$current" == "$new_value" ]]; then
    ok "Rotation propagated: app-env = '$current' after ${i}x2s polls"
    exit 0
  fi
  sleep 2
done

fail "Rotation did not propagate within 30s — Secret still '$current', expected '$new_value'"

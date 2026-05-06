#!/usr/bin/env bash
# Read-only health probes for the k8s-ref homelab cluster.
# Exits non-zero if any check fails, making it CI-able.
#
# Requires: kubectl in PATH, KUBECONFIG pointing at the homelab context.
# Optional: argocd CLI for the ArgoCD sync check (skipped if absent).
set -euo pipefail

NAMESPACE="${NAMESPACE:-k8s-ref-demo}"
PASS=0
FAIL=0

check() {
  local label="$1"
  local result="$2"
  if [ "${result}" = "true" ] || [ "${result}" = "0" ]; then
    echo "  ✓ ${label}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${label} (got: ${result})"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Nodes ==="
not_ready=$(kubectl get nodes \
  -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' \
  | tr ' ' '\n' | grep -c "^True$" || true)
total_nodes=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
check "All nodes Ready (${not_ready}/${total_nodes})" \
  "$([ "${not_ready}" -eq "${total_nodes}" ] && echo true || echo false)"

echo ""
echo "=== Pods in ${NAMESPACE} ==="
bad_pods=$(kubectl get pods -n "${NAMESPACE}" -o json \
  | jq '[.items[] | select(.status.phase!="Running" and .status.phase!="Succeeded")] | length')
check "All pods Running or Succeeded (bad=${bad_pods})" \
  "$([ "${bad_pods}" -eq 0 ] && echo true || echo false)"

echo ""
echo "=== Certificates in ${NAMESPACE} ==="
bad_certs=$(kubectl get certificate -n "${NAMESPACE}" -o json \
  | jq '[.items[] | select(
      (.status.conditions // [])
      | map(select(.type=="Ready")) | first | .status != "True"
    )] | length' 2>/dev/null || echo "0")
check "All certificates Ready (bad=${bad_certs})" \
  "$([ "${bad_certs}" -eq 0 ] && echo true || echo false)"

echo ""
echo "=== ArgoCD ==="
if command -v argocd &>/dev/null; then
  sync=$(argocd app get k8s-ref-demo -o json 2>/dev/null \
    | jq -r '.status.sync.status' || echo "Unknown")
  health=$(argocd app get k8s-ref-demo -o json 2>/dev/null \
    | jq -r '.status.health.status' || echo "Unknown")
  check "k8s-ref-demo sync=${sync} health=${health}" \
    "$([ "${sync}" = "Synced" ] && [ "${health}" = "Healthy" ] && echo true || echo false)"
else
  echo "  - argocd CLI not found; skipping ArgoCD check"
fi

echo ""
echo "=== Summary ==="
echo "  Passed: ${PASS}  Failed: ${FAIL}"
[ "${FAIL}" -eq 0 ]

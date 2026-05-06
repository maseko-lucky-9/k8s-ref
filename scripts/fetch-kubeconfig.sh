#!/usr/bin/env bash
# Fetch homelab kubeconfig via Tailscale SSH and rewrite server URL to
# 127.0.0.1 so the SSH tunnel handles TLS (cert SAN includes 127.0.0.1).
#
# Usage:
#   ./scripts/fetch-kubeconfig.sh
#
# Then in a separate shell, open the tunnel:
#   ssh -L 16443:127.0.0.1:16443 -N ltmaseko7@<HOMELAB_HOST>
#
# Then:
#   export KUBECONFIG=~/.kube/config-homelab
#   kubectl get nodes
set -euo pipefail

HOST="${HOMELAB_HOST:-100.114.75.127}"
HOMELAB_USER="${HOMELAB_USER:-ltmaseko7}"
DEST="${KUBECONFIG_DEST:-$HOME/.kube/config-homelab}"

echo "Fetching kubeconfig from ${HOMELAB_USER}@${HOST} …"
scp "${HOMELAB_USER}@${HOST}:${HOME}/.kube/config-microk8s" "${DEST}"
chmod 600 "${DEST}"

# Rewrite server URL to 127.0.0.1 — the MicroK8s apiserver cert SAN includes
# 127.0.0.1 by default but not the Tailscale IP, so direct TLS would fail.
sed -i.bak -E 's|server: https://[0-9.]+:16443|server: https://127.0.0.1:16443|' "${DEST}"
rm -f "${DEST}.bak"

echo ""
echo "Wrote ${DEST}."
echo ""
echo "Open the SSH tunnel in a separate terminal:"
echo "  ssh -L 16443:127.0.0.1:16443 -N ${HOMELAB_USER}@${HOST}"
echo ""
echo "Then verify:"
echo "  export KUBECONFIG=${DEST}"
echo "  kubectl get nodes"

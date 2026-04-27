#!/usr/bin/env bash
# install-cloudflared.sh — Install cloudflared on Ubuntu and configure for K8s-ref tunnel.
# Usage: ./scripts/install-cloudflared.sh
# Run on the homelab host. Idempotent.
set -euo pipefail

CLOUDFLARED_VERSION="2025.4.0"
ARCH=$(dpkg --print-architecture)  # amd64 or arm64

echo "==> Installing cloudflared ${CLOUDFLARED_VERSION} (${ARCH})"

if cloudflared version &>/dev/null; then
  echo "cloudflared already installed: $(cloudflared version)"
  exit 0
fi

curl -fsSL \
  "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-${ARCH}.deb" \
  -o /tmp/cloudflared.deb

sudo dpkg -i /tmp/cloudflared.deb
rm -f /tmp/cloudflared.deb

cloudflared version
echo "==> cloudflared installed successfully"

echo ""
echo "Next steps to create the K8s-ref tunnel:"
echo "  1. cloudflared tunnel login                            # opens browser, saves cert"
echo "  2. cloudflared tunnel create k8s-ref                  # creates tunnel, saves creds JSON"
echo "  3. Note the tunnel ID from the output (UUID)"
echo "  4. Create the K8s secret:"
echo "     kubectl create secret generic cloudflared-tunnel-creds \\"
echo "       --from-file=credentials.json=\$HOME/.cloudflared/<UUID>.json \\"
echo "       -n k8s-ref-demo"
echo "  5. In ArgoCD app values, set:"
echo "     cloudflared.enabled=true"
echo "     cloudflared.tunnelId=<UUID>"
echo "  6. Add DNS CNAME in Cloudflare dashboard:"
echo "     k8s-ref-a.prudentiadigital.co.za  CNAME  <UUID>.cfargotunnel.com"
echo "     k8s-ref-b.prudentiadigital.co.za  CNAME  <UUID>.cfargotunnel.com"

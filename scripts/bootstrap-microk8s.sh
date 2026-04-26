#!/usr/bin/env bash
# bootstrap-microk8s.sh — One-shot homelab MicroK8s bootstrap.
#
# Idempotent: safe to re-run. Each step checks current state before acting.
# Logs every action BEFORE doing it (per scripts/README.md conventions).
#
# Scope: MicroK8s install + required addons + kubectl alias + readiness check.
# Out of scope: ArgoCD install, app deployment — see docs/runbooks/m1-kickoff.md.
#
# Pre-requisite: Ubuntu 22.04+ host with snap, ≥8 GB RAM, internet access.
# Usage: ./scripts/bootstrap-microk8s.sh

set -euo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

log()   { printf "%b\n" "${CYAN}▸${NC} $*"; }
ok()    { printf "%b\n" "${GREEN}✓${NC} $*"; }
warn()  { printf "%b\n" "${YELLOW}!${NC} $*"; }
fail()  { printf "%b\n" "${RED}✗${NC} $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

# ────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ────────────────────────────────────────────────────────────────────────────
log "Pre-flight checks"

# OS check
if ! grep -qE "Ubuntu" /etc/os-release 2>/dev/null; then
  warn "Not running Ubuntu — script tested on Ubuntu 22.04+. Continuing."
fi

# RAM check (warn if < 6 GB free)
TOTAL_MEM_KB="$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))
if [[ "$TOTAL_MEM_GB" -lt 6 ]]; then
  warn "Total RAM is ${TOTAL_MEM_GB} GB — recommended ≥8 GB. Cluster + ArgoCD + observability stack will be tight."
else
  ok "RAM: ${TOTAL_MEM_GB} GB"
fi

# snap check
require_cmd snap
ok "snap available"

# Sudo check
if ! sudo -n true 2>/dev/null; then
  log "Sudo will prompt for password during install."
fi

# ────────────────────────────────────────────────────────────────────────────
# MicroK8s install
# ────────────────────────────────────────────────────────────────────────────
MICROK8S_CHANNEL="${MICROK8S_CHANNEL:-1.30/stable}"

if snap list microk8s >/dev/null 2>&1; then
  CURRENT_CHANNEL="$(snap info microk8s 2>/dev/null | awk '/tracking:/ {print $2}')"
  ok "MicroK8s already installed (tracking: ${CURRENT_CHANNEL})"
else
  log "Installing MicroK8s (channel ${MICROK8S_CHANNEL})..."
  sudo snap install microk8s --classic --channel="${MICROK8S_CHANNEL}"
  ok "MicroK8s installed"
fi

# User group (so kubectl works without sudo)
if ! id -nG "$USER" | grep -qw microk8s; then
  log "Adding ${USER} to microk8s group..."
  sudo usermod -a -G microk8s "$USER"
  sudo chown -R "$USER" ~/.kube 2>/dev/null || mkdir -p ~/.kube
  warn "You must log out and back in (or run 'newgrp microk8s') for group change to take effect."
  warn "Re-run this script after re-logging in to verify cluster status."
  exit 0
else
  ok "User ${USER} already in microk8s group"
fi

# ────────────────────────────────────────────────────────────────────────────
# Wait for cluster ready
# ────────────────────────────────────────────────────────────────────────────
log "Waiting for cluster ready (up to 5 min)..."
sudo microk8s status --wait-ready --timeout=300 >/dev/null
ok "Cluster ready"

# ────────────────────────────────────────────────────────────────────────────
# Enable addons
# ────────────────────────────────────────────────────────────────────────────
ADDONS=(
  "dns"               # CoreDNS — required by everything
  "hostpath-storage"  # Default StorageClass for PVCs (homelab only — never prod)
  "ingress"           # ingress-nginx
  "helm3"             # helm CLI shim
  "rbac"              # RBAC enforcement
  "metrics-server"    # for HPA + kubectl top
)

for addon in "${ADDONS[@]}"; do
  if microk8s status --addon "$addon" 2>/dev/null | grep -q "enabled"; then
    ok "Addon already enabled: $addon"
  else
    log "Enabling addon: $addon"
    microk8s enable "$addon"
    ok "Enabled: $addon"
  fi
done

# ────────────────────────────────────────────────────────────────────────────
# kubectl alias + kubeconfig export
# ────────────────────────────────────────────────────────────────────────────
KUBECONFIG_PATH="$HOME/.kube/config-microk8s"

log "Exporting kubeconfig to ${KUBECONFIG_PATH}"
mkdir -p "$HOME/.kube"
microk8s config > "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"
ok "Kubeconfig at ${KUBECONFIG_PATH}"

# Suggest shell alias (don't auto-modify rc files)
if ! command -v kubectl >/dev/null 2>&1; then
  warn "kubectl not in PATH. Either:"
  warn "  (a) install it system-wide: sudo snap install kubectl --classic"
  warn "  (b) use the MicroK8s shim:   alias kubectl='microk8s kubectl'"
fi

cat <<EOF

${GREEN}═══════════════════════════════════════════════════════════════════${NC}
${GREEN}  MicroK8s bootstrap complete${NC}
${GREEN}═══════════════════════════════════════════════════════════════════${NC}

Cluster info:
  Kubeconfig:  ${KUBECONFIG_PATH}
  Set in shell: ${YELLOW}export KUBECONFIG=${KUBECONFIG_PATH}${NC}
  Verify:       ${YELLOW}kubectl get nodes${NC}
  Or via shim:  ${YELLOW}microk8s kubectl get nodes${NC}

Next steps (per docs/runbooks/m1-kickoff.md):
  1. Install ArgoCD (Phase 2 of M1)
  2. Bootstrap App-of-Apps (Phase 3)
  3. Deploy first sample app (Phase 4)

EOF

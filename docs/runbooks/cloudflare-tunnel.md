# Runbook — Cloudflare Tunnel Setup (M1 W3)

> **Status:** Pre-staged. Cloudflared Deployment is committed but disabled (`cloudflared.enabled: false` in `values.yaml`). Enable once a tunnel is created and credentials injected.

## Prerequisites

- `cloudflared` CLI installed on the workstation (`scripts/install-cloudflared.sh` for the homelab host)
- Cloudflare account with access to the `prudentiadigital.co.za` zone
- `kubectl` pointing at the homelab cluster (`scripts/fetch-kubeconfig.sh`)
- ArgoCD syncing the `k8s-ref-demo` app

## Step 1 — Create the tunnel

```bash
cloudflared tunnel login          # opens browser; authenticates to your CF account
cloudflared tunnel create k8s-ref-demo
# Note the tunnel ID printed — you'll need it in step 3
```

Credentials file written to `~/.cloudflared/<tunnel-id>.json`.

## Step 2 — Inject credentials as a Kubernetes Secret

```bash
TUNNEL_ID=<tunnel-id>
kubectl create secret generic cloudflared-tunnel-creds \
  -n k8s-ref-demo \
  --from-file=credentials.json="$HOME/.cloudflared/${TUNNEL_ID}.json"
```

**Do not commit the credentials JSON to git.** A Vault ExternalSecret to manage this is scoped to M2 (see ADR-0003).

## Step 3 — Enable cloudflared in Helm values

Create or update an env-overlay `values-homelab.yaml` alongside the main chart:

```yaml
cloudflared:
  enabled: true
  tunnelId: "<tunnel-id>"
  # ingress rules are driven by tenants[].publicHost in values.yaml
```

Commit and push. ArgoCD will pick up the change and deploy the 2-replica cloudflared Deployment.

## Step 4 — Wire DNS

```bash
cloudflared tunnel route dns k8s-ref-demo k8s-ref-a.prudentiadigital.co.za
cloudflared tunnel route dns k8s-ref-demo k8s-ref-b.prudentiadigital.co.za
```

Cloudflare creates CNAME records pointing to `<tunnel-id>.cfargotunnel.com`.

## Step 5 — Verify

```bash
curl -s https://k8s-ref-a.prudentiadigital.co.za/healthz
# Expected: {"status":"ok"}
```

Screenshot the public URL response for portfolio item P7.

## Rollback

```bash
kubectl delete secret cloudflared-tunnel-creds -n k8s-ref-demo
# Set cloudflared.enabled: false in values, commit, ArgoCD syncs → Deployment removed
cloudflared tunnel delete k8s-ref-demo   # removes the tunnel from CF dashboard
```

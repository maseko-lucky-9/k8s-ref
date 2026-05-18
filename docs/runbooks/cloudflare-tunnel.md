# Cloudflare Tunnel — public exposure runbook

> **Status:** live in production (M1 W3, 2026-05-18).
> **Tunnel:** `k8s-ref-demo` · UUID `f2fbd78e-a9ed-48b1-b361-93361e440df4` · 4 edge connections across Cloudflare jnb01/jnb03/jnb04.
> **Public URLs:** `https://k8s-ref-a.prudentiadigital.co.za` · `https://k8s-ref-b.prudentiadigital.co.za`

## What this is

A zero-trust outbound tunnel from the homelab MicroK8s cluster to Cloudflare's edge. Two `cloudflared` pods run inside `k8s-ref-demo`, dial Cloudflare over QUIC, and route public requests for the two tenant hostnames back to the in-cluster `tenant-a` / `tenant-b` Services.

**No firewall ports opened on the homelab.** Outbound UDP/443 only. The cluster's API server, Vault, ArgoCD, Grafana, and every other namespace stay unreachable from the public internet.

```
public visitor
     │  HTTPS
     ▼
Cloudflare edge (TLS terminate)
     │  QUIC over UDP/443, outbound from cluster
     ▼
cloudflared pod (k8s-ref-demo)  ◀── ingress map in cloudflared-config CM
     │  cluster-internal HTTP
     ▼
tenant-a / tenant-b Service → podinfo Pod
```

## Routing — only the demo workloads are public

The tunnel's ingress map (`helm/charts/k8s-ref-demo/templates/cloudflared/configmap.yaml`) is **explicit allow-list**. Anything not listed falls through to `http_status:404`. Currently:

| Public hostname | Cluster Service |
|---|---|
| `k8s-ref-a.prudentiadigital.co.za` | `tenant-a.k8s-ref-demo.svc.cluster.local:80` |
| `k8s-ref-b.prudentiadigital.co.za` | `tenant-b.k8s-ref-demo.svc.cluster.local:80` |
| anything else | `http_status:404` |

**ArgoCD, Grafana, Vault are deliberately NOT in this map.** Adding admin UIs to the tunnel would re-introduce public attack surface; the screenshot bundle in `docs/portfolio-item-assets/` is the portfolio artifact for those.

## How it was set up (2026-05-18, one-shot)

Replay-safe — every step is idempotent or guarded.

### 0. Preflight

```bash
which cloudflared                                 # /opt/homebrew/bin/cloudflared (or apt-installed)
cloudflared --version                             # 2026.5.0 or newer
ls -la ~/.cloudflared/cert.pem                    # exists ⇒ already auth'd
                                                  # if not: `cloudflared tunnel login`
dig +short NS prudentiadigital.co.za              # carter.ns.cloudflare.com / sharon.ns.cloudflare.com
```

### 1. Create the tunnel + grab credentials

```bash
cloudflared tunnel create k8s-ref-demo
# → writes ~/.cloudflared/<UUID>.json (175-byte JSON; treat as secret)
cloudflared tunnel list      # confirm it appears
```

### 2. Stash credentials in-cluster

```bash
TUNNEL_UUID=<from-step-1>
kubectl create secret generic cloudflared-tunnel-creds \
  -n k8s-ref-demo \
  --from-file=credentials.json=$HOME/.cloudflared/$TUNNEL_UUID.json \
  --dry-run=client -o yaml | kubectl apply -f -
```

The Secret is consumed by the `cloudflared` Deployment (mounted at `/etc/cloudflared/creds/credentials.json`). Name of the Secret is configurable via `values.yaml` `cloudflared.credentialsSecret`.

### 3. Add DNS CNAMEs (Cloudflare-side, no manual dashboard work)

```bash
cloudflared tunnel route dns $TUNNEL_UUID k8s-ref-a.prudentiadigital.co.za
cloudflared tunnel route dns $TUNNEL_UUID k8s-ref-b.prudentiadigital.co.za
```

Each call creates a CNAME `<hostname> → <UUID>.cfargotunnel.com` and a proxied Cloudflare record. TLS certs are issued automatically (Cloudflare-managed) — verifiable via:

```bash
echo | openssl s_client -connect k8s-ref-a.prudentiadigital.co.za:443 -servername k8s-ref-a.prudentiadigital.co.za 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

### 4. Flip the Helm flag + commit

In `helm/charts/k8s-ref-demo/values.yaml`:

```yaml
cloudflared:
  enabled: true
  tunnelId: "<UUID-from-step-1>"
  imageTag: "2026.5.0"
  credentialsSecret: cloudflared-tunnel-creds
```

Commit on a feature branch, PR to main, merge — ArgoCD then reconciles the Deployment + ConfigMap from Git.

### 5. Verify

```bash
kubectl get pods -n k8s-ref-demo -l app=cloudflared       # 2/2 Running
cloudflared tunnel info $TUNNEL_UUID                       # 4 connector entries across edge POPs
curl -s https://k8s-ref-a.prudentiadigital.co.za/ | jq .  # podinfo JSON, hostname=tenant-a-*
```

P7 evidence captured at `docs/portfolio-item-assets/p7-cloudflare-tunnel-evidence.txt`.

## Operations

### Rotate the tunnel (compromise, key spill, etc.)

```bash
# Delete old tunnel + create fresh
cloudflared tunnel delete <old-UUID>
cloudflared tunnel create k8s-ref-demo
TUNNEL_UUID=<new-UUID>

# Replace in-cluster Secret
kubectl create secret generic cloudflared-tunnel-creds \
  -n k8s-ref-demo \
  --from-file=credentials.json=$HOME/.cloudflared/$TUNNEL_UUID.json \
  --dry-run=client -o yaml | kubectl apply -f -

# Re-route DNS
cloudflared tunnel route dns $TUNNEL_UUID k8s-ref-a.prudentiadigital.co.za
cloudflared tunnel route dns $TUNNEL_UUID k8s-ref-b.prudentiadigital.co.za

# Update values.yaml tunnelId + commit + PR
# ArgoCD will roll the cloudflared Deployment to pick up the new Secret
```

### Add a new public hostname

1. Add a tenant entry with `publicHost: <new>.prudentiadigital.co.za` in `values.yaml` (or edit `cloudflared/configmap.yaml` directly if it's a non-tenant Service).
2. `cloudflared tunnel route dns $TUNNEL_UUID <new>.prudentiadigital.co.za`.
3. Commit + PR. ArgoCD sync re-applies the ConfigMap; `cloudflared` reloads on the next pod restart (or `kubectl rollout restart deploy/cloudflared -n k8s-ref-demo` to force).

### Take the demo down (temporary)

```bash
# Soft: scale to 0 (DNS still points at tunnel, requests get connection-refused at the edge)
kubectl scale deploy/cloudflared -n k8s-ref-demo --replicas=0

# Hard: flip values.yaml cloudflared.enabled=false, commit, PR — ArgoCD prunes (currently prune=false on the App, so this requires manual delete)
```

### Take the demo down (permanent)

```bash
cloudflared tunnel delete <UUID>
kubectl delete secret cloudflared-tunnel-creds -n k8s-ref-demo
# Then flip values.yaml + commit + PR; the CNAMEs become orphaned (404 from edge) until removed via `cloudflared tunnel route dns --overwrite-dns` or the dashboard
```

## Failure modes & recovery

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods Ready but `cloudflared tunnel info` shows 0 connections | Credentials Secret missing or wrong UUID | `kubectl describe pod` for volume-mount errors; verify `values.yaml` `tunnelId` matches the Secret's JSON `TunnelID` |
| `curl` returns 530 from Cloudflare | DNS routed but tunnel offline | Pods crashlooping or rolled out without creds — check `kubectl logs` and the connector count |
| `curl` returns 404 | Hostname not in tunnel ingress map | Add to `cloudflared/configmap.yaml`, sync ArgoCD, `kubectl rollout restart` |
| Certs not auto-issued | Domain not delegated to Cloudflare | `dig NS <domain>` should show Cloudflare nameservers |
| `cloudflared` logs ICMP permission warnings | Container runs as non-root user (65532) | Cosmetic only — ICMP proxying is disabled, HTTP routing is unaffected |

## Decisions deferred to a follow-up ADR

- **Cloudflare Access** in front of admin UIs (ArgoCD, Grafana, Vault). Today they stay cluster-internal; if we ever need temporary public access for a demo call, Access (with OAuth/email-OTP) is the right gate — never a tunnel hostname without auth.
- **Wildcard hostname** vs. enumerated CNAMEs. Two CNAMEs is fine for two tenants; if the chart grows to 10+ tenants, switch to `*.prudentiadigital.co.za` + a Cloudflare DNS API call from the chart.

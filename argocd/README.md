# ArgoCD

> GitOps control plane for the cluster. Populated alongside M1.

## Layout (planned)

```
argocd/
├── bootstrap/          # Kustomization to install ArgoCD itself + bootstrap App-of-Apps
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── argocd-install.yaml
├── apps/               # ApplicationSet manifests (one per logical app group)
│   ├── infra-apps.yaml      # cert-manager, ESO, ingress-nginx, etc.
│   ├── observability.yaml   # kube-prometheus-stack, Loki, Tempo
│   └── workloads.yaml       # Sample multi-tenant SaaS workloads
└── README.md
```

## Bootstrap

```bash
kubectl apply -k argocd/bootstrap
```

After bootstrap completes, `argocd/apps/` ApplicationSets self-deploy via the App-of-Apps pattern.

## Conventions

- Every workload deployed via ArgoCD — nothing kubectl-applied directly
- Sync policy: automated with prune + self-heal disabled by default; enabled per-app where safe
- Sync waves used to enforce: namespaces → CRDs → operators → workloads

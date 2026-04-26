# Helm Charts

> Authored Helm charts for the sample multi-tenant SaaS workload + any internal apps. Populated alongside M4.

## Conventions

- One chart per directory: `helm/<chart-name>/`
- Chart standards: Helm 3.x, `apiVersion: v2`, semver versioning
- Each chart includes:
  - `Chart.yaml` with `description` and `type: application`
  - `values.yaml` with `# yaml-language-server: $schema=values.schema.json` header
  - `values.schema.json` for input validation
  - `templates/NOTES.txt` with post-install summary
  - `templates/tests/` with `helm test` smoke checks
  - `README.md` generated via `helm-docs`

## Lint + render commands

```bash
# Lint a chart
helm lint helm/<chart>

# Render with default values
helm template helm/<chart>

# Render with a specific values file
helm template helm/<chart> -f helm/<chart>/values-dev.yaml
```

## Distribution

Charts are consumed by ArgoCD — see `argocd/apps/` ApplicationSet manifests.

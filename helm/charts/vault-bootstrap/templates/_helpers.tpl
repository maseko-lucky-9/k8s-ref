{{/*
Common labels for vault-bootstrap resources.
*/}}
{{- define "vault-bootstrap.labels" -}}
app.kubernetes.io/name: vault-bootstrap
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: k8s-ref
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end }}

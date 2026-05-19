{{/*
Common labels for vault-init.
*/}}
{{- define "vault-init.labels" -}}
app.kubernetes.io/name: vault-init
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: k8s-ref
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

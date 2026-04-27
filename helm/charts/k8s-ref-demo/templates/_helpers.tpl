{{- define "k8s-ref-demo.labels" -}}
app.kubernetes.io/name: k8s-ref-demo
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

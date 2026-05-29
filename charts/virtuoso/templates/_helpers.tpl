{{- define "virtuoso.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "virtuoso.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "virtuoso.labels" -}}
app.kubernetes.io/name: {{ include "virtuoso.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "virtuoso.selectorLabels" -}}
app.kubernetes.io/name: {{ include "virtuoso.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the Secret that holds the DBA password — either the user-provided
existing Secret or the one this chart renders.
*/}}
{{- define "virtuoso.secretName" -}}
{{- if .Values.existingSecret -}}
{{- .Values.existingSecret -}}
{{- else -}}
{{- include "virtuoso.fullname" . -}}
{{- end -}}
{{- end -}}

{{- define "virtuoso.dbaPasswordKey" -}}
{{- default "DBA_PASSWORD" .Values.existingSecretKey -}}
{{- end -}}

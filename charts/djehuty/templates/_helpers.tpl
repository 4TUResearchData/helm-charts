{{/* Common name helpers */}}

{{- define "djehuty.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "djehuty.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Name of the bundled virtuoso subchart's Service / Deployment. Mirrors
charts/virtuoso/templates/_helpers.tpl `virtuoso.fullname` for the default
case (`<release>-virtuoso`); override via `virtuoso.fullnameOverride` if
the subchart's name template is customized.
*/}}
{{- define "djehuty.virtuoso.fullname" -}}
{{- if .Values.virtuoso.fullnameOverride -}}
{{- .Values.virtuoso.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default "virtuoso" .Values.virtuoso.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "djehuty.labels" -}}
app.kubernetes.io/name: {{ include "djehuty.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "djehuty.selectorLabels" -}}
app.kubernetes.io/name: {{ include "djehuty.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Name of the Secret backing the djehuty pod (env vars + file mounts).
Either the user-provided existing Secret or the one this chart renders.
*/}}
{{- define "djehuty.secretName" -}}
{{- if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- printf "%s-secrets" (include "djehuty.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
Resolved SPARQL endpoint URL. When the virtuoso subchart is bundled,
derive `http://<release>-virtuoso:<service.port>/sparql`; otherwise return
the explicit value the operator set under `rdfStore.sparqlUri`.
*/}}
{{- define "djehuty.sparqlUri" -}}
{{- if .Values.virtuoso.enabled -}}
{{- $port := default 8890 (dig "service" "port" 8890 .Values.virtuoso) -}}
{{- printf "http://%s:%v/sparql" (include "djehuty.virtuoso.fullname" .) $port -}}
{{- else -}}
{{- required "rdfStore.sparqlUri is required when virtuoso.enabled is false" .Values.rdfStore.sparqlUri -}}
{{- end -}}
{{- end -}}

{{- define "djehuty.sparqlUpdateUri" -}}
{{- if .Values.virtuoso.enabled -}}
{{- include "djehuty.sparqlUri" . -}}
{{- else -}}
{{- $u := .Values.rdfStore.sparqlUpdateUri -}}
{{- if $u -}}{{- $u -}}{{- else -}}{{- include "djehuty.sparqlUri" . -}}{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Build the full djehuty config dict.
- Auto-derives base-url from route/ingress when config.base-url is empty.
- Injects rdf-store from the resolved SPARQL endpoint(s) above.
*/}}
{{- define "djehuty.configJson" -}}
{{- $cfg := deepCopy .Values.config -}}
{{- if not (index $cfg "base-url") -}}
  {{- if and .Values.route.enabled .Values.route.host -}}
    {{- $scheme := "http" -}}
    {{- if .Values.route.tls.enabled -}}{{- $scheme = "https" -}}{{- end -}}
    {{- $_ := set $cfg "base-url" (printf "%s://%s" $scheme .Values.route.host) -}}
  {{- else if and .Values.ingress.enabled .Values.ingress.hosts -}}
    {{- $scheme := "http" -}}
    {{- if .Values.ingress.tls -}}{{- $scheme = "https" -}}{{- end -}}
    {{- $host := (first .Values.ingress.hosts).host -}}
    {{- $_ := set $cfg "base-url" (printf "%s://%s" $scheme $host) -}}
  {{- else -}}
    {{- $_ := set $cfg "base-url" (printf "http://localhost:%v" .Values.service.port) -}}
  {{- end -}}
{{- end -}}
{{- $rdf := dict
    "sparql-uri" (include "djehuty.sparqlUri" .)
    "sparql-update-uri" (include "djehuty.sparqlUpdateUri" .)
    "state-graph" .Values.rdfStore.stateGraph
-}}
{{- $_ := set $cfg "rdf-store" $rdf -}}
{{- /*
Side-loaded config fragments → djehuty `include:` array.
Walks config.includes[], emits one absolute path per (ref, key) into the
`include:` array on the rendered config. Existing user-supplied `include:`
entries (if any) are preserved and prepended.
*/ -}}
{{- $includes := list -}}
{{- with index $cfg "include" -}}{{- $includes = . -}}{{- end -}}
{{- range $idx, $inc := default (list) (index $cfg "includes") -}}
  {{- $name := default $inc.secret $inc.configMap -}}
  {{- if not $name -}}{{- fail (printf "config.includes[%d]: must set either 'configMap:' or 'secret:'" $idx) -}}{{- end -}}
  {{- if and $inc.configMap $inc.secret -}}{{- fail (printf "config.includes[%d]: set 'configMap:' OR 'secret:', not both" $idx) -}}{{- end -}}
  {{- if not $inc.keys -}}{{- fail (printf "config.includes[%s]: 'keys:' is required (list the files to include from this reference)" $name) -}}{{- end -}}
  {{- range $k := $inc.keys -}}
    {{- $includes = append $includes (printf "/etc/djehuty/config.d/%s/%s" $name $k) -}}
  {{- end -}}
{{- end -}}
{{- if $includes -}}{{- $_ := set $cfg "include" $includes -}}{{- end -}}
{{- /* The `includes:` meta-key is chart machinery, not djehuty config. */ -}}
{{- $_ := unset $cfg "includes" -}}
{{- dict "djehuty" $cfg | toJson -}}
{{- end -}}

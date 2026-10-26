{{- define "apps.syncPolicy" -}}
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
    # some CRDs are too big for the last-applied annotation of client side apply
    - ServerSideApply=true
  retry:
    limit: 10
    backoff:
      duration: 15s
      factor: 2
      maxDuration: 5m
{{- end }}

{{/* usage: include "apps.metadata" (list "name" wave) */}}
{{- define "apps.metadata" -}}
metadata:
  name: {{ index . 0 }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ index . 1 | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
{{- end }}

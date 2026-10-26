#!/usr/bin/env bash
# Creates the kind cluster, installs Argo CD and hands everything else to the root app.
# REPO_URL and REVISION choose where Argo CD reads this repository from.
set -euo pipefail

cd "$(dirname "$0")/.."

repo_url=${REPO_URL:-https://github.com/murops/forge-gitops.git}
revision=${REVISION:-main}
argocd_version=$(sed -n 's/^  argocd: //p' apps/values.yaml)

if ! kind get clusters | grep -qx forge; then
  kind create cluster --config bootstrap/kind.yaml
fi
kubectl config use-context kind-forge >/dev/null

# pods resolve keycloak.localhost to the gateway, so the OIDC issuer is the same URL the browser uses
corefile=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')
if ! grep -q keycloak.localhost <<<"$corefile"; then
  rule='    rewrite stop name exact keycloak.localhost public-gateway.envoy-gateway-system.svc.cluster.local answer auto'
  corefile=$(awk -v rule="$rule" '{print} /^[[:space:]]*ready$/ {print rule}' <<<"$corefile")
  kubectl -n kube-system create configmap coredns --from-literal=Corefile="$corefile" \
    --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n kube-system rollout restart deployment coredns
fi

# only the first install, after that Argo CD manages itself through the argocd Application
if ! helm -n argocd status argocd >/dev/null 2>&1; then
  helm install argocd argo-cd --repo https://argoproj.github.io/argo-helm \
    --version "$argocd_version" -n argocd --create-namespace \
    -f bootstrap/argocd-values.yaml --wait
fi

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $repo_url
    targetRevision: $revision
    path: apps
    helm:
      valuesObject:
        repoURL: $repo_url
        revision: $revision
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 10
      backoff:
        duration: 15s
        factor: 2
        maxDuration: 5m
EOF

password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
cat <<EOF

Argo CD is syncing the platform, the first sync takes a few minutes.

  Argo CD   http://argocd.localhost   admin / $password
  Keycloak  http://keycloak.localhost
  Forge     http://forge.localhost  http://homol.forge.localhost  http://desen.forge.localhost  (dev / dev)

kubectl -n argocd get applications -w
EOF

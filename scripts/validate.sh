#!/usr/bin/env bash
# Renders everything Argo CD would apply and validates it with kubeconform.
set -euo pipefail

cd "$(dirname "$0")/.."

kubeconform_image=${KUBECONFORM_IMAGE:-ghcr.io/yannh/kubeconform:v0.8.0}
# RENDER_DIR keeps the rendered manifests, e.g. for a security scan
if [[ -n "${RENDER_DIR:-}" ]]; then
  out=$RENDER_DIR
  mkdir -p "$out"
else
  out=$(mktemp -d)
  trap 'rm -rf "$out"' EXIT
fi

helm template root apps > "$out/apps.yaml"
for f in platform/*/*.yaml; do echo ---; cat "$f"; done > "$out/platform.yaml"

for env in environments/*/env.yaml; do
  dir=$(dirname "$env")
  name=$(basename "$dir")
  chart_version=$(sed -n 's/^chartVersion: //p' "$env")
  kubectl kustomize "$dir" > "$out/$name-deps.yaml"
  helm template forge oci://ghcr.io/murops/charts/forge --version "$chart_version" \
    -f environments/common-values.yaml -f "$dir/values.yaml" > "$out/$name.yaml"
  echo "rendered $name (chart $chart_version, image $(sed -n 's/^  tag: //p' "$dir/values.yaml"))"
done

for f in "$out"/*.yaml; do echo ---; cat "$f"; done | docker run --rm -i "$kubeconform_image" -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

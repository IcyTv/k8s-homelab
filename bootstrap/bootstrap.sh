#!/usr/bin/env bash
set -euo pipefail

require_binary() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' binary not found in PATH" >&2
    exit 1
  fi
}

require_binary kubectl
require_binary helm

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
RELEASE_NAME="${ARGOCD_RELEASE:-argocd}"
CHART_REPO="https://argoproj.github.io/argo-helm"
CHART_NAME="argo-cd"
CHART_VERSION="${ARGOCD_CHART_VERSION:-9.0.5}"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"

if ! helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "argocd"; then
  helm repo add argocd "$CHART_REPO" >/dev/null
fi
helm repo update argocd >/dev/null

VALUES_FILE="$(mktemp)"
trap 'rm -f "$VALUES_FILE"' EXIT

cat <<'EOF' >"$VALUES_FILE"
configs:
  params:
    server.insecure: true
redis:
  enabled: true
redisSecretInit:
  enabled: false
server:
  ingress:
    enabled: true
    ingressClassName: traefik
    hostname: argocd.icytv.de
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/service.serversscheme: http
    tls: false

  ingressGrpc:
    enabled: true
    hostname: grpc.argocd.icytv.de
    annotations:
      traefik.ingress.kubernetes.io/router.entrypoints: websecure
      traefik.ingress.kubernetes.io/service.serversscheme: http
    tls: false
EOF

helm upgrade --install "$RELEASE_NAME" argocd/"$CHART_NAME" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --version "$CHART_VERSION" \
  --values "$VALUES_FILE"

kubectl apply -f "$REPO_ROOT/bootstrap/root-app.yaml"

kubectl -n "$NAMESPACE" rollout status deployment/argocd-server --timeout=5m
kubectl -n "$NAMESPACE" rollout status statefulset/argocd-application-controller --timeout=5m

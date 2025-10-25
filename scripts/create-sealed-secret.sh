#!/usr/bin/env bash
set -euo pipefail

if ! command -v kubectl >/dev/null 2>&1; then
  echo "error: kubectl not found in PATH" >&2
  exit 1
fi

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "error: kubeseal not found in PATH" >&2
  echo "hint: install from https://github.com/bitnami-labs/sealed-secrets/releases" >&2
  exit 1
fi

if [[ $# -lt 3 ]]; then
  echo "usage: $(basename "$0") <namespace> <secret-name> key1=value1 [key2=value2 ...]" >&2
  exit 1
fi

SECRET_NAMESPACE="$1"
SECRET_NAME="$2"
shift 2

SECRET_ARGS=()
for pair in "$@"; do
  if [[ "$pair" != *=* ]]; then
    echo "error: invalid secret entry '$pair' (expected key=value)" >&2
    exit 1
  fi
  SECRET_ARGS+=("--from-literal=${pair}")
done

OUTPUT_DIR="${OUTPUT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/manifests}"
OUTPUT_FILE="${OUTPUT_FILE:-$OUTPUT_DIR/${SECRET_NAMESPACE}-${SECRET_NAME}.sealedsecret.yaml}"

mkdir -p "$(dirname "$OUTPUT_FILE")"

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$SECRET_NAMESPACE" \
  "${SECRET_ARGS[@]}" \
  --dry-run=client -o json |
  kubeseal --controller-namespace kube-system --controller-name sealed-secrets --format=yaml \
  >"$OUTPUT_FILE"

echo "sealed secret written to $OUTPUT_FILE"

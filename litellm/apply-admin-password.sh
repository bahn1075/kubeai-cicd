#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-litellm}"
DEPLOYMENT="${DEPLOYMENT:-litellm}"
SECRET_NAME="${SECRET_NAME:-litellm-ui-login}"
UI_USERNAME="${UI_USERNAME:-admin}"
PASSWORD="${1:-${UI_PASSWORD:-}}"

usage() {
  cat <<'EOF'
Usage:
  ./litellm/apply-admin-password.sh [PASSWORD]

Behavior:
  - Creates or updates a Kubernetes Secret for LiteLLM UI login
  - Injects UI_USERNAME / UI_PASSWORD into the LiteLLM deployment
  - Restarts the deployment and waits for rollout

Environment overrides:
  NAMESPACE=litellm
  DEPLOYMENT=litellm
  SECRET_NAME=litellm-ui-login
  UI_USERNAME=admin
  UI_PASSWORD=<password>

Examples:
  ./litellm/apply-admin-password.sh 'vkfrhd33'
  UI_PASSWORD='vkfrhd33' ./litellm/apply-admin-password.sh
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_cmd kubectl

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -z "$PASSWORD" ]]; then
  read -r -s -p "LiteLLM admin UI password: " PASSWORD
  echo
fi

if [[ -z "$PASSWORD" ]]; then
  echo "Password cannot be empty." >&2
  exit 1
fi

echo "Applying Secret ${SECRET_NAME} in namespace ${NAMESPACE}..."
kubectl -n "$NAMESPACE" create secret generic "$SECRET_NAME" \
  --from-literal=UI_USERNAME="$UI_USERNAME" \
  --from-literal=UI_PASSWORD="$PASSWORD" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Injecting secret refs into deployment/${DEPLOYMENT}..."
for _ in 1 2 3 4 5; do
  if kubectl -n "$NAMESPACE" set env "deployment/${DEPLOYMENT}" --from="secret/${SECRET_NAME}" >/dev/null; then
    break
  fi
  sleep 1
done

echo "Restarting deployment/${DEPLOYMENT}..."
kubectl -n "$NAMESPACE" rollout restart "deployment/${DEPLOYMENT}" >/dev/null

echo "Waiting for rollout to complete..."
kubectl -n "$NAMESPACE" rollout status "deployment/${DEPLOYMENT}" --timeout=180s

echo
echo "LiteLLM UI admin credentials applied."
echo "Username: ${UI_USERNAME}"
echo "Password: [hidden]"

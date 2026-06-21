#!/usr/bin/env bash
# Initialize a freshly-deployed OpenBao cluster that uses Transit auto-unseal.
#
# With auto-unseal, `operator init` produces *recovery* keys (not unseal keys). Store the
# recovery key shares and the initial root token OFFLINE (e.g. split among break-glass
# holders / a sealed secret manager). This script writes them to ./.secrets which is
# .gitignored — move them out of the repo immediately.
#
# Usage: scripts/bootstrap-init.sh <namespace> <release>
set -euo pipefail

NAMESPACE="${1:-secret-vault}"
RELEASE="${2:-openbao}"
POD="${RELEASE}-0"
OUT_DIR="./.secrets"
INIT_FILE="${OUT_DIR}/${RELEASE}-init.json"

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"

echo ">> Checking init status of ${POD} in ${NAMESPACE}..."
if kubectl exec -n "${NAMESPACE}" "${POD}" -- bao status -format=json 2>/dev/null \
    | grep -q '"initialized": true'; then
  echo "!! ${POD} already initialized. Aborting (will not re-init)."
  exit 1
fi

echo ">> Initializing with 5 recovery shares, threshold 3..."
kubectl exec -n "${NAMESPACE}" "${POD}" -- \
  bao operator init \
    -recovery-shares=5 \
    -recovery-threshold=3 \
    -format=json > "${INIT_FILE}"

chmod 600 "${INIT_FILE}"

echo ""
echo ">> Initialization complete. Recovery keys + root token written to:"
echo "     ${INIT_FILE}"
echo ""
echo "   With Transit auto-unseal, the other pods will unseal automatically once they"
echo "   join the Raft cluster. Verify:"
echo "     kubectl exec -n ${NAMESPACE} ${POD} -- bao status"
echo ""
echo "!! SECURITY: move ${INIT_FILE} out of this repo NOW. Distribute the recovery shares"
echo "   to separate break-glass holders and delete the local copy. Use the root token only"
echo "   to bootstrap auth (OIDC admin group), then REVOKE it:"
echo "     bao token revoke <root-token>"

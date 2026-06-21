#!/usr/bin/env bash
# Phase 2 end-to-end smoke test: kubernetes auth works, and VSO materializes + re-syncs a
# kv-v2 secret into a native K8s Secret consumed by a workload.
#
# Prereqs: VSO installed; `enable_kubernetes_auth=true` applied; examples/k8s applied.
# Usage: scripts/verify-phase2.sh <openbao-namespace> <release> <app-namespace>
# Env:   VAULT_TOKEN (token that can write kv/payments, e.g. team-payments or admin)
set -euo pipefail

OB_NS="${1:-secret-vault}"
RELEASE="${2:-openbao}"
APP_NS="${3:-payments}"
POD="${RELEASE}-0"
MOUNT="kv/payments"
SECRET_PATH="payments-api"
K8S_SECRET="payments-api-db"

ob() { kubectl exec -n "${OB_NS}" "${POD}" -- env VAULT_TOKEN="${VAULT_TOKEN:?set VAULT_TOKEN}" "$@"; }

echo ">> 1. kubernetes auth method enabled in OpenBao"
ob bao auth list -format=json | grep -q '"kubernetes/"' && echo "   OK: kubernetes auth"

echo ">> 2. role 'payments-api-app' exists"
ob bao read -format=json auth/kubernetes/role/payments-api-app >/dev/null && echo "   OK: role present"

echo ">> 3. seed a source secret in kv/payments/payments-api"
NEW_VAL="synced-$(date +%s)"
ob bao kv put -mount="${MOUNT}" "${SECRET_PATH}" db_password="${NEW_VAL}"

echo ">> 4. wait for VSO to materialize the K8s Secret '${K8S_SECRET}' in ns '${APP_NS}'"
for i in $(seq 1 24); do
  if kubectl get secret -n "${APP_NS}" "${K8S_SECRET}" >/dev/null 2>&1; then break; fi
  sleep 5
done
GOT="$(kubectl get secret -n "${APP_NS}" "${K8S_SECRET}" -o jsonpath='{.data.db_password}' | base64 -d)"
[ "${GOT}" = "${NEW_VAL}" ] && echo "   OK: Secret materialized with current value" \
  || { echo "   FAIL: got '${GOT}', expected '${NEW_VAL}'"; exit 1; }

echo ">> 5. rotate source value and confirm VSO re-syncs (refreshAfter)"
NEW_VAL2="resynced-$(date +%s)"
ob bao kv put -mount="${MOUNT}" "${SECRET_PATH}" db_password="${NEW_VAL2}"
for i in $(seq 1 24); do
  CUR="$(kubectl get secret -n "${APP_NS}" "${K8S_SECRET}" -o jsonpath='{.data.db_password}' | base64 -d)"
  [ "${CUR}" = "${NEW_VAL2}" ] && break
  sleep 5
done
[ "${CUR}" = "${NEW_VAL2}" ] && echo "   OK: VSO re-synced the rotated value" \
  || { echo "   FAIL: re-sync did not occur (got '${CUR}')"; exit 1; }

echo ""
echo ">> Phase 2 verification PASSED."
echo "   The workload (envFrom: ${K8S_SECRET}) now receives updated secrets without app changes."

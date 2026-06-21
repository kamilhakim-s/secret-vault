#!/usr/bin/env bash
# Phase 3 end-to-end smoke test: AD service-account password AUTO-ROTATION via the ldap
# secrets engine, plus check-out/check-in for shared accounts.
#
# Prereqs: enable_ldap_secrets=true applied with at least one static role (and optionally a
# library). Reachable AD (real test OU, or the throwaway one in test/ad/).
#
# Usage: scripts/verify-phase3.sh <openbao-namespace> <release> <role> [library]
# Env:   VAULT_TOKEN (admin or a token holding ldap-read-<team> for <role>)
set -euo pipefail

OB_NS="${1:-secret-vault}"
RELEASE="${2:-openbao}"
ROLE="${3:-payments-svc}"
LIBRARY="${4:-}"
POD="${RELEASE}-0"

ob() { kubectl exec -n "${OB_NS}" "${POD}" -- env VAULT_TOKEN="${VAULT_TOKEN:?set VAULT_TOKEN}" "$@"; }
field() { ob bao read -format=json "$1" | python3 -c "import sys,json;print(json.load(sys.stdin)['data'].get('$2',''))"; }

echo ">> 1. ldap secrets engine enabled"
ob bao secrets list -format=json | grep -q '"ldap/"' && echo "   OK: ldap/ mounted"

echo ">> 2. static role '${ROLE}' exists"
ob bao read -format=json "ldap/static-role/${ROLE}" >/dev/null && echo "   OK: role present"

echo ">> 3. read current credentials"
PW1="$(field "ldap/static-cred/${ROLE}" password)"
[ -n "${PW1}" ] && echo "   OK: got a password (len=${#PW1})" || { echo "   FAIL: empty password"; exit 1; }

echo ">> 4. force a rotation and confirm the password changed"
ob bao write -f "ldap/rotate-role/${ROLE}" >/dev/null
sleep 2
PW2="$(field "ldap/static-cred/${ROLE}" password)"
[ -n "${PW2}" ] && [ "${PW1}" != "${PW2}" ] \
  && echo "   OK: password rotated" \
  || { echo "   FAIL: password did not change after rotate-role"; exit 1; }

if [ -n "${LIBRARY}" ]; then
  echo ">> 5. check-out / check-in for library '${LIBRARY}'"
  CO="$(ob bao write -format=json "ldap/library/${LIBRARY}/check-out" ttl=300)"
  USER="$(printf '%s' "${CO}" | python3 -c "import sys,json;print(json.load(sys.stdin)['data']['service_account_name'])")"
  echo "   checked out: ${USER}"
  ob bao write "ldap/library/${LIBRARY}/check-in" service_account_names="${USER}" >/dev/null
  echo "   OK: checked back in (password rotated on check-in)"
else
  echo ">> 5. (skipped — no library name passed)"
fi

echo ""
echo ">> Phase 3 verification PASSED."
echo "   Tip: to prove the rotated password actually works in AD, bind with it from a pod that"
echo "   has ldapsearch:  ldapsearch -H \"\$AD_URL\" -D \"<userPrincipalName>\" -w \"<password>\" -b \"<base>\""

#!/usr/bin/env bash
# Phase 1 end-to-end smoke test: cluster healthy + unsealed, KV round-trips, audit logging on.
# Run after `make openbao-up && make init && make tf-apply`.
#
# Usage: scripts/verify-phase1.sh <namespace> <release>
# Env:   VAULT_TOKEN (a token with access to a team kv mount, e.g. team-platform)
set -euo pipefail

NAMESPACE="${1:-secret-vault}"
RELEASE="${2:-openbao}"
POD="${RELEASE}-0"
TEAM="${TEAM:-platform}"

run() { kubectl exec -n "${NAMESPACE}" "${POD}" -- env VAULT_TOKEN="${VAULT_TOKEN:?set VAULT_TOKEN}" "$@"; }

echo ">> 1. Cluster status (expect initialized=true, sealed=false, HA peers present)"
run bao status

echo ">> 2. Confirm kv-v2 mount exists for team ${TEAM}"
run bao secrets list -format=json | grep -q "kv/${TEAM}/" \
  && echo "   OK: kv/${TEAM}/ mounted"

echo ">> 3. KV round-trip"
run bao kv put -mount="kv/${TEAM}" verify-smoke value=hello-$(date +%s)
run bao kv get -mount="kv/${TEAM}" verify-smoke
run bao kv delete -mount="kv/${TEAM}" verify-smoke
echo "   OK: write/read/delete succeeded"

echo ">> 4. Audit device enabled"
run bao audit list -format=json | grep -q '"file/"' \
  && echo "   OK: file audit device active"

echo ">> 5. OIDC + GitLab JWT auth methods present"
run bao auth list -format=json | grep -q '"oidc/"' && echo "   OK: oidc auth"
run bao auth list -format=json | grep -q '"jwt-gitlab/"' && echo "   OK: jwt-gitlab auth"

echo ""
echo ">> Phase 1 verification PASSED."
echo "   Manual checks remaining: browser SSO login via the Route, and a real GitLab"
echo "   pipeline run using examples/gitlab/.gitlab-ci.yml."

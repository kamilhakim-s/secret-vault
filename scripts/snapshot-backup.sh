#!/usr/bin/env bash
# Take a Raft snapshot of the OpenBao cluster and upload it to object storage.
# This is the backbone of the DR strategy (OpenBao OSS has no cross-region replication).
#
# Run on a schedule (CronJob / OpenShift CronJob) with an automation token that holds
# the `read` capability on sys/storage/raft/snapshot (see policies/admin.hcl).
#
# Usage: scripts/snapshot-backup.sh <namespace> <release>
# Env:   VAULT_TOKEN (automation token), S3_BUCKET (e.g. s3://my-bucket/openbao)
set -euo pipefail

NAMESPACE="${1:-secret-vault}"
RELEASE="${2:-openbao}"
POD="${RELEASE}-0"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
SNAP="openbao-${TS}.snap"
S3_BUCKET="${S3_BUCKET:?set S3_BUCKET, e.g. s3://my-bucket/openbao}"

echo ">> Taking Raft snapshot from ${POD}..."
kubectl exec -n "${NAMESPACE}" "${POD}" -- \
  env VAULT_TOKEN="${VAULT_TOKEN:?set VAULT_TOKEN}" \
  bao operator raft snapshot save "/tmp/${SNAP}"

echo ">> Copying snapshot out of the pod..."
kubectl cp -n "${NAMESPACE}" "${POD}:/tmp/${SNAP}" "/tmp/${SNAP}"
kubectl exec -n "${NAMESPACE}" "${POD}" -- rm -f "/tmp/${SNAP}"

echo ">> Uploading to ${S3_BUCKET}/${SNAP}..."
aws s3 cp "/tmp/${SNAP}" "${S3_BUCKET}/${SNAP}" --sse aws:kms
rm -f "/tmp/${SNAP}"

echo ">> Done: ${S3_BUCKET}/${SNAP}"
echo "   Restore procedure: docs/runbooks/dr-snapshot-restore.md"

# Runbook — Disaster Recovery (Raft Snapshot Restore)

OpenBao OSS has no cross-region replication, so DR = **restore a Raft snapshot into a fresh
cluster**. Backups are produced two ways:
- **Automated:** the `openbao-raft-snapshot` CronJob
  ([deploy/backup/snapshot-cronjob.yaml](../../deploy/backup/snapshot-cronjob.yaml))
  authenticates via kubernetes auth (no stored creds) and writes snapshots to the
  `openbao-snapshots` PVC, with an optional offsite object-storage upload.
- **Manual / ad-hoc:** [`scripts/snapshot-backup.sh`](../../scripts/snapshot-backup.sh)
  (uses a `VAULT_TOKEN` and pushes to S3).

## Recovery objectives

- **RPO** = your snapshot interval (e.g. hourly → up to 1h of writes lost).
- **RTO** = time to stand up a cluster + restore (typically minutes). Drill it quarterly.

## Prerequisites for restore

- The latest snapshot from object storage.
- The **recovery keys** (auto-unseal cluster) OR unseal keys (Shamir cluster).
- The **same auto-unseal configuration** (Transit unsealer reachable / same KMS key), because
  the snapshot's data is encrypted with the original cluster's keyring. A force-restore to a
  cluster with a *different* seal requires the original recovery keys.

## Procedure

1. **Stand up a new cluster** (`make unsealer-up` if needed, `make openbao-up`). Do **not**
   `operator init` it — the restore brings the data.
   - If reusing the original unsealer/KMS, the new cluster can decrypt the restored data.
2. **Initialize just enough** to get a token, OR restore with `-force` using recovery keys.
3. **Restore the snapshot:**
   ```bash
   kubectl cp /tmp/openbao-<ts>.snap secret-vault/openbao-0:/tmp/restore.snap
   kubectl exec -n secret-vault openbao-0 -- \
     env VAULT_TOKEN=<token> bao operator raft snapshot restore -force /tmp/restore.snap
   ```
4. **Verify:**
   ```bash
   kubectl exec -n secret-vault openbao-0 -- bao status        # unsealed, active
   kubectl exec -n secret-vault openbao-0 -- bao secrets list   # mounts present
   kubectl exec -n secret-vault openbao-0 -- bao kv get -mount=kv/platform <known-key>
   ```
5. **Re-point clients** (GitLab `VAULT_ADDR`, VSO `VaultConnection`, Route) at the new
   cluster if the address changed.

## Post-restore

- Rotate the initial root token; confirm OIDC admin access works.
- Confirm audit devices are re-enabled and shipping to the SIEM.
- Take a fresh snapshot to establish a new baseline.

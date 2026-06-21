# Runbook — Quarterly DR Drill

A scheduled rehearsal of [dr-snapshot-restore.md](dr-snapshot-restore.md). Run quarterly in a
non-production cluster; record timings to confirm RPO/RTO targets are met.

## Pre-drill
- [ ] Confirm the snapshot CronJob has recent successful runs (`oc get jobs -n secret-vault`).
- [ ] Confirm recovery keys + the unsealer/KMS config are accessible to the drill operators.
- [ ] Pick the snapshot under test (latest, plus one ~24h old to test older restores).

## Drill
1. [ ] Stand up a fresh, isolated cluster (`make unsealer-up && make openbao-up`).
2. [ ] **Start the clock.**
3. [ ] Restore the snapshot (procedure in dr-snapshot-restore.md).
4. [ ] Verify: `bao status` unsealed/active; `bao secrets list` shows mounts; read a known
       KV key and a known LDAP static-cred.
5. [ ] Re-point a test client (a throwaway GitLab job or VSO instance) and confirm it reads.
6. [ ] **Stop the clock** → record RTO.

## Post-drill
- [ ] Compare RTO/RPO to targets; file follow-ups for any miss.
- [ ] Rotate the restored cluster's root token; confirm OIDC admin access.
- [ ] Tear down the drill cluster.
- [ ] Update this runbook with anything that surprised you.

## Compliance note (FIPS / replication gap)
OpenBao OSS has no cross-region replication and no FIPS-validated build. This snapshot/restore
drill IS the documented DR control. If a workload later mandates FIPS 140-3, evaluate Vault
Enterprise for that specific tier rather than reworking the whole platform.

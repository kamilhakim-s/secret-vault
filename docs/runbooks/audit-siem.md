# Runbook — Audit Logging & SIEM

## Devices

Two audit devices run together ([terraform/audit.tf](../../terraform/audit.tf)):

| Device | Path | Purpose |
| --- | --- | --- |
| `file` | `/openbao/audit/audit.log` (audit PVC) | Durable local record; the fail-safe. |
| `socket` | `tcp → vector-audit.logging.svc:9000` | Streams events to the SIEM forwarder. |

**Fail-safe behavior:** OpenBao completes a request only if **at least one** device logs it.
With both enabled, a SIEM/network outage on the socket device does not block operations
because the file device still succeeds. (Never run *only* a network device.)

## Bring-up order

1. Deploy the forwarder first — it must be reachable when the socket device is enabled:
   ```bash
   oc apply -f deploy/logging/vector-audit-forwarder.yaml
   ```
2. Enable the socket device:
   ```hcl
   enable_audit_socket  = true
   audit_socket_address = "vector-audit.logging.svc:9000"
   ```
   `make tf-apply`

## Forwarding to the SIEM

The Vector forwarder defaults to a `console` sink, so events flow to stdout and the platform
log pipeline (OpenShift Logging / Loki / EFK) carries them to the SIEM. To push directly to a
SIEM HEC endpoint, uncomment the `http` sink in
[vector-audit-forwarder.yaml](../../deploy/logging/vector-audit-forwarder.yaml) and supply the
endpoint/token via a Secret.

## Notes

- Sensitive values are **HMAC'd** in audit output by default (`log_raw=false`) — safe to ship.
- Rotate the file device log with logrotate or size-based rotation on the PVC; the file device
  reopens on `SIGHUP` (`bao audit` lifecycle) — see OpenBao docs.
- Verify both devices are active: `bao audit list` shows `file/` and `socket/`.

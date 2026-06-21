# Audit devices. Every request is logged with caller identity + path.
#
# Fail-safe model: OpenBao completes a request only if AT LEAST ONE audit device logs it
# successfully. Running two devices means a transient SIEM/network outage on the socket
# device does not block operations — the local file device still succeeds.
#
# Ordering: the socket device validates connectivity when enabled, so deploy the forwarder
# (deploy/logging/) BEFORE applying this. Gate it with var.enable_audit_socket until then.

variable "enable_audit_socket" {
  type        = bool
  default     = false
  description = "Enable the socket audit device that streams to the SIEM forwarder."
}

variable "audit_socket_address" {
  type        = string
  default     = "vector-audit.logging.svc:9000"
  description = "host:port of the in-cluster audit log forwarder."
}

# Durable local record on the audit PVC.
resource "vault_audit" "file" {
  type = "file"
  path = "file"
  options = {
    file_path = "/openbao/audit/audit.log"
  }
}

# Streams audit events to the forwarder, which ships them to the SIEM.
resource "vault_audit" "socket" {
  count = var.enable_audit_socket ? 1 : 0

  type = "socket"
  path = "socket"
  options = {
    address     = var.audit_socket_address
    socket_type = "tcp"
    # log_raw=false (default) keeps sensitive values HMAC'd in the audit stream.
  }

  # The file device should already be working as the fail-safe before adding the socket.
  depends_on = [vault_audit.file]
}

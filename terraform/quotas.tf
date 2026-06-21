# Phase 5 — resource quotas to protect the cluster from abuse / runaway clients.

variable "global_rate_limit_rps" {
  type        = number
  default     = 1000
  description = "Global request rate limit (requests/sec) across the cluster."
}

variable "global_max_leases" {
  type        = number
  default     = 100000
  description = "Global cap on the number of active leases."
}

# Global default rate limit. Add path-scoped overrides (e.g. tighter on auth/ login paths).
resource "vault_quota_rate_limit" "global" {
  name = "global"
  path = ""
  rate = var.global_rate_limit_rps
}

# Tighter rate limit on login endpoints to blunt credential-stuffing.
resource "vault_quota_rate_limit" "logins" {
  name           = "logins"
  path           = "auth/"
  rate           = 100
  block_interval = 60 # seconds to block a client that exceeds the rate
}

# Cap total active leases so a misbehaving consumer can't exhaust storage.
resource "vault_quota_lease_count" "global" {
  name      = "global"
  path      = ""
  max_leases = var.global_max_leases
}

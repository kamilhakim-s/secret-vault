# Phase 5 — internal PKI for service-to-service TLS issuance.
# Demonstrates a self-managed root CA + an issuing role. For production, prefer a root CA kept
# offline and an intermediate signed by it; this single-tier setup is the minimal viable form.

variable "enable_pki" {
  type    = bool
  default = false # flip to true in Phase 5
}

variable "pki_common_name" {
  type        = string
  default     = "secret-vault Internal Root"
  description = "Subject CN of the root CA."
}

variable "pki_allowed_domains" {
  type        = list(string)
  default     = ["svc.cluster.local", "secret-vault.svc"]
  description = "Domains the issuing role may sign certs for."
}

resource "vault_mount" "pki" {
  count                     = var.enable_pki ? 1 : 0
  path                      = "pki"
  type                      = "pki"
  description               = "Internal service-to-service TLS"
  default_lease_ttl_seconds = 86400      # 1 day
  max_lease_ttl_seconds     = 315360000  # 10 years (the root)
}

resource "vault_pki_secret_backend_root_cert" "root" {
  count       = var.enable_pki ? 1 : 0
  backend     = vault_mount.pki[0].path
  type        = "internal"
  common_name = var.pki_common_name
  ttl         = "315360000"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_config_urls" "urls" {
  count                   = var.enable_pki ? 1 : 0
  backend                 = vault_mount.pki[0].path
  issuing_certificates    = ["${var.openbao_addr}/v1/pki/ca"]
  crl_distribution_points = ["${var.openbao_addr}/v1/pki/crl"]
}

# Issuing role: short-lived leaf certs for internal services.
resource "vault_pki_secret_backend_role" "internal" {
  count            = var.enable_pki ? 1 : 0
  backend          = vault_mount.pki[0].path
  name             = "internal"
  allowed_domains  = var.pki_allowed_domains
  allow_subdomains = true
  allow_bare_domains = false
  max_ttl          = "2592000" # 30 days
  ttl              = "604800"  # 7 days default
  key_type         = "rsa"
  key_bits         = 2048
}

# Issue a cert at:  bao write pki/issue/internal common_name=foo.secret-vault.svc
# Consumers can use VSO's VaultPKISecret CR to keep a leaf cert + key synced into a Secret.

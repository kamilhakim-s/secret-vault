# Phase 3 — Active Directory service-account secrets with AUTOMATIC ROTATION.
#
# Uses the modern `ldap` secrets engine (the successor to the deprecated `ad` engine).
# Two capabilities:
#   1. Static roles  — OpenBao owns an AD service account's password and rotates it on a
#                      schedule (rotation_period). Apps fetch the current password on demand.
#   2. Check-out/in  — a shared LIBRARY of AD accounts; OpenBao hands one out exclusively,
#                      then rotates its password on check-in. Good for high-load shared use.

variable "enable_ldap_secrets" {
  type    = bool
  default = false # flip to true in Phase 3
}

variable "ad_binddn" {
  type        = string
  default     = ""
  description = "Privileged bind DN OpenBao uses to rotate other accounts' passwords."
}

variable "ad_bindpass" {
  type      = string
  default   = ""
  sensitive = true
}

variable "ad_url" {
  type        = string
  default     = ""
  description = "AD/LDAPS URL, e.g. ldaps://dc1.corp.example.com"
}

variable "ad_userdn" {
  type        = string
  default     = ""
  description = "Base DN where service accounts live, e.g. OU=ServiceAccounts,DC=corp,DC=example,DC=com"
}

# AD rejects password changes over plaintext, so use LDAPS (ldaps://) or StartTLS.
variable "ad_starttls" {
  type    = bool
  default = false
}

# TEST ONLY: trust a self-signed DC cert. Never enable against real AD.
variable "ad_insecure_tls" {
  type    = bool
  default = false
}

# role name -> the AD account it manages, its rotation cadence, and the owning team.
# `team` drives which ldap-read-<team> policy gets read access (see policies-ldap.tf).
variable "ad_static_roles" {
  type = map(object({
    dn              = string # full DN of the AD account
    username        = string # sAMAccountName
    rotation_period = number # seconds, e.g. 86400 for daily
    team            = string # owning team -> grants ldap-read-<team>
  }))
  default = {}
}

# Shared-account pools for check-out/check-in. `team` likewise scopes read access.
variable "ad_libraries" {
  type = map(object({
    team                         = string
    service_account_names        = list(string) # sAMAccountNames in the pool
    ttl                          = number        # max checkout lease (seconds)
    max_ttl                      = number
    disable_check_in_enforcement = optional(bool, false)
  }))
  default = {}
}

resource "vault_ldap_secret_backend" "ad" {
  count        = var.enable_ldap_secrets ? 1 : 0
  path         = "ldap"
  binddn       = var.ad_binddn
  bindpass     = var.ad_bindpass
  url          = var.ad_url
  userdn       = var.ad_userdn
  schema       = "ad"          # use AD password attributes (unicodePwd)
  starttls     = var.ad_starttls
  insecure_tls = var.ad_insecure_tls
  description  = "AD service-account credentials with automatic rotation"
}

# Static roles: OpenBao rotates each account's password every rotation_period.
resource "vault_ldap_secret_backend_static_role" "sa" {
  for_each = var.enable_ldap_secrets ? var.ad_static_roles : {}

  mount           = vault_ldap_secret_backend.ad[0].path
  role_name       = each.key
  username        = each.value.username
  dn              = each.value.dn
  rotation_period = each.value.rotation_period
}

# Check-out/check-in libraries: a pool of interchangeable shared AD accounts. OpenBao hands
# one out exclusively and rotates its password on check-in.
resource "vault_ldap_secret_backend_library_set" "pool" {
  for_each = var.enable_ldap_secrets ? var.ad_libraries : {}

  mount                        = vault_ldap_secret_backend.ad[0].path
  name                         = each.key
  service_account_names        = each.value.service_account_names
  ttl                          = each.value.ttl
  max_ttl                      = each.value.max_ttl
  disable_check_in_enforcement = each.value.disable_check_in_enforcement
}

# Consumption paths (granted per team via ldap-read-<team>, see policies-ldap.tf):
#   read   ldap/static-cred/<role>           -> current username + password
#   update ldap/rotate-role/<role>           -> force immediate rotation
#   update ldap/library/<set>/check-out      -> borrow a shared account
#   update ldap/library/<set>/check-in       -> return it (triggers rotation)
#   read   ldap/library/<set>/status         -> see availability

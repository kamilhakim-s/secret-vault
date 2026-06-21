# Human SSO into the built-in OpenBao UI via OIDC.
# IdP groups are mapped to OpenBao external groups, which carry the team self-service policy.

resource "vault_jwt_auth_backend" "oidc" {
  path               = "oidc"
  type               = "oidc"
  oidc_discovery_url = var.oidc_discovery_url
  oidc_client_id     = var.oidc_client_id
  oidc_client_secret = var.oidc_client_secret
  default_role       = "default"

  tune {
    listing_visibility = "unauth" # show the OIDC button on the UI login screen
  }
}

# Default role used by the UI login flow. Group membership (below) grants the real policies;
# the role itself only establishes identity + the group claim mapping.
resource "vault_jwt_auth_backend_role" "default" {
  backend   = vault_jwt_auth_backend.oidc.path
  role_name = "default"
  role_type = "oidc"

  user_claim            = "sub"
  groups_claim          = var.oidc_group_claim
  oidc_scopes           = ["openid", "profile", "email", "groups"]
  allowed_redirect_uris = [
    # OpenShift Route / UI callback. Replace host per environment.
    "https://openbao.apps.example.com/ui/vault/auth/oidc/oidc/callback",
    "https://openbao.apps.example.com/oidc/callback",
    # Local CLI login.
    "http://localhost:8250/oidc/callback",
  ]

  token_policies = ["default"]
  token_ttl      = 3600
  token_max_ttl  = 28800
}

# External groups: map IdP group -> OpenBao group -> team policy.
resource "vault_identity_group" "team" {
  for_each = var.oidc_group_to_team

  name = each.key
  type = "external"
  policies = compact([
    "team-${each.value}",
    contains(tolist(local.ldap_teams), each.value) ? "ldap-read-${each.value}" : "",
  ])

  depends_on = [vault_policy.team, vault_policy.ldap_read]
}

resource "vault_identity_group_alias" "team" {
  for_each = var.oidc_group_to_team

  name           = each.key # must match the value emitted in the IdP groups claim
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.team[each.key].id
}

# Admin group.
resource "vault_identity_group" "admin" {
  name     = var.oidc_admin_group
  type     = "external"
  policies = ["secret-vault-admin"]

  depends_on = [vault_policy.admin]
}

resource "vault_identity_group_alias" "admin" {
  name           = var.oidc_admin_group
  mount_accessor = vault_jwt_auth_backend.oidc.accessor
  canonical_id   = vault_identity_group.admin.id
}

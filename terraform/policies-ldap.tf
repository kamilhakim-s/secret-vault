# Per-team read policies for AD (LDAP) credentials, generated from the static roles and
# library sets each team owns. Attached to that team's OIDC group, GitLab CI roles, and
# Kubernetes workload roles (see auth-oidc.tf / auth-gitlab-jwt.tf / auth-kubernetes.tf).

locals {
  # team -> [role names it owns]  and  team -> [library set names it owns]
  ldap_static_by_team = {
    for t in var.teams : t => [for k, v in var.ad_static_roles : k if v.team == t]
  }
  ldap_lib_by_team = {
    for t in var.teams : t => [for k, v in var.ad_libraries : k if v.team == t]
  }

  # Teams that actually have AD resources AND have the engine enabled. Empty when LDAP is off,
  # so nothing references a policy that wasn't created.
  ldap_teams = var.enable_ldap_secrets ? toset([
    for t in var.teams : t
    if length(local.ldap_static_by_team[t]) > 0 || length(local.ldap_lib_by_team[t]) > 0
  ]) : toset([])
}

resource "vault_policy" "ldap_read" {
  for_each = local.ldap_teams

  name = "ldap-read-${each.value}"
  policy = join("\n", concat(
    [
      for r in local.ldap_static_by_team[each.value] : <<-EOT
        path "ldap/static-cred/${r}" { capabilities = ["read"] }
        path "ldap/rotate-role/${r}" { capabilities = ["update"] }
      EOT
    ],
    [
      for l in local.ldap_lib_by_team[each.value] : <<-EOT
        path "ldap/library/${l}/check-out" { capabilities = ["update"] }
        path "ldap/library/${l}/check-in"  { capabilities = ["update"] }
        path "ldap/library/${l}/status"    { capabilities = ["read"] }
      EOT
    ],
  ))
}

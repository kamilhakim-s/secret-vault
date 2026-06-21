# GitLab CI/CD authentication via OIDC ID tokens (JWT auth method).
# Each pipeline job mints a short-lived id_token; OpenBao verifies it against GitLab's
# OIDC discovery endpoint and issues a job-scoped token. No credentials are stored in GitLab.

resource "vault_jwt_auth_backend" "gitlab" {
  path               = "jwt-gitlab"
  type               = "jwt"
  oidc_discovery_url = var.gitlab_issuer
  bound_issuer       = var.gitlab_issuer
}

# One role per project. Bound claims pin the role to a specific project so a leaked token
# from another project cannot assume it. Reads are limited to the team's ci-read policy.
resource "vault_jwt_auth_backend_role" "gitlab_project" {
  for_each = var.gitlab_projects

  backend        = vault_jwt_auth_backend.gitlab.path
  role_name      = each.key
  role_type      = "jwt"
  user_claim     = "project_path"
  bound_audiences = [var.gitlab_issuer]

  # Pin to the exact project. Add ref/ref_type/environment claims for tighter scoping
  # (e.g. only protected branches or a specific deploy environment).
  bound_claims_type = "glob"
  bound_claims = {
    project_path = each.value.project_path
  }

  token_policies = compact([
    "ci-read-${each.value.team}",
    contains(tolist(local.ldap_teams), each.value.team) ? "ldap-read-${each.value.team}" : "",
  ])
  token_explicit_max_ttl = 600   # job-scoped; hard cap regardless of renewals
  token_ttl          = 300
  token_num_uses     = 0

  depends_on = [vault_policy.ci_read, vault_policy.ldap_read]
}

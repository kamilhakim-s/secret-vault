# Team / tenant definitions. In Phase 4 each team also gets its own namespace; for the
# MVP we use per-team kv-v2 mounts and policies in the root namespace.
variable "teams" {
  type = set(string)
  default = [
    "platform",
    "payments",
  ]
  description = "Teams that get an isolated kv-v2 mount and self-service policy."
}

# ---- OIDC (human SSO) ----
variable "oidc_discovery_url" {
  type        = string
  description = "IdP OIDC discovery URL (e.g. https://login.microsoftonline.com/<tenant>/v2.0 or Keycloak realm)."
}

variable "oidc_client_id" {
  type      = string
  sensitive = true
}

variable "oidc_client_secret" {
  type      = string
  sensitive = true
}

variable "oidc_group_claim" {
  type        = string
  default     = "groups"
  description = "Token claim that carries the user's group membership."
}

# Map IdP group name -> OpenBao team. Members of the group get the team's self-service policy.
variable "oidc_group_to_team" {
  type = map(string)
  default = {
    "secret-vault-platform" = "platform"
    "secret-vault-payments" = "payments"
  }
}

# IdP group that should receive the admin policy.
variable "oidc_admin_group" {
  type    = string
  default = "secret-vault-admins"
}

# ---- GitLab ----
variable "gitlab_issuer" {
  type        = string
  description = "GitLab instance base URL used as the OIDC issuer (e.g. https://gitlab.example.com)."
}

# Per-project GitLab CI access: project_path -> kv path it may read.
variable "gitlab_projects" {
  type = map(object({
    project_path = string # e.g. "mygroup/myapp"
    team         = string # which team's kv mount it reads from
  }))
  default = {}
}

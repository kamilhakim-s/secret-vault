# Renders least-privilege policies from the templates in ./policies and registers them.

# Per-team self-service policy: full control over its own kv mount, read-only on cubbyhole.
resource "vault_policy" "team" {
  for_each = var.teams

  name = "team-${each.value}"
  policy = templatefile("${path.module}/policies/team.hcl.tpl", {
    team = each.value
  })
}

# Admin policy for the platform operators (sys mounts, policies, auth config).
resource "vault_policy" "admin" {
  name   = "secret-vault-admin"
  policy = file("${path.module}/policies/admin.hcl")
}

# Read-only policy used by GitLab CI roles (scoped further per-project via the role).
resource "vault_policy" "ci_read" {
  for_each = var.teams

  name = "ci-read-${each.value}"
  policy = templatefile("${path.module}/policies/ci-read.hcl.tpl", {
    team = each.value
  })
}

# Policy for the automated Raft snapshot CronJob (Phase 4 DR).
resource "vault_policy" "snapshot" {
  name   = "raft-snapshot"
  policy = file("${path.module}/policies/snapshot.hcl")
}

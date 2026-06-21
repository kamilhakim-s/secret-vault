# One versioned kv-v2 mount per team: kv/<team>.
resource "vault_mount" "kv" {
  for_each = var.teams

  path        = "kv/${each.value}"
  type        = "kv"
  options     = { version = "2" }
  description = "Key/Value (v2) secrets for team ${each.value}"
}

# Audit devices live in audit.tf.

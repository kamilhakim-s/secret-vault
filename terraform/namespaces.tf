# Phase 4 — per-team namespaces for hard multi-tenant isolation (free in OpenBao).
#
# NOTE: namespaces are a structural change — each team's mounts, policies, auth roles, and
# identity groups move INSIDE its namespace. When you adopt this, set `namespace = ...` on
# the per-team provider/resources (use provider aliases or separate Terraform workspaces per
# namespace). The MVP keeps everything in the root namespace; this file enables the cutover.

variable "enable_namespaces" {
  type    = bool
  default = false # flip to true in Phase 4
}

resource "vault_namespace" "team" {
  for_each = var.enable_namespaces ? var.teams : []
  path     = each.value
}

# Example pattern for namespaced resources (apply via an aliased provider per namespace):
#
#   provider "vault" {
#     alias     = "payments"
#     address   = var.openbao_addr
#     namespace = "payments"
#   }
#
#   resource "vault_mount" "kv_payments" {
#     provider = vault.payments
#     path     = "kv"
#     type     = "kv"
#     options  = { version = "2" }
#   }

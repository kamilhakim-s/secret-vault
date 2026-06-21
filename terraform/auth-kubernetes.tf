# Phase 2 — Kubernetes auth method for in-cluster workloads (and the Vault Secrets Operator).
# Workloads present their projected ServiceAccount token; OpenBao verifies it via TokenReview.
#
# Requires the auth-delegator ClusterRoleBinding in deploy/openshift/auth-delegator-rbac.yaml.

variable "enable_kubernetes_auth" {
  type    = bool
  default = false # flip to true in Phase 2
}

# Per-app bindings: serviceaccount + namespace -> which team kv it may read.
variable "k8s_workloads" {
  type = map(object({
    service_account = string
    namespace       = string
    team            = string
  }))
  default = {}
}

resource "vault_auth_backend" "kubernetes" {
  count = var.enable_kubernetes_auth ? 1 : 0
  type  = "kubernetes"
  path  = "kubernetes"
}

# When OpenBao runs inside the same cluster, it can use the local SA token + CA and the
# in-cluster API host, so no static credentials are needed (token_reviewer_jwt omitted).
resource "vault_kubernetes_auth_backend_config" "this" {
  count                = var.enable_kubernetes_auth ? 1 : 0
  backend              = vault_auth_backend.kubernetes[0].path
  kubernetes_host      = "https://kubernetes.default.svc"
  disable_local_ca_jwt = false
}

resource "vault_kubernetes_auth_backend_role" "workload" {
  for_each = var.enable_kubernetes_auth ? var.k8s_workloads : {}

  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = each.key
  bound_service_account_names      = [each.value.service_account]
  bound_service_account_namespaces = [each.value.namespace]
  token_policies = compact([
    "ci-read-${each.value.team}", # read-only on the team's kv
    contains(tolist(local.ldap_teams), each.value.team) ? "ldap-read-${each.value.team}" : "",
  ])
  token_ttl = 1200

  depends_on = [vault_policy.ci_read, vault_policy.ldap_read]
}

# Role for the automated Raft snapshot CronJob — credential-free auth from in-cluster.
variable "snapshot_namespace" {
  type    = string
  default = "secret-vault"
}

resource "vault_kubernetes_auth_backend_role" "snapshot" {
  count = var.enable_kubernetes_auth ? 1 : 0

  backend                          = vault_auth_backend.kubernetes[0].path
  role_name                        = "raft-snapshot"
  bound_service_account_names      = ["openbao-snapshot"]
  bound_service_account_namespaces = [var.snapshot_namespace]
  token_policies                   = ["raft-snapshot"]
  token_ttl                        = 600

  depends_on = [vault_policy.snapshot]
}

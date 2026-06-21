# Platform operator policy. Broad, but intentionally NOT root:
# excludes raw sys/raw, and unseal/seal key operations (those stay with break-glass holders).

# Manage secrets engines.
path "sys/mounts" {
  capabilities = ["read", "list"]
}
path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage auth methods.
path "sys/auth" {
  capabilities = ["read", "list"]
}
path "sys/auth/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
path "auth/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage policies.
path "sys/policies/acl" {
  capabilities = ["list"]
}
path "sys/policies/acl/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Manage namespaces (Phase 4).
path "sys/namespaces/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Identity (OIDC groups/aliases).
path "identity/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Operate on all team kv mounts for support.
path "kv/+/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
path "kv/+/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Health, leases, audit, raft operations.
path "sys/health" {
  capabilities = ["read", "sudo"]
}
path "sys/leases/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "sys/audit" {
  capabilities = ["read", "list"]
}
path "sys/audit/*" {
  capabilities = ["create", "read", "update", "delete", "sudo"]
}
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

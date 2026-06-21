# Self-service policy for team "${team}".
# Full lifecycle over the team's own kv-v2 mount; nothing else.

# kv-v2 data + metadata live under data/ and metadata/ sub-paths.
path "kv/${team}/data/*" {
  capabilities = ["create", "read", "update", "patch", "delete"]
}

path "kv/${team}/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# Allow listing the mount in the UI.
path "kv/${team}/*" {
  capabilities = ["list"]
}

# Let users manage their own token + see their capabilities (UI niceties).
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
path "sys/capabilities-self" {
  capabilities = ["update"]
}

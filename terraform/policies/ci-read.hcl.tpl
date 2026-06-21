# Read-only policy for GitLab CI jobs of team "${team}".
# Reading is restricted to the team's kv mount; the GitLab JWT role additionally binds the
# specific project so one team's pipeline cannot read another team's secrets.

path "kv/${team}/data/*" {
  capabilities = ["read"]
}

path "kv/${team}/metadata/*" {
  capabilities = ["read", "list"]
}

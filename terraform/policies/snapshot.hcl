# Minimal policy for the automated Raft snapshot job. Read = take-a-snapshot here.
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

# Runbook — AD Secrets & Automatic Rotation

Engine: `ldap` secrets engine in `ad` schema (Terraform: `terraform/secrets-ldap.tf`,
`enable_ldap_secrets = true`).

## Concepts

| Mode | Use when | Behavior |
| --- | --- | --- |
| **Static role** | A specific AD service account, owned by OpenBao | OpenBao rotates its password every `rotation_period`; apps read the *current* password on demand. |
| **Check-out / check-in** | A pool of interchangeable shared accounts | OpenBao hands out one account exclusively; rotates its password on check-in. |

Static roles can be **root-managed** (the privileged `binddn` changes other accounts'
passwords) or **self-managed** (the account rotates its own password — no elevated bind
needed). The `ad_binddn`/`ad_bindpass` here drive root-managed rotation.

## Configure a static role (Terraform)

```hcl
ad_static_roles = {
  "payments-svc" = {
    dn              = "CN=svc-payments,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
    username        = "svc-payments"
    rotation_period = 86400        # rotate daily
    team            = "payments"   # owning team
  }
}
```

Read access is **generated automatically**: the `team` field produces an `ldap-read-<team>`
policy ([terraform/policies-ldap.tf](../../terraform/policies-ldap.tf)) that grants `read` on
`ldap/static-cred/<role>` and `update` on `ldap/rotate-role/<role>`. That policy is attached
to the team's OIDC group, its GitLab CI roles, and its Kubernetes workload roles — so humans
and pipelines and pods all get access without hand-editing policies.

## Configure a check-out/check-in library (Terraform)

```hcl
ad_libraries = {
  "payments-batch" = {
    team                  = "payments"
    service_account_names = ["svc-batch-1", "svc-batch-2"]
    ttl                   = 3600
    max_ttl               = 14400
  }
}
```

## Daily operations

- **Read current creds:** `bao read ldap/static-cred/payments-svc`
- **Force a rotation now:** `bao write -f ldap/rotate-role/payments-svc`
- **Check rotation status:** the read above returns `last_password` and `ttl`/next rotation.
- **In the UI:** the LDAP mount shows each static role, current username, and a *Rotate*
  action — this is the developer-facing surface of the feature.

## Verify (test env)

1. Point at a throwaway **Samba AD DC** (or a test OU in real AD).
2. Apply a static role with a short `rotation_period` (e.g. 60s).
3. Confirm the AD password changes (bind with the value returned by `static-cred`).
4. Confirm an app authenticates with the rotated password *after* rotation (re-read creds).
5. For check-out: `bao write ldap/library/<set>/check-out` returns a unique account; after
   `check-in`, confirm its password rotated.

## Failure handling

- Rotation failures surface in telemetry/audit. Common causes: `binddn` lacks permission to
  reset the target account, LDAPS cert not trusted, or account locked. The previous password
  remains valid until a successful rotation, so reads don't break mid-incident.

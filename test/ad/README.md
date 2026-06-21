# Throwaway test AD (Phase 3)

A disposable Samba AD Domain Controller for exercising AD password auto-rotation **without a
real directory**. Test-only — see the warnings in [samba-ad-dc.yaml](samba-ad-dc.yaml).

## 1. Deploy

```bash
oc apply -f test/ad/samba-ad-dc.yaml
# OpenShift only — Samba AD DC needs elevated privileges:
oc adm policy add-scc-to-user anyuid -z samba-ad -n test-ad
oc rollout status deploy/samba-ad -n test-ad
```

## 2. Seed an OU + service accounts

Exec into the pod and use `samba-tool` to create the OU, a bind account for OpenBao, and the
managed service account(s):

```bash
POD=$(oc get pod -n test-ad -l app=samba-ad -o name)
oc exec -n test-ad "$POD" -- bash -lc '
  samba-tool ou create "OU=ServiceAccounts,DC=corp,DC=example,DC=com" || true
  # Bind account OpenBao uses to reset other accounts (root-managed rotation):
  samba-tool user create svc-openbao "Bind123!Bind123!" \
    --userou="OU=ServiceAccounts" || true
  # Managed service account for the static role:
  samba-tool user create svc-payments "Init123!Init123!" \
    --userou="OU=ServiceAccounts" || true
  # Give the bind account rights to reset passwords (test shortcut: Domain Admins):
  samba-tool group addmembers "Domain Admins" svc-openbao || true
'
```

## 3. Point OpenBao at it (terraform.tfvars)

```hcl
enable_ldap_secrets = true
ad_url          = "ldaps://samba-ad.test-ad.svc:636"
ad_insecure_tls = true   # TEST ONLY — self-signed DC cert
ad_binddn       = "CN=svc-openbao,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
ad_bindpass     = "Bind123!Bind123!"
ad_userdn       = "OU=ServiceAccounts,DC=corp,DC=example,DC=com"

ad_static_roles = {
  "payments-svc" = {
    dn              = "CN=svc-payments,OU=ServiceAccounts,DC=corp,DC=example,DC=com"
    username        = "svc-payments"
    rotation_period = 60          # fast rotation for the test
    team            = "payments"
  }
}
```

Apply: `make tf-apply`

## 4. Verify

```bash
VAULT_TOKEN=<admin-token> make verify-phase3
# or with a library set:
# VAULT_TOKEN=<token> ./scripts/verify-phase3.sh secret-vault openbao payments-svc payments-batch
```

## 5. Tear down

```bash
oc delete -f test/ad/samba-ad-dc.yaml
```

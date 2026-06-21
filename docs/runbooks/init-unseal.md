# Runbook — Initialization & Unseal

## Model

The cluster uses **Transit auto-unseal** backed by the separate `openbao-unsealer` instance.
Pods unseal automatically on restart. `operator init` therefore produces **recovery keys**
(used for root-token regeneration and recovery operations), not unseal keys.

## One-time bootstrap order

1. **Deploy the unsealer** (`make unsealer-up`), then init it (it uses Shamir):
   ```bash
   kubectl exec -n secret-vault openbao-unsealer-0 -- bao operator init \
     -key-shares=3 -key-threshold=2 -format=json > .secrets/unsealer-init.json
   # unseal the unsealer with 2 of the 3 shares
   kubectl exec -n secret-vault openbao-unsealer-0 -- bao operator unseal <share-1>
   kubectl exec -n secret-vault openbao-unsealer-0 -- bao operator unseal <share-2>
   ```
2. **Create the Transit wrapping key** on the unsealer and a scoped token:
   ```bash
   bao secrets enable transit
   bao write -f transit/keys/autounseal
   bao policy write autounseal - <<'EOF'
   path "transit/encrypt/autounseal" { capabilities = ["update"] }
   path "transit/decrypt/autounseal" { capabilities = ["update"] }
   EOF
   bao token create -policy=autounseal -period=24h -orphan -field=token
   ```
3. **Store the token** for the main cluster:
   ```bash
   oc create secret generic openbao-unseal-token \
     --from-literal=token=<token-from-step-2> -n secret-vault
   ```
4. **Deploy the main cluster** (`make openbao-up`) and **init it** (`make init`).

## Recovery keys handling

- `make init` writes `.secrets/<release>-init.json` (gitignored). **Move it out of the repo
  immediately.**
- Split the 5 recovery shares among separate break-glass holders (threshold 3).
- Use the initial **root token** only to confirm OIDC admin-group access, then **revoke it**:
  `bao token revoke <root-token>`. Day-2 admin is via OIDC → `secret-vault-admin` policy.

## Verify

```bash
kubectl exec -n secret-vault openbao-0 -- bao status   # Sealed: false, HA Mode: active/standby
```

## If a pod comes up sealed

Auto-unseal failed to reach the unsealer. Check:
- `openbao-unseal-token` Secret exists and the token is not expired/revoked.
- The unsealer pod is unsealed and reachable (NetworkPolicy, TLS CA in `unsealer-ca`).
- Logs: `kubectl logs -n secret-vault openbao-0`.

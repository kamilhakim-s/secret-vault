# Vault Secrets Operator (VSO) — Phase 2

VSO watches CRs and materializes OpenBao secrets into native Kubernetes/OpenShift `Secret`
objects, keeping them in sync. Workloads consume the resulting `Secret` as env vars or files —
no app changes, no sidecar.

VSO talks to OpenBao over its standard API, so it works against OpenBao the same as Vault.

## Install (Helm)

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  -n vault-secrets-operator-system --create-namespace \
  --set defaultVaultConnection.enabled=true \
  --set defaultVaultConnection.address=https://openbao.secret-vault.svc:8200 \
  --set defaultVaultConnection.skipTLSVerify=false \
  --set defaultVaultConnection.caCertSecretRef=openbao-ca
```

## Wire-up

1. Enable the `kubernetes` auth method in OpenBao (Terraform: set
   `enable_kubernetes_auth = true` and define `k8s_workloads`).
2. Apply the sample `VaultAuth` + `VaultStaticSecret` in
   [`../../examples/k8s`](../../examples/k8s).
3. Confirm the target `Secret` is created and the sample pod reads it; update the source KV
   value and confirm VSO re-syncs.

## Alternatives (documented, not default)

- **Agent Injector** sidecar — pod annotations render secrets to a shared in-memory volume.
- **CSI provider** — secrets mounted as a CSI volume. Useful when you want file-only delivery
  and no materialized K8s `Secret`.

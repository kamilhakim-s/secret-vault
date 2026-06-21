# OpenShift specifics

Apply with `make openshift` (or `oc apply -f deploy/openshift/`).

## Security Context Constraints (SCC)

The OpenBao Helm chart runs as **non-root** and reads its UID from the namespace's
`openshift.io/sa.scc.uid-range`, so the default **`restricted-v2`** SCC is sufficient — do
**not** grant `anyuid` or `privileged`. Verify nothing is forcing a specific `runAsUser` in
the Helm values that falls outside the namespace range.

If you mount the Raft data PVC with an `fsGroup`, ensure it falls within the namespace's
`openshift.io/sa.scc.supplemental-groups` range (the chart handles this when
`global.openshift: true`).

## Files

| File | Purpose |
| --- | --- |
| `route.yaml` | Exposes UI/API via a reencrypt Route (edge TLS → pod TLS). |
| `networkpolicy.yaml` | Default-deny ingress + explicit allows (router, Raft peers, Prometheus). |
| `auth-delegator-rbac.yaml` | Lets the OpenBao SA call TokenReview for the `kubernetes` auth method (Phase 2). |

## TLS

Certificates (`openbao-tls`, `openbao-unsealer-tls`, `openbao-unsealer-ca`) come from
cert-manager or the OpenShift **service-CA** (annotate the Service with
`service.beta.openshift.io/serving-cert-secret-name`). The reencrypt Route needs the CA in
`destinationCACertificate` — wire this through your GitOps templating rather than committing
cert material.

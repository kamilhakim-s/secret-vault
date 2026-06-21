# Architecture

## Overview

```
                         ┌────────────────────────────┐
   Developers ──OIDC──▶  │  OpenBao built-in Web UI    │
   (browser)            │  + CLI/API (TLS)            │
                         └──────────────┬─────────────┘
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        │                OpenBao HA cluster (3–5 nodes)                   │
        │   Integrated Raft storage · Transit/KMS auto-unseal · TLS      │
        │                                                                 │
        │  Secrets engines:        Auth methods:                         │
        │   - kv-v2 (per team)      - oidc      (humans → built-in UI)   │
        │   - ldap  (AD rotation)   - jwt       (GitLab CI id_tokens)    │
        │                           - kubernetes(cluster workloads)      │
        │  Namespaces per team/app · Audit devices → SIEM                │
        └───────┬───────────────────────┬────────────────────┬──────────┘
                │                        │                    │
        GitLab CI/CD            K8s / OpenShift          Active Directory
   (id_tokens + secrets:)   (Vault Secrets Operator /   (service accounts,
                             Agent Injector / CSI)       auto-rotated)
```

## Components

### OpenBao cluster
- **HA** via 3 (or 5) replicas with **Integrated Raft storage** — no external storage
  dependency, snapshots are first-class.
- **Auto-unseal** via a small separate OpenBao **Transit** instance (or cloud KMS where
  available) so pods unseal on restart without a human entering key shares. Recovery keys are
  Shamir-split and stored offline (see [runbooks/init-unseal.md](runbooks/init-unseal.md)).
- **TLS** everywhere: client→server and Raft peer traffic. Certs from cert-manager or the
  OpenShift service-CA.

### Secrets engines
- **`kv-v2`** — versioned static key/value secrets, one mount per team (`kv/team-<name>`).
- **`ldap`** — Active Directory service-account password management with **automatic
  rotation** (static roles + `rotation_period`) and **check-out/check-in** for shared
  high-load accounts. This is the modern replacement for the older `ad` secrets engine.
- **`pki`** (Phase 5) — internal service-to-service TLS issuance.

### Auth methods
- **`oidc`** — human SSO to the built-in UI. IdP groups map to OpenBao policies; each team
  only sees its own paths.
- **`jwt`** — GitLab CI/CD. Jobs mint a short-lived `id_token`; OpenBao verifies it against
  GitLab's OIDC discovery URL and issues a job-scoped token bound to project/ref/environment
  claims.
- **`kubernetes`** — cluster workloads authenticate with their ServiceAccount token, verified
  via the TokenReview API.

## Secret delivery paths

### GitLab CI/CD
Native, credential-free. The job declares an `id_token` and a `secrets:` block; the runner
exchanges the token for a job-scoped OpenBao token and fetches the secret. Nothing is stored
in GitLab CI/CD variables. (Native `secrets:` requires GitLab Premium/Ultimate; Free/CE uses
`id_tokens` + a manual `bao` fetch — both shown in [examples/gitlab](../examples/gitlab).)

### Kubernetes / OpenShift
**Vault Secrets Operator (VSO)** is the default: a `VaultStaticSecret` (or
`VaultDynamicSecret`) CR tells the operator to materialize an OpenBao path into a native K8s
`Secret`, kept in sync. Workloads consume it as env/volume — no app changes. Alternatives:
the **Agent Injector** sidecar (annotations render secrets to a shared volume) and the
**CSI provider** (secrets mounted as a volume). On OpenShift, mind SCCs (run non-root),
expose the UI via a `Route`, and constrain traffic with `NetworkPolicy`.

## Identity & multi-tenancy
- **Namespaces** (free in OpenBao) isolate each team/app: separate mounts, policies, and
  auth role bindings, so self-service has no cross-team blast radius.
- **Policies** are least-privilege HCL in [terraform/policies](../terraform/policies),
  applied via Terraform. OIDC group claims and GitLab/K8s role bindings reference them.

## Configuration & change management (GitOps)
- **Cluster manifests** (`deploy/`) are applied by Argo CD / OpenShift GitOps.
- **OpenBao config** (mounts, policies, auth roles, LDAP rotation) is **Terraform** using the
  `vault` provider, which is API-compatible with OpenBao.
- Every change is a reviewed pull request — that review **is** the approval workflow.

## Availability & DR
- **Backups:** automated Raft snapshots to object storage (`scripts/snapshot-backup.sh`).
- **DR:** restore a snapshot into a fresh cluster — OpenBao OSS has no cross-region
  replication, so snapshot/restore is the strategy. Runbook:
  [runbooks/dr-snapshot-restore.md](runbooks/dr-snapshot-restore.md).

## Observability
- Prometheus telemetry endpoint scraped into Grafana; alerts on seal status, token TTL
  exhaustion, rotation failures, and audit-device outages.
- **Audit devices** (file → fluent-bit/forwarder) ship every request with identity + path to
  the SIEM. Audit logging is fail-closed by design — keep at least two devices so a single
  sink outage doesn't block operations.

## Phased build plan

| Phase | Scope |
| --- | --- |
| 0 | Foundations: repo, layout, docs, dev cluster, TLS, IdP/GitLab-tier confirm |
| 1 | **MVP**: OpenBao HA + auto-unseal + `kv-v2` + OIDC SSO + GitLab injection |
| 2 | K8s/OpenShift injection via VSO + `kubernetes` auth |
| 3 | **AD auto-rotation**: `ldap` secrets engine, static roles, check-out/check-in |
| 4 | Multi-tenancy (namespaces), RBAC, audit→SIEM, GitOps, snapshot DR |
| 5 | Hardening: PKI, telemetry/alerting, lease quotas, DR drills, FIPS gap note |

See each phase's verification steps in the [project README](../README.md) and the runbooks.

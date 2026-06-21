# secret-vault — Central Secrets Management Platform

An enterprise-grade, self-hosted secrets management platform built on **[OpenBao](https://openbao.org/)**
(the Linux Foundation open-source fork of HashiCorp Vault), running on **Kubernetes / OpenShift**.

Developers self-serve secrets through OpenBao's built-in web UI (fronted by corporate SSO),
and secrets are injected directly into **GitLab CI/CD** pipelines and **cluster workloads** —
nothing long-lived is ever copy-pasted or stored in a repo.

## Capabilities

| Capability | How it's delivered |
| --- | --- |
| Key/Value secrets | `kv-v2` secrets engine, one mount per team/namespace |
| AD secrets + auto-rotation | `ldap` secrets engine: static roles with `rotation_period` + check-out/check-in |
| Developer UI | OpenBao built-in web UI + OIDC SSO + namespace-scoped self-service policies |
| GitLab CI/CD injection | GitLab `id_tokens` → JWT auth → `secrets:` keyword (job-scoped, zero stored creds) |
| K8s / OpenShift injection | Vault Secrets Operator (VSO) syncs into native `Secret`s (Agent Injector / CSI as alternates) |
| Multi-tenancy | OpenBao namespaces (free) with isolated mounts + least-privilege policies |
| Governance | Audit devices → SIEM, config-as-code (Terraform), GitOps PR review = approval workflow |

## Why OpenBao (not Vault Enterprise)

OpenBao v2.5.0 (GA Feb 2026) is fully OSI-licensed and includes **namespaces/multi-tenancy
for free** (Enterprise-only in Vault). It shares Vault's API and secrets engines, and GitLab
runs it in production. Known gaps vs Vault Enterprise — **no cross-region Performance/DR
replication** and **no FIPS builds** — are mitigated here with automated Raft snapshot DR
(see [docs/runbooks/dr-snapshot-restore.md](docs/runbooks/dr-snapshot-restore.md)). If FIPS
is later mandated for a specific tier, evaluate Vault Enterprise for that tier only.

## Repository layout

```
deploy/
  helm/openbao/values.yaml          HA, Raft storage, OpenShift settings, telemetry
  helm/openbao/values-unsealer.yaml small Transit auto-unseal instance
  openshift/                        Route, SCC, NetworkPolicy, auth-delegator RBAC
  backup/                           scheduled Raft snapshot CronJob (Phase 4 DR)
  monitoring/                       ServiceMonitor + PrometheusRule + Grafana (Phase 5)
  vso/                              Vault Secrets Operator install + sample CRs (Phase 2)
  logging/                          Vector audit→SIEM forwarder (Phase 4)
  gitops/                           Argo CD Application (OpenShift GitOps) (Phase 4)
terraform/
  providers.tf                      vault provider → OpenBao address
  secrets-kv.tf                     kv-v2 mounts per team
  secrets-ldap.tf                   LDAP secrets engine: static roles + libraries (Phase 3)
  audit.tf                          file + socket audit devices (Phase 4)
  auth-oidc.tf                      human SSO → built-in UI, group→policy mapping
  auth-gitlab-jwt.tf                GitLab id_token JWT auth + roles
  auth-kubernetes.tf                cluster workload + snapshot auth (Phase 2)
  namespaces.tf                     per-team OpenBao namespaces (Phase 4)
  pki.tf                            internal PKI for service TLS (Phase 5)
  quotas.tf                         rate-limit + lease-count quotas (Phase 5)
  policies.tf / policies-ldap.tf    generated least-privilege policies
  policies/                         *.hcl / *.hcl.tpl policy sources
examples/
  gitlab/.gitlab-ci.yml             id_tokens + secrets: demo
  k8s/                              sample app + VaultStaticSecret/VaultAuth (Phase 2)
test/ad/                            throwaway Samba AD DC for Phase 3 testing (test only)
scripts/                            bootstrap init/unseal, snapshot backup, verify-phaseN
docs/                              architecture + runbooks
```

## Quick start (dev cluster)

Requires: an OpenShift Local (CRC) or kind/minikube cluster, `helm`, `terraform`, and the
`bao` CLI. See the [Makefile](Makefile) for the full target list.

```bash
make unsealer-up      # 1. deploy the Transit auto-unseal helper
make openbao-up       # 2. deploy the OpenBao HA cluster (Helm)
make init             # 3. initialize + capture recovery keys (scripts/bootstrap-init.sh)
make tf-apply         # 4. apply KV mounts, OIDC, GitLab JWT auth, policies (Terraform)
make verify           # 5. run the Phase 1 end-to-end check
```

Implementation is phased — see [docs/architecture.md](docs/architecture.md) for the full
build plan and the per-phase verification steps.

## Status

- [x] Phase 0 — Foundations (repo, layout, docs)
- [x] Phase 1 — MVP: OpenBao HA + KV + SSO + GitLab injection *(artifacts complete; run `make verify` on a cluster)*
- [x] Phase 2 — Kubernetes / OpenShift injection via VSO *(artifacts complete; run `make verify-phase2`)*
- [x] Phase 3 — AD secrets with auto-rotation via LDAP engine *(roles + libraries + policies wired; `make verify-phase3` against a real/test AD)*
- [x] Phase 4 — Multi-tenancy & governance *(namespaces pattern, dual audit devices → SIEM forwarder, GitOps Application)*
- [x] Phase 5 — Hardening & enterprise readiness *(PKI, rate/lease quotas, ServiceMonitor + alerts + Grafana, DR drill)*

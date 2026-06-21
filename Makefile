# secret-vault — operational targets
# Override these per environment (e.g. `make openbao-up NAMESPACE=secrets-prod`).
NAMESPACE        ?= secret-vault
RELEASE          ?= openbao
UNSEALER_RELEASE ?= openbao-unsealer
HELM_REPO        ?= https://openbao.github.io/openbao-helm
CHART            ?= openbao/openbao
BAO_ADDR         ?= https://openbao.$(NAMESPACE).svc:8200

# Skip TLS verification only against an internal dev CA; production uses a trusted bundle.
TF_DIR           ?= terraform

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: repo
repo: ## Add + update the OpenBao Helm repo
	helm repo add openbao $(HELM_REPO)
	helm repo update

.PHONY: unsealer-up
unsealer-up: repo ## Deploy the small Transit auto-unseal helper instance
	helm upgrade --install $(UNSEALER_RELEASE) $(CHART) \
		-n $(NAMESPACE) --create-namespace \
		-f deploy/helm/openbao/values-unsealer.yaml

.PHONY: openbao-up
openbao-up: repo ## Deploy the OpenBao HA cluster (Helm)
	helm upgrade --install $(RELEASE) $(CHART) \
		-n $(NAMESPACE) --create-namespace \
		-f deploy/helm/openbao/values.yaml

.PHONY: openshift
openshift: ## Apply OpenShift-specific manifests (Route, SCC, NetworkPolicy, RBAC)
	oc apply -n $(NAMESPACE) -f deploy/openshift/

VSO_NS ?= vault-secrets-operator-system

.PHONY: vso-up
vso-up: ## Install the Vault Secrets Operator (Phase 2)
	helm repo add hashicorp https://helm.releases.hashicorp.com
	helm repo update
	helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
		-n $(VSO_NS) --create-namespace

.PHONY: snapshot-cron
snapshot-cron: ## Install the scheduled Raft snapshot CronJob
	oc apply -n $(NAMESPACE) -f deploy/backup/snapshot-cronjob.yaml

.PHONY: init
init: ## Initialize OpenBao + capture recovery keys (interactive, writes to ./.secrets)
	./scripts/bootstrap-init.sh $(NAMESPACE) $(RELEASE)

.PHONY: tf-init
tf-init: ## terraform init
	cd $(TF_DIR) && terraform init

.PHONY: tf-plan
tf-plan: ## terraform plan (KV mounts, OIDC, GitLab JWT auth, policies)
	cd $(TF_DIR) && terraform plan

.PHONY: tf-apply
tf-apply: ## terraform apply
	cd $(TF_DIR) && terraform apply

.PHONY: snapshot
snapshot: ## Take a Raft snapshot and push to object storage
	./scripts/snapshot-backup.sh $(NAMESPACE) $(RELEASE)

.PHONY: verify
verify: ## Phase 1 end-to-end check (status, KV round-trip, audit)
	./scripts/verify-phase1.sh $(NAMESPACE) $(RELEASE)

.PHONY: verify-phase2
verify-phase2: ## Phase 2 end-to-end check (k8s auth + VSO sync/re-sync)
	./scripts/verify-phase2.sh $(NAMESPACE) $(RELEASE) payments

ROLE    ?= payments-svc
LIBRARY ?=

.PHONY: verify-phase3
verify-phase3: ## Phase 3 end-to-end check (AD rotation + check-out/in). Set ROLE/LIBRARY.
	./scripts/verify-phase3.sh $(NAMESPACE) $(RELEASE) $(ROLE) $(LIBRARY)

.PHONY: test-ad-up
test-ad-up: ## Deploy the throwaway Samba AD DC for Phase 3 testing (test only)
	oc apply -f test/ad/samba-ad-dc.yaml

.PHONY: audit-forwarder
audit-forwarder: ## Deploy the Vector audit→SIEM forwarder (Phase 4)
	oc apply -f deploy/logging/vector-audit-forwarder.yaml

.PHONY: gitops
gitops: ## Register the OpenShift GitOps (Argo CD) Application (Phase 4)
	oc apply -f deploy/gitops/application-platform.yaml

.PHONY: monitoring
monitoring: ## Apply ServiceMonitor, PrometheusRule, and Grafana dashboard (Phase 5)
	oc apply -f deploy/monitoring/

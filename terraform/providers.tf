# The HashiCorp `vault` provider speaks OpenBao's API (they share the same API surface).
# There is no separate "openbao" provider needed for these resources.
terraform {
  required_version = ">= 1.6"
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.4"
    }
  }

  # Use a remote backend in real environments (state contains sensitive config).
  # backend "s3" { ... }   # or consul / kubernetes / http
}

variable "openbao_addr" {
  type        = string
  description = "OpenBao API address (e.g. https://openbao.secret-vault.svc:8200)"
}

variable "openbao_ca_cert_file" {
  type        = string
  description = "Path to the CA bundle used to verify the OpenBao TLS cert."
  default     = ""
}

# Auth to OpenBao for Terraform itself is via the VAULT_TOKEN env var (a short-lived
# admin/automation token), NOT a static value in code.
provider "vault" {
  address      = var.openbao_addr
  ca_cert_file = var.openbao_ca_cert_file != "" ? var.openbao_ca_cert_file : null
}

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_PATH="${1:-}"

if [[ -z "${TARGET_PATH}" ]]; then
  fail "Usage: validate.sh <terraform-directory>"
fi

if [[ ! -d "${TARGET_PATH}" ]]; then
  fail "Target path '${TARGET_PATH}' is not a directory"
fi

if [[ ! -f "${TARGET_PATH}/main.tf" ]]; then
  fail "main.tf is required at the root of the Terraform directory"
fi

log "Checking Terraform formatting in ${TARGET_PATH}"
terraform -chdir="${TARGET_PATH}" fmt -check

log "Validation runner supports ${INCA_SUPPORTED_TERRAFORM_PROVIDER:-registry.terraform.io/hashicorp/aws} ${INCA_SUPPORTED_TERRAFORM_PROVIDER_VERSION:-unknown}"
log "Initializing Terraform without backend"
if ! terraform -chdir="${TARGET_PATH}" init -backend=false; then
  fail "Terraform init failed. The validation runner currently supports only ${INCA_SUPPORTED_TERRAFORM_PROVIDER:-registry.terraform.io/hashicorp/aws} ${INCA_SUPPORTED_TERRAFORM_PROVIDER_VERSION:-unknown} from its embedded provider mirror."
fi

log "Validating Terraform configuration"
terraform -chdir="${TARGET_PATH}" validate

log "Validation succeeded"

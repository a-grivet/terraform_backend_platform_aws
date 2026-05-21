#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

TARGET_PATH="${1:-}"

if [[ -z "${TARGET_PATH}" ]]; then
  fail "Usage: apply.sh <terraform-directory>"
fi

if [[ ! -d "${TARGET_PATH}" ]]; then
  fail "Target path '${TARGET_PATH}' is not a directory"
fi

if [[ ! -f "${TARGET_PATH}/main.tf" ]]; then
  fail "main.tf is required at the root of the Terraform directory"
fi

TF_PLAN_OUT="${TF_PLAN_OUT:-tfplan}"
TF_AUTO_APPROVE="${TF_AUTO_APPROVE:-true}"
TF_DESTROY_AFTER_APPLY="${TF_DESTROY_AFTER_APPLY:-false}"

log "Initializing Terraform in ${TARGET_PATH}"
terraform -chdir="${TARGET_PATH}" init

log "Creating Terraform execution plan"
terraform -chdir="${TARGET_PATH}" plan -out="${TF_PLAN_OUT}"

if [[ "${TF_AUTO_APPROVE}" == "true" ]]; then
  log "Applying Terraform plan with auto-approve"
  terraform -chdir="${TARGET_PATH}" apply -auto-approve "${TF_PLAN_OUT}"
else
  log "Applying Terraform plan"
  terraform -chdir="${TARGET_PATH}" apply "${TF_PLAN_OUT}"
fi

log "Terraform outputs"
terraform -chdir="${TARGET_PATH}" output

if [[ "${TF_DESTROY_AFTER_APPLY}" == "true" ]]; then
  log "Destroying Terraform-managed resources after apply"
  terraform -chdir="${TARGET_PATH}" destroy -auto-approve
fi

log "Apply workflow succeeded"

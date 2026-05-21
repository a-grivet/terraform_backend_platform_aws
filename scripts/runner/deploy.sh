#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

required_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Environment variable '${name}' is required"
  fi
}

utc_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

discover_task_id() {
  if [[ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]]; then
    curl -fsSL "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null \
      | jq -r '.TaskARN // empty' 2>/dev/null \
      | awk -F/ 'NF {print $NF}'
    return 0
  fi
  printf 'unknown'
}

build_dynamodb_key_json() {
  jq -n \
    --arg template_id "${TEMPLATE_ID}" \
    --arg version_id "${VERSION_ID}" \
    '{
      template_id: {S: $template_id},
      version_id: {S: $version_id}
    }'
}

update_status_transition() {
  local expected_status="$1"
  local next_status="$2"
  local timestamp="$3"
  local completed_at="${4:-}"
  local error_message="${5:-}"

  local expression values

  if [[ -n "${completed_at}" && -n "${error_message}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      --arg error_message "${error_message}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at},
        ":error_message": {S: $error_message}
      }')"
    values="$(jq '. + {":deploy_stage": {S: "DEPLOYMENT"}, ":failed_status": {S: "FAILED"}}' <<<"${values}")"
    expression="SET #status = :status, user_status = :failed_status, updated_at = :updated_at, deployment_completed_at = :completed_at, deployment_error_message = :error_message, failure_stage = :deploy_stage"

  elif [[ -n "${completed_at}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at}
      }')"
    values="$(jq '. + {":deployed_status": {S: "DEPLOYED"}}' <<<"${values}")"
    expression="SET #status = :status, user_status = :deployed_status, updated_at = :updated_at, deployment_completed_at = :completed_at REMOVE deployment_error_message, failure_stage"

  else
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg started_at "${timestamp}" \
      --arg task_id "${DEPLOYMENT_TASK_ID}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":updated_at": {S: $updated_at},
        ":started_at": {S: $started_at},
        ":task_id": {S: $task_id}
      }')"
    values="$(jq '. + {":in_progress": {S: "IN_PROGRESS"}}' <<<"${values}")"
    expression="SET #status = :status, user_status = :in_progress, updated_at = :updated_at, deployment_started_at = :started_at, deployment_task_id = :task_id REMOVE deployment_error_message, failure_stage"
  fi

  aws dynamodb update-item \
    --region "${AWS_REGION}" \
    --table-name "${UPLOAD_INTENTS_TABLE_NAME}" \
    --key "$(build_dynamodb_key_json)" \
    --condition-expression "#status = :expected" \
    --update-expression "${expression}" \
    --expression-attribute-names '{"#status":"status"}' \
    --expression-attribute-values "${values}" \
    >/dev/null
}

finalize_failure() {
  local message="${1:-Deployment failed.}"
  local timestamp
  timestamp="$(utc_now)"

  log "Marking deployment as failed for ${TEMPLATE_ID}/${VERSION_ID}: ${message}"
  restore_task_role_credentials
  update_status_transition "DEPLOYING" "DEPLOY_FAILED" "${timestamp}" "${timestamp}" "${message}" || true
}

_TASK_ROLE_KEY="${AWS_ACCESS_KEY_ID:-}"
_TASK_ROLE_SECRET="${AWS_SECRET_ACCESS_KEY:-}"
_TASK_ROLE_TOKEN="${AWS_SESSION_TOKEN:-}"

restore_task_role_credentials() {
  if [[ -n "${_TASK_ROLE_KEY}" ]]; then
    export AWS_ACCESS_KEY_ID="${_TASK_ROLE_KEY}"
    export AWS_SECRET_ACCESS_KEY="${_TASK_ROLE_SECRET}"
    export AWS_SESSION_TOKEN="${_TASK_ROLE_TOKEN}"
  else
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  fi
}

assume_target_role() {
  log "Assuming target role arn:aws:iam::${TARGET_ACCOUNT_ID}:role/${TARGET_ROLE_NAME}"

  local session_name
  session_name="$(printf 'inca-deploy-%s-%s' "${TEMPLATE_ID}" "${VERSION_ID}" | cut -c1-64)"

  local credentials
  credentials="$(aws sts assume-role \
    --role-arn "arn:aws:iam::${TARGET_ACCOUNT_ID}:role/${TARGET_ROLE_NAME}" \
    --role-session-name "${session_name}" \
    --region "${AWS_REGION}" \
    --query 'Credentials' \
    --output json)"

  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN

  AWS_ACCESS_KEY_ID="$(jq -r '.AccessKeyId' <<<"${credentials}")"
  AWS_SECRET_ACCESS_KEY="$(jq -r '.SecretAccessKey' <<<"${credentials}")"
  AWS_SESSION_TOKEN="$(jq -r '.SessionToken' <<<"${credentials}")"

  log "Successfully assumed role — session valid until $(jq -r '.Expiration' <<<"${credentials}")"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

required_env "AWS_REGION"
required_env "UPLOAD_INTENTS_TABLE_NAME"
required_env "DEPLOYMENT_S3_BUCKET"
required_env "DEPLOYMENT_S3_KEY"
required_env "TEMPLATE_ID"
required_env "VERSION_ID"
required_env "TARGET_ACCOUNT_ID"
required_env "TARGET_ROLE_NAME"

DEPLOYMENT_TASK_ID="$(discover_task_id)"
log "Task ${DEPLOYMENT_TASK_ID} triggered — bucket=${DEPLOYMENT_S3_BUCKET} key=${DEPLOYMENT_S3_KEY} target=${TARGET_ACCOUNT_ID}/${TARGET_ROLE_NAME}"

log "Starting deployment for ${TEMPLATE_ID}/${VERSION_ID}"
update_status_transition "DEPLOYING" "DEPLOYING" "$(utc_now)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
DEPLOYMENT_FAILURE_MESSAGE="Unexpected runtime failure."
trap 'finalize_failure "${DEPLOYMENT_FAILURE_MESSAGE}"' ERR

ARCHIVE_PATH="${WORKDIR}/package.zip"
EXTRACT_DIR="${WORKDIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

DEPLOYMENT_FAILURE_MESSAGE="Failed to download validated package from S3."
log "Downloading validated package from s3://${DEPLOYMENT_S3_BUCKET}/${DEPLOYMENT_S3_KEY}"
aws s3 cp "s3://${DEPLOYMENT_S3_BUCKET}/${DEPLOYMENT_S3_KEY}" "${ARCHIVE_PATH}" --region "${AWS_REGION}" >/dev/null

DEPLOYMENT_FAILURE_MESSAGE="Failed to extract package."
log "Extracting package"
unzip -q "${ARCHIVE_PATH}" -d "${EXTRACT_DIR}"

DEPLOYMENT_FAILURE_MESSAGE="Failed to determine Terraform root in extracted archive."
TERRAFORM_ROOT="$("${SCRIPT_DIR}/find_terraform_root.sh" "${EXTRACT_DIR}")"
log "Resolved Terraform root to ${TERRAFORM_ROOT}"

DEPLOYMENT_FAILURE_MESSAGE="Failed to assume target account role."
assume_target_role

DEPLOYMENT_FAILURE_MESSAGE="Terraform init failed in target account."
log "Initializing Terraform in ${TERRAFORM_ROOT}"
terraform -chdir="${TERRAFORM_ROOT}" init -no-color

DEPLOYMENT_FAILURE_MESSAGE="Terraform apply failed in target account."
log "Applying Terraform in ${TERRAFORM_ROOT}"
terraform -chdir="${TERRAFORM_ROOT}" apply -auto-approve -no-color

COMPLETED_AT="$(utc_now)"
log "Marking deployment as successful for ${TEMPLATE_ID}/${VERSION_ID}"
restore_task_role_credentials
update_status_transition "DEPLOYING" "DEPLOYED" "${COMPLETED_AT}" "${COMPLETED_AT}"

log "Deployment flow succeeded"

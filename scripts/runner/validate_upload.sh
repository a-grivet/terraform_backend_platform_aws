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

derive_identifiers_from_key() {
  local key="$1"
  if [[ "${key}" =~ ^blueprints/pending/[^/]+/([^/]+)/([^/]+)/[^/]+\.zip$ ]]; then
    TEMPLATE_ID="${BASH_REMATCH[1]}"
    VERSION_ID="${BASH_REMATCH[2]}"
  elif [[ "${key}" =~ ^uploads/raw/([^/]+)/([^/]+)\.zip$ ]]; then
    TEMPLATE_ID="${BASH_REMATCH[1]}"
    VERSION_ID="${BASH_REMATCH[2]}"
  else
    fail "Unable to derive template_id and version_id from key '${key}'"
  fi
}

build_lifecycle_key() {
  local target_stage="$1"
  local key="$2"

  if [[ "${key}" == blueprints/pending/* ]]; then
    printf 'blueprints/%s/%s' "${target_stage}" "${key#blueprints/pending/}"
    return 0
  fi

  fail "Unable to derive ${target_stage} key from '${key}'"
}

move_uploaded_package() {
  local target_stage="$1"
  local source_key="$2"
  local target_key

  target_key="$(build_lifecycle_key "${target_stage}" "${source_key}")"

  log "Moving uploaded package to s3://${VALIDATION_S3_BUCKET}/${target_key}" >&2
  aws s3 mv \
    "s3://${VALIDATION_S3_BUCKET}/${source_key}" \
    "s3://${VALIDATION_S3_BUCKET}/${target_key}" \
    --region "${AWS_REGION}" \
    >/dev/null

  printf '%s' "${target_key}"
}

discover_task_id() {
  if [[ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]]; then
    curl -fsSL "${ECS_CONTAINER_METADATA_URI_V4}/task" 2>/dev/null | jq -r '.TaskARN // empty' 2>/dev/null | awk -F/ 'NF {print $NF}'
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

derive_user_status() {
  local backend_status="$1"

  case "${backend_status}" in
    WAITING_FOR_UPLOAD | UPLOADED | VALIDATING | READY)
      printf 'IN_PROGRESS'
      ;;
    DEPLOYING)
      printf 'DEPLOYING'
      ;;
    DEPLOYED)
      printf 'DEPLOYED'
      ;;
    VALIDATION_FAILED | DEPLOY_FAILED)
      printf 'FAILED'
      ;;
    *)
      printf '%s' "${backend_status}"
      ;;
  esac
}

derive_user_status_label() {
  local backend_status="$1"

  case "${backend_status}" in
    WAITING_FOR_UPLOAD | UPLOADED | VALIDATING | READY)
      printf 'In progress'
      ;;
    VALIDATION_FAILED)
      printf 'Needs changes'
      ;;
    DEPLOYING)
      printf 'Deploying'
      ;;
    DEPLOYED)
      printf 'Deployed'
      ;;
    DEPLOY_FAILED)
      printf 'Deployment failed'
      ;;
    *)
      printf '%s' "${backend_status}"
      ;;
  esac
}

update_status_transition() {
  local expected_status="$1"
  local next_status="$2"
  local timestamp="$3"
  local completed_at="${4:-}"
  local error_message="${5:-}"
  local lifecycle_s3_key="${6:-}"
  local next_user_status
  local next_user_status_label
  next_user_status="$(derive_user_status "${next_status}")"
  next_user_status_label="$(derive_user_status_label "${next_status}")"

  local values
  local expression

  if [[ -n "${completed_at}" && -n "${error_message}" && -n "${lifecycle_s3_key}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg user_status "${next_user_status}" \
      --arg user_status_label "${next_user_status_label}" \
      --arg validation_status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      --arg error_message "${error_message}" \
      --arg s3_key "${lifecycle_s3_key}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":user_status": {S: $user_status},
        ":user_status_label": {S: $user_status_label},
        ":validation_status": {S: $validation_status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at},
        ":error_message": {S: $error_message},
        ":s3_key": {S: $s3_key}
      }'
    )"
    expression="SET #status = :status, user_status = :user_status, user_status_label = :user_status_label, validation_status = :validation_status, updated_at = :updated_at, validation_completed_at = :completed_at, validation_error_message = :error_message, failure_stage = :validation_stage, s3_key = :s3_key"
    values="$(jq '. + {":validation_stage": {S: "VALIDATION"}}' <<<"${values}")"
  elif [[ -n "${completed_at}" && -n "${error_message}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg user_status "${next_user_status}" \
      --arg user_status_label "${next_user_status_label}" \
      --arg validation_status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      --arg error_message "${error_message}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":user_status": {S: $user_status},
        ":user_status_label": {S: $user_status_label},
        ":validation_status": {S: $validation_status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at},
        ":error_message": {S: $error_message}
      }'
    )"
    expression="SET #status = :status, user_status = :user_status, user_status_label = :user_status_label, validation_status = :validation_status, updated_at = :updated_at, validation_completed_at = :completed_at, validation_error_message = :error_message, failure_stage = :validation_stage"
    values="$(jq '. + {":validation_stage": {S: "VALIDATION"}}' <<<"${values}")"
  elif [[ -n "${completed_at}" && -n "${lifecycle_s3_key}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg user_status "${next_user_status}" \
      --arg user_status_label "${next_user_status_label}" \
      --arg validation_status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      --arg s3_key "${lifecycle_s3_key}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":user_status": {S: $user_status},
        ":user_status_label": {S: $user_status_label},
        ":validation_status": {S: $validation_status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at},
        ":s3_key": {S: $s3_key}
      }'
    )"
    expression="SET #status = :status, user_status = :user_status, user_status_label = :user_status_label, validation_status = :validation_status, updated_at = :updated_at, validation_completed_at = :completed_at, s3_key = :s3_key REMOVE validation_error_message, failure_stage"
  elif [[ -n "${completed_at}" ]]; then
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg user_status "${next_user_status}" \
      --arg user_status_label "${next_user_status_label}" \
      --arg validation_status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg completed_at "${completed_at}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":user_status": {S: $user_status},
        ":user_status_label": {S: $user_status_label},
        ":validation_status": {S: $validation_status},
        ":updated_at": {S: $updated_at},
        ":completed_at": {S: $completed_at}
      }'
    )"
    expression="SET #status = :status, user_status = :user_status, user_status_label = :user_status_label, validation_status = :validation_status, updated_at = :updated_at, validation_completed_at = :completed_at REMOVE validation_error_message, failure_stage"
  else
    values="$(jq -n \
      --arg expected "${expected_status}" \
      --arg status "${next_status}" \
      --arg user_status "${next_user_status}" \
      --arg user_status_label "${next_user_status_label}" \
      --arg validation_status "${next_status}" \
      --arg updated_at "${timestamp}" \
      --arg started_at "${timestamp}" \
      --arg task_id "${VALIDATION_TASK_ID}" \
      '{
        ":expected": {S: $expected},
        ":status": {S: $status},
        ":user_status": {S: $user_status},
        ":user_status_label": {S: $user_status_label},
        ":validation_status": {S: $validation_status},
        ":updated_at": {S: $updated_at},
        ":started_at": {S: $started_at},
        ":task_id": {S: $task_id}
      }'
    )"
    expression="SET #status = :status, user_status = :user_status, user_status_label = :user_status_label, validation_status = :validation_status, updated_at = :updated_at, validation_started_at = :started_at, validation_task_id = :task_id REMOVE validation_error_message, failure_stage"
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

find_validation_root() {
  local workspace="$1"

  if [[ -f "${workspace}/main.tf" ]]; then
    printf '%s' "${workspace}"
    return 0
  fi

  local candidate_count
  candidate_count="$(find "${workspace}" -mindepth 2 -maxdepth 2 -type f -name 'main.tf' | wc -l | tr -d ' ')"

  if [[ "${candidate_count}" == "1" ]]; then
    find "${workspace}" -mindepth 2 -maxdepth 2 -type f -name 'main.tf' -print -quit | xargs dirname
    return 0
  fi

  fail "Unable to determine a unique Terraform root in extracted archive '${workspace}'"
}

finalize_failure() {
  local timestamp
  timestamp="$(utc_now)"
  local message="${1:-Validation failed.}"
  local rejected_key=""

  if [[ -n "${VALIDATION_S3_BUCKET:-}" && -n "${VALIDATION_S3_KEY:-}" && "${VALIDATION_S3_KEY}" == blueprints/pending/* ]]; then
    rejected_key="$(move_uploaded_package "rejected" "${VALIDATION_S3_KEY}" || true)"
  fi

  log "Marking validation as failed for ${TEMPLATE_ID}/${VERSION_ID}: ${message}"
  update_status_transition "VALIDATING" "VALIDATION_FAILED" "${timestamp}" "${timestamp}" "${message}" "${rejected_key}" || true
}

required_env "AWS_REGION"
required_env "UPLOAD_INTENTS_TABLE_NAME"
required_env "VALIDATION_S3_BUCKET"
required_env "VALIDATION_S3_KEY"

VALIDATION_TASK_ID="$(discover_task_id)"
log "Task ${VALIDATION_TASK_ID} triggered — bucket=${VALIDATION_S3_BUCKET} key=${VALIDATION_S3_KEY}"

derive_identifiers_from_key "${VALIDATION_S3_KEY}"

log "Starting validation for ${TEMPLATE_ID}/${VERSION_ID}"
update_status_transition "UPLOADED" "VALIDATING" "$(utc_now)"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT
VALIDATION_FAILURE_MESSAGE="Unexpected runtime failure."
trap 'finalize_failure "${VALIDATION_FAILURE_MESSAGE}" ' ERR

ARCHIVE_PATH="${WORKDIR}/package.zip"
EXTRACT_DIR="${WORKDIR}/extracted"
mkdir -p "${EXTRACT_DIR}"

VALIDATION_FAILURE_MESSAGE="Failed to download uploaded package from S3."
log "Downloading uploaded package from s3://${VALIDATION_S3_BUCKET}/${VALIDATION_S3_KEY}"
aws s3 cp "s3://${VALIDATION_S3_BUCKET}/${VALIDATION_S3_KEY}" "${ARCHIVE_PATH}" --region "${AWS_REGION}" >/dev/null

VALIDATION_FAILURE_MESSAGE="Failed to extract uploaded package."
log "Extracting uploaded package"
unzip -q "${ARCHIVE_PATH}" -d "${EXTRACT_DIR}"

VALIDATION_FAILURE_MESSAGE="Failed to determine Terraform root in extracted archive."
VALIDATION_ROOT="$(find_validation_root "${EXTRACT_DIR}")"
log "Resolved Terraform validation root to ${VALIDATION_ROOT}"

VALIDATION_FAILURE_MESSAGE="Terraform validation failed. The validation runner currently supports only ${INCA_SUPPORTED_TERRAFORM_PROVIDER:-registry.terraform.io/hashicorp/aws} ${INCA_SUPPORTED_TERRAFORM_PROVIDER_VERSION:-unknown}. See CloudWatch logs for details."
"${SCRIPT_DIR}/validate.sh" "${VALIDATION_ROOT}"

COMPLETED_AT="$(utc_now)"
VALIDATED_S3_KEY="$(move_uploaded_package "validated" "${VALIDATION_S3_KEY}")"
log "Marking validation as successful for ${TEMPLATE_ID}/${VERSION_ID}"
update_status_transition "VALIDATING" "READY" "${COMPLETED_AT}" "${COMPLETED_AT}" "" "${VALIDATED_S3_KEY}"

log "Validation flow succeeded"

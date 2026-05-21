#!/usr/bin/env bash
# test_validation_foundation_flow.sh
#
# Smoke test for the validation foundation end-to-end flow.
#
# What this test validates:
#   - The full upload sequence (prepare → S3 upload → complete) succeeds and
#     transitions the intent to UPLOADED.
#   - The S3 ObjectCreated event triggers the EventBridge rule, which launches
#     an ECS Fargate validation task.
#   - The Fargate task runs validate.sh against the uploaded package and
#     writes the outcome back to DynamoDB.
#   - The intent reaches the expected terminal status within the timeout.
#
# The test polls DynamoDB every 5 seconds until the intent status matches
# EXPECTED_STATUS (default: READY) or a terminal failure state is detected.
# VALIDATION_FAILED is always treated as a hard failure regardless of the
# expected status.
#
# Required env vars:
#   API_URL                   Base URL of the upload API (without trailing slash)
#   AWS_REGION                AWS region where the foundation is deployed
#   UPLOAD_INTENTS_TABLE_NAME DynamoDB table name for upload intents
#
# Required binaries: aws, curl, jq, zip, mktemp
#
# CI usage:
#   verify / smoke_test_validation_dev  (expected status: READY)
#   verify / smoke_test_validation_main (expected status: READY)
#
# Usage:
#   bash test_validation_foundation_flow.sh <fixture-directory> [expected-status] [timeout-seconds]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../scripts/runner/common.sh"

required_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Environment variable '${name}' is required"
  fi
}

FIXTURE_DIR="${1:-}"
EXPECTED_STATUS="${2:-READY}"
TIMEOUT_SECONDS="${3:-180}"

if [[ -z "${FIXTURE_DIR}" ]]; then
  fail "Usage: test_validation_foundation_flow.sh <fixture-directory> [expected-status] [timeout-seconds]"
fi

if [[ ! -d "${FIXTURE_DIR}" ]]; then
  fail "Fixture directory '${FIXTURE_DIR}' does not exist"
fi

for binary in aws curl jq zip mktemp; do
  if ! command -v "${binary}" >/dev/null 2>&1; then
    fail "Required binary '${binary}' is not available"
  fi
done

required_env "API_URL"
required_env "AWS_REGION"
required_env "UPLOAD_INTENTS_TABLE_NAME"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

ARCHIVE_PATH="${WORKDIR}/fixture.zip"
FIXTURE_NAME="$(basename "${FIXTURE_DIR}")"
TEMPLATE_NAME="${FIXTURE_NAME}-$(date +%s)"
FILE_NAME="${FIXTURE_NAME}.zip"

log "Building ZIP archive from ${FIXTURE_DIR}"
(
  cd "${FIXTURE_DIR}"
  zip -qr "${ARCHIVE_PATH}" .
)

FILE_SIZE="$(wc -c < "${ARCHIVE_PATH}" | tr -d ' ')"

log "Calling prepare endpoint"
PREPARE_RESPONSE="$(curl -fsS -X POST "${API_URL}/templates/uploads/prepare" \
  -H "Content-Type: application/json" \
  -d "{\"template_name\":\"${TEMPLATE_NAME}\",\"file_name\":\"${FILE_NAME}\",\"content_type\":\"application/zip\",\"file_size\":${FILE_SIZE}}")"

TEMPLATE_ID="$(printf '%s' "${PREPARE_RESPONSE}" | jq -r '.template_id')"
VERSION_ID="$(printf '%s' "${PREPARE_RESPONSE}" | jq -r '.version_id')"
UPLOAD_URL="$(printf '%s' "${PREPARE_RESPONSE}" | jq -r '.upload.url')"

log "Uploading archive for ${TEMPLATE_ID}/${VERSION_ID}"
curl -fsS "${UPLOAD_URL}" \
  -H "Content-Type: application/zip" \
  --upload-file "${ARCHIVE_PATH}" \
  >/dev/null

log "Calling complete endpoint"
curl -fsS -X POST "${API_URL}/templates/uploads/complete" \
  -H "Content-Type: application/json" \
  -d "{\"template_id\":\"${TEMPLATE_ID}\",\"version_id\":\"${VERSION_ID}\"}" \
  >/dev/null

DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))

while (( $(date +%s) < DEADLINE )); do
  ITEM_JSON="$(aws dynamodb get-item \
    --region "${AWS_REGION}" \
    --table-name "${UPLOAD_INTENTS_TABLE_NAME}" \
    --key "{\"template_id\":{\"S\":\"${TEMPLATE_ID}\"},\"version_id\":{\"S\":\"${VERSION_ID}\"}}")"

  CURRENT_STATUS="$(printf '%s' "${ITEM_JSON}" | jq -r '.Item.status.S // empty')"

  case "${CURRENT_STATUS}" in
    "${EXPECTED_STATUS}")
      log "Validation foundation smoke test reached expected status '${EXPECTED_STATUS}' for ${TEMPLATE_ID}/${VERSION_ID}"
      exit 0
      ;;
    VALIDATION_FAILED)
      ERROR_MESSAGE="$(printf '%s' "${ITEM_JSON}" | jq -r '.Item.validation_error_message.S // "Validation failed without explicit error message."')"
      fail "Validation flow ended in VALIDATION_FAILED for ${TEMPLATE_ID}/${VERSION_ID}: ${ERROR_MESSAGE}"
      ;;
    READY)
      fail "Validation flow unexpectedly reached READY for ${TEMPLATE_ID}/${VERSION_ID}"
      ;;
    "")
      log "Waiting for DynamoDB item to become visible for ${TEMPLATE_ID}/${VERSION_ID}"
      ;;
    *)
      log "Current status for ${TEMPLATE_ID}/${VERSION_ID}: ${CURRENT_STATUS}"
      ;;
  esac

  sleep 5
done

fail "Validation flow did not reach '${EXPECTED_STATUS}' within ${TIMEOUT_SECONDS}s for ${TEMPLATE_ID}/${VERSION_ID}"

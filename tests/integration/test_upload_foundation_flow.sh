#!/usr/bin/env bash
# test_upload_foundation_flow.sh
#
# Smoke test for the upload foundation end-to-end flow.
#
# What this test validates:
#   - The prepare endpoint (POST /templates/uploads/prepare) returns a presigned
#     S3 URL and creates an upload intent in DynamoDB with status
#     WAITING_FOR_UPLOAD.
#   - The ZIP archive uploads successfully to the presigned URL.
#   - The complete endpoint (POST /templates/uploads/complete) transitions the
#     intent status to UPLOADED in both the API response and DynamoDB.
#
# This test exercises the full API Gateway → Lambda → S3 → DynamoDB chain for
# the upload flow. It does not trigger the validation flow; the intent is left
# in the UPLOADED state at the end.
#
# Required env vars:
#   API_URL                  Base URL of the upload API (without trailing slash)
#   AWS_REGION               AWS region where the foundation is deployed
#   UPLOAD_INTENTS_TABLE_NAME DynamoDB table name for upload intents
#
# Required binaries: aws, curl, python3, zip, mktemp
#
# CI usage:
#   verify / smoke_test_upload_dev
#   verify / smoke_test_upload_main
#
# Usage:
#   bash test_upload_foundation_flow.sh <fixture-directory>

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

if [[ -z "${FIXTURE_DIR}" ]]; then
  fail "Usage: test_upload_foundation_flow.sh <fixture-directory>"
fi

if [[ ! -d "${FIXTURE_DIR}" ]]; then
  fail "Fixture directory '${FIXTURE_DIR}' does not exist"
fi

for binary in aws curl python3 zip mktemp; do
  if ! command -v "${binary}" >/dev/null 2>&1; then
    fail "Required binary '${binary}' is not available"
  fi
done

json_value() {
  local path="$1"
  python3 -c '
import json
import sys

value = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    if not isinstance(value, dict) or key not in value:
        value = ""
        break
    value = value[key]

if isinstance(value, (str, int, float)):
    print(value)
' "${path}"
}

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

TEMPLATE_ID="$(printf '%s' "${PREPARE_RESPONSE}" | json_value "template_id")"
VERSION_ID="$(printf '%s' "${PREPARE_RESPONSE}" | json_value "version_id")"
UPLOAD_URL="$(printf '%s' "${PREPARE_RESPONSE}" | json_value "upload.url")"

ITEM_JSON="$(aws dynamodb get-item \
  --region "${AWS_REGION}" \
  --table-name "${UPLOAD_INTENTS_TABLE_NAME}" \
  --key "{\"template_id\":{\"S\":\"${TEMPLATE_ID}\"},\"version_id\":{\"S\":\"${VERSION_ID}\"}}")"

DDB_STATUS="$(printf '%s' "${ITEM_JSON}" | json_value "Item.status.S")"
if [[ "${DDB_STATUS}" != "WAITING_FOR_UPLOAD" ]]; then
  fail "Expected DynamoDB status 'WAITING_FOR_UPLOAD' after prepare, got '${DDB_STATUS:-missing}'"
fi

log "DynamoDB status after prepare is WAITING_FOR_UPLOAD for ${TEMPLATE_ID}/${VERSION_ID}"

log "Uploading archive for ${TEMPLATE_ID}/${VERSION_ID}"
curl -fsS "${UPLOAD_URL}" \
  -H "Content-Type: application/zip" \
  --upload-file "${ARCHIVE_PATH}" \
  >/dev/null

log "Calling complete endpoint"
COMPLETE_RESPONSE="$(curl -fsS -X POST "${API_URL}/templates/uploads/complete" \
  -H "Content-Type: application/json" \
  -d "{\"template_id\":\"${TEMPLATE_ID}\",\"version_id\":\"${VERSION_ID}\"}")"

FINAL_STATUS="$(printf '%s' "${COMPLETE_RESPONSE}" | json_value "status")"
if [[ "${FINAL_STATUS}" != "UPLOADED" ]]; then
  fail "Expected upload status 'UPLOADED', got '${FINAL_STATUS}'"
fi

ITEM_JSON="$(aws dynamodb get-item \
  --region "${AWS_REGION}" \
  --table-name "${UPLOAD_INTENTS_TABLE_NAME}" \
  --key "{\"template_id\":{\"S\":\"${TEMPLATE_ID}\"},\"version_id\":{\"S\":\"${VERSION_ID}\"}}")"

DDB_STATUS="$(printf '%s' "${ITEM_JSON}" | json_value "Item.status.S")"
if [[ "${DDB_STATUS}" != "UPLOADED" ]]; then
  fail "Expected DynamoDB status 'UPLOADED', got '${DDB_STATUS:-missing}'"
fi

log "DynamoDB status after complete is UPLOADED for ${TEMPLATE_ID}/${VERSION_ID}"
log "Upload foundation smoke test succeeded for ${TEMPLATE_ID}/${VERSION_ID}"

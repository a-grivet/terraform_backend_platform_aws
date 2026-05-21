#!/usr/bin/env bash
# Integration smoke test for the deployment foundation end-to-end flow.
#
# Uploads minimal-deploy-lab, waits for validation (READY), authenticates a
# transient Cognito test user, triggers a deployment via the deployment API,
# and asserts the Step Functions execution reaches SUCCEEDED.
#
# Required env vars:
#   API_URL                      Upload API base URL
#   DEPLOYMENT_API_URL           Deployment API base URL
#   DEPLOYMENT_STATE_MACHINE_ARN Step Functions state machine ARN
#   UPLOAD_INTENTS_TABLE_NAME    DynamoDB table for upload intents
#   COGNITO_USER_POOL_ID         Cognito user pool ID
#   COGNITO_CLIENT_ID            Cognito app client ID
#   AWS_REGION                   AWS region
#
# Usage:
#   test_deployment_foundation_flow.sh <fixture-dir> [timeout-seconds]

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
TIMEOUT_SECONDS="${2:-300}"

if [[ -z "${FIXTURE_DIR}" ]]; then
  fail "Usage: test_deployment_foundation_flow.sh <fixture-directory> [timeout-seconds]"
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
required_env "DEPLOYMENT_API_URL"
required_env "DEPLOYMENT_STATE_MACHINE_ARN"
required_env "UPLOAD_INTENTS_TABLE_NAME"
required_env "COGNITO_USER_POOL_ID"
required_env "COGNITO_CLIENT_ID"
required_env "AWS_REGION"

log "Runner public IP: $(curl -sf --max-time 5 https://checkip.amazonaws.com || echo 'unavailable')"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

TEST_USER=""
WORKDIR="$(mktemp -d)"

cleanup() {
  if [[ -n "${TEST_USER}" ]]; then
    log "Cleaning up test Cognito user: ${TEST_USER}"
    aws cognito-idp admin-delete-user \
      --user-pool-id "${COGNITO_USER_POOL_ID}" \
      --username "${TEST_USER}" 2>/dev/null || true
  fi
  rm -rf "${WORKDIR}"
}

trap cleanup EXIT

# ---------------------------------------------------------------------------
# Step 1: Upload the fixture blueprint
# ---------------------------------------------------------------------------

ARCHIVE_PATH="${WORKDIR}/fixture.zip"
FIXTURE_NAME="$(basename "${FIXTURE_DIR}")"
TEMPLATE_NAME="${FIXTURE_NAME}-smoke-$(date +%s)"
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

log "template_id=${TEMPLATE_ID} version_id=${VERSION_ID}"

log "Uploading archive to S3 presigned URL"
curl -fsS -X PUT "${UPLOAD_URL}" \
  -H "Content-Type: application/zip" \
  --data-binary "@${ARCHIVE_PATH}"

log "Calling complete endpoint"
curl -fsS -X POST "${API_URL}/templates/uploads/complete" \
  -H "Content-Type: application/json" \
  -d "{\"template_id\":\"${TEMPLATE_ID}\",\"version_id\":\"${VERSION_ID}\"}" > /dev/null

# ---------------------------------------------------------------------------
# Step 2: Wait for validation (READY status)
# ---------------------------------------------------------------------------

log "Waiting up to ${TIMEOUT_SECONDS}s for blueprint to reach READY status..."
VALIDATION_START="$(date +%s)"

while true; do
  ELAPSED=$(( $(date +%s) - VALIDATION_START ))
  if (( ELAPSED >= TIMEOUT_SECONDS )); then
    fail "Timeout after ${TIMEOUT_SECONDS}s waiting for READY status"
  fi

  ITEM="$(aws dynamodb get-item \
    --table-name "${UPLOAD_INTENTS_TABLE_NAME}" \
    --key "{\"template_id\":{\"S\":\"${TEMPLATE_ID}\"},\"version_id\":{\"S\":\"${VERSION_ID}\"}}" \
    --output json)"

  CURRENT_STATUS="$(printf '%s' "${ITEM}" | jq -r '.Item.status.S // "NOT_FOUND"')"
  log "Blueprint status: ${CURRENT_STATUS} (${ELAPSED}s elapsed)"

  case "${CURRENT_STATUS}" in
    READY)
      log "Blueprint is READY"
      break
      ;;
    FAILED|INVALID|ERROR)
      fail "Blueprint reached failure status: ${CURRENT_STATUS}"
      ;;
  esac

  sleep 10
done

# ---------------------------------------------------------------------------
# Step 3: Create transient Cognito test user and authenticate
# ---------------------------------------------------------------------------

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SANDBOX_ROLE_NAME="inca-learner-sandbox-001"
TEST_USER="smoke-deploy-$(date +%s)@inca-test.internal"
TEST_PASSWORD="Sm0ke!$(date +%s | tail -c 8)"

log "Creating Cognito test user: ${TEST_USER}"
aws cognito-idp admin-create-user \
  --user-pool-id "${COGNITO_USER_POOL_ID}" \
  --username "${TEST_USER}" \
  --user-attributes \
    "Name=email,Value=${TEST_USER}" \
    "Name=email_verified,Value=true" \
    "Name=custom:aws_account_id,Value=${ACCOUNT_ID}" \
    "Name=custom:role_name,Value=${SANDBOX_ROLE_NAME}" \
  --message-action SUPPRESS \
  --output json > /dev/null

aws cognito-idp admin-set-user-password \
  --user-pool-id "${COGNITO_USER_POOL_ID}" \
  --username "${TEST_USER}" \
  --password "${TEST_PASSWORD}" \
  --permanent

log "Authenticating test user"
AUTH_RESULT="$(aws cognito-idp initiate-auth \
  --client-id "${COGNITO_CLIENT_ID}" \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=${TEST_USER},PASSWORD=${TEST_PASSWORD}" \
  --output json)"

ID_TOKEN="$(printf '%s' "${AUTH_RESULT}" | jq -r '.AuthenticationResult.IdToken')"
if [[ -z "${ID_TOKEN}" || "${ID_TOKEN}" == "null" ]]; then
  fail "Failed to obtain Cognito ID token"
fi
log "Cognito ID token obtained"

# ---------------------------------------------------------------------------
# Step 4: Trigger deployment
# ---------------------------------------------------------------------------

log "POST ${DEPLOYMENT_API_URL}/deployments"
DEPLOY_RESPONSE="$(curl -fsS -X POST "${DEPLOYMENT_API_URL}/deployments" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -d "{\"template_id\":\"${TEMPLATE_ID}\",\"version_id\":\"${VERSION_ID}\"}")"

log "Deploy response: $(printf '%s' "${DEPLOY_RESPONSE}" | jq -c .)"

EXECUTION_ARN="$(printf '%s' "${DEPLOY_RESPONSE}" | jq -r '.execution_arn')"
if [[ -z "${EXECUTION_ARN}" || "${EXECUTION_ARN}" == "null" ]]; then
  fail "No execution_arn in deployment response"
fi
log "Step Functions execution: ${EXECUTION_ARN}"

# ---------------------------------------------------------------------------
# Step 5: Poll Step Functions execution
# ---------------------------------------------------------------------------

log "Waiting up to ${TIMEOUT_SECONDS}s for execution to complete..."
DEPLOY_START="$(date +%s)"

while true; do
  ELAPSED=$(( $(date +%s) - DEPLOY_START ))
  if (( ELAPSED >= TIMEOUT_SECONDS )); then
    fail "Timeout after ${TIMEOUT_SECONDS}s waiting for Step Functions execution"
  fi

  EXEC_STATUS="$(aws stepfunctions describe-execution \
    --execution-arn "${EXECUTION_ARN}" \
    --query 'status' --output text)"

  log "Execution status: ${EXEC_STATUS} (${ELAPSED}s elapsed)"

  case "${EXEC_STATUS}" in
    SUCCEEDED)
      log "Smoke test PASSED — deployment flow verified end-to-end"
      exit 0
      ;;
    FAILED|ABORTED|TIMED_OUT)
      EXEC_CAUSE="$(aws stepfunctions describe-execution \
        --execution-arn "${EXECUTION_ARN}" \
        --query 'cause' --output text 2>/dev/null || echo 'unavailable')"
      log "Execution failure cause: ${EXEC_CAUSE}"
      aws stepfunctions get-execution-history \
        --execution-arn "${EXECUTION_ARN}" \
        --output json 2>/dev/null \
        | jq '[.events[] | select(.type | test("Failed|Error|Fault|fault"))] | .[-3:]' || true
      fail "Step Functions execution reached failure status: ${EXEC_STATUS}"
      ;;
  esac

  sleep 15
done

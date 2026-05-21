#!/usr/bin/env bash
# test_offline_provider_mirror.sh
#
# Verifies that validate.sh correctly handles the filesystem mirror mechanism
# used by the Terraform runner image.
#
# What this test validates:
#   - validate.sh succeeds when the required provider is present in the
#     filesystem mirror (success path: hashicorp/aws).
#   - validate.sh fails with the expected diagnostic message when the required
#     provider is absent from the mirror (failure path: hashicorp/random is
#     not in the mirror, so terraform init cannot resolve it).
#
# What this test does NOT validate:
#   - The provider binary embedded in the published runner image at build time.
#     That layer is exercised by the end-to-end smoke tests
#     (smoke_test_validation_foundation_dev / _main), which run validate.sh
#     inside the actual ECS Fargate task against the image mirror embedded at
#     /opt/terraform-provider-mirror.
#
# Constraint: this test runs in the CI `test` stage, before the runner image is
# built. It therefore reconstructs the mirror structure locally rather than
# using the image-embedded mirror. The mirror path layout and the
# TF_CLI_CONFIG_FILE configuration intentionally mirror config/terraform.rc and
# the Dockerfile RUN layer so that any structural drift between the test and the
# image configuration is immediately visible.
#
# The success path downloads the AWS provider binary once at test time. The
# failure path uses an intentionally empty mirror and requires no network access.
#
# Usage:
#   bash test_offline_provider_mirror.sh <fixture-path> <success|failure>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/runner/common.sh"

FIXTURE_PATH="${1:-}"
EXPECTED_RESULT="${2:-}"
PROVIDER_VERSION="${TERRAFORM_AWS_PROVIDER_VERSION:-5.100.0}"

if [[ -z "${FIXTURE_PATH}" || -z "${EXPECTED_RESULT}" ]]; then
  fail "Usage: test_offline_provider_mirror.sh <fixture-path> <success|failure>"
fi

if [[ ! -d "${FIXTURE_PATH}" ]]; then
  fail "Fixture path '${FIXTURE_PATH}' is not a directory"
fi

if [[ "${EXPECTED_RESULT}" != "success" && "${EXPECTED_RESULT}" != "failure" ]]; then
  fail "Expected result must be either 'success' or 'failure'"
fi

for binary in terraform mktemp; do
  if ! command -v "${binary}" >/dev/null 2>&1; then
    fail "Required binary '${binary}' is not available"
  fi
done

if [[ "${EXPECTED_RESULT}" == "success" ]]; then
  for binary in curl unzip; do
    if ! command -v "${binary}" >/dev/null 2>&1; then
      fail "Required binary '${binary}' is not available (needed for the success path)"
    fi
  done
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

MIRROR_DIR="${WORKDIR}/mirror"
FIXTURE_COPY="${WORKDIR}/fixture"
OUTPUT_FILE="${WORKDIR}/validate-output.txt"
TERRAFORM_RC="${WORKDIR}/terraform.rc"

# Mirror path structure matches /opt/terraform-provider-mirror in the runner
# image (Dockerfile RUN layer) and the include rule in config/terraform.rc.
PROVIDER_MIRROR_PATH="${MIRROR_DIR}/registry.terraform.io/hashicorp/aws/${PROVIDER_VERSION}/linux_amd64"
mkdir -p "${PROVIDER_MIRROR_PATH}"

cp -R "${FIXTURE_PATH}" "${FIXTURE_COPY}"
find "${FIXTURE_COPY}" -type d -name '.terraform' -prune -exec rm -rf {} +
find "${FIXTURE_COPY}" -type f \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.backup' -o -name 'tfplan' \) -delete

if [[ "${EXPECTED_RESULT}" == "success" ]]; then
  log "Downloading hashicorp/aws ${PROVIDER_VERSION} into local mirror"
  curl -fsSL "https://releases.hashicorp.com/terraform-provider-aws/${PROVIDER_VERSION}/terraform-provider-aws_${PROVIDER_VERSION}_linux_amd64.zip" \
    -o "${WORKDIR}/terraform-provider-aws.zip"
  unzip -q "${WORKDIR}/terraform-provider-aws.zip" -d "${PROVIDER_MIRROR_PATH}"
else
  log "Failure path — mirror intentionally empty, no download required"
fi

# Terraform CLI config mirrors config/terraform.rc: filesystem mirror only,
# with the same include constraint (hashicorp/aws exclusively).
cat > "${TERRAFORM_RC}" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "${MIRROR_DIR}"
    include = ["registry.terraform.io/hashicorp/aws"]
  }
}
EOF

export TF_CLI_CONFIG_FILE="${TERRAFORM_RC}"
export INCA_SUPPORTED_TERRAFORM_PROVIDER="registry.terraform.io/hashicorp/aws"
export INCA_SUPPORTED_TERRAFORM_PROVIDER_VERSION="${PROVIDER_VERSION}"

set +e
bash "${REPO_ROOT}/scripts/runner/validate.sh" "${FIXTURE_COPY}" >"${OUTPUT_FILE}" 2>&1
STATUS=$?
set -e

cat "${OUTPUT_FILE}"

if [[ "${EXPECTED_RESULT}" == "success" ]]; then
  if [[ "${STATUS}" -ne 0 ]]; then
    fail "Expected validation success for '${FIXTURE_PATH}', but it failed"
  fi
  log "Offline mirror success path passed"
  exit 0
fi

if [[ "${STATUS}" -eq 0 ]]; then
  fail "Expected validation failure for '${FIXTURE_PATH}', but it succeeded"
fi

if ! grep -q "embedded provider mirror" "${OUTPUT_FILE}"; then
  fail "Expected failure output to mention the embedded provider mirror constraint"
fi

log "Offline mirror failure path passed"

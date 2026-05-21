#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

workspace="${1:-}"
if [[ -z "${workspace}" ]]; then
  fail "Usage: find_terraform_root.sh <workspace-directory>"
fi

if [[ -f "${workspace}/main.tf" ]]; then
  printf '%s' "${workspace}"
  exit 0
fi

candidate_count="$(find "${workspace}" -mindepth 2 -maxdepth 2 -type f -name 'main.tf' | wc -l | tr -d ' ')"

if [[ "${candidate_count}" == "1" ]]; then
  find "${workspace}" -mindepth 2 -maxdepth 2 -type f -name 'main.tf' -print -quit | xargs dirname
  exit 0
fi

fail "Unable to determine a unique Terraform root in extracted archive '${workspace}'"

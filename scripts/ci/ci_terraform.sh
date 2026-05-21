#!/bin/sh
# CI helper functions for Terraform pipelines.
# Source this file in job scripts: . scripts/ci/ci_terraform.sh

. scripts/runner/common.sh

validate_plan_artifacts() {
  local metadata_file="$1"
  local plan_file="$2"

  test -f "${plan_file}" \
    || fail "Expected Terraform plan artifact ${plan_file} is missing"
  test -f "${metadata_file}" \
    || fail "Expected Terraform metadata artifact ${metadata_file} is missing"

  . "${metadata_file}"
  log "Recorded PLAN_PIPELINE_ID=${PLAN_PIPELINE_ID:-<missing>}"
  log "Recorded PLAN_COMMIT_SHA=${PLAN_COMMIT_SHA:-<missing>}"

  test "${PLAN_PIPELINE_ID:-}" = "${CI_PIPELINE_ID}" \
    || fail "Recorded PLAN_PIPELINE_ID must match ${CI_PIPELINE_ID}"
  test "${PLAN_COMMIT_SHA:-}" = "${CI_COMMIT_SHA}" \
    || fail "Recorded PLAN_COMMIT_SHA must match ${CI_COMMIT_SHA}"
}

# Downloads the latest plan artifact for a given job name on the current branch
# via the GitLab API, then verifies the plan was generated on the current commit.
#
# Searches both parent pipelines and their child (downstream) pipelines because
# all plan and apply jobs run inside a child pipeline triggered by
# trigger_application_pipeline. The legacy /jobs/artifacts/:ref/download endpoint
# only searches parent pipeline jobs and always returns 404 for child pipeline jobs.
download_and_validate_plan_artifact() {
  local job_name="$1"
  local metadata_file="$2"
  local plan_file="$3"

  command -v curl  >/dev/null 2>&1 || { command -v apk >/dev/null 2>&1 && apk add --no-cache --quiet curl; }
  command -v jq    >/dev/null 2>&1 || { command -v apk >/dev/null 2>&1 && apk add --no-cache --quiet jq; }
  command -v unzip >/dev/null 2>&1 || { command -v apk >/dev/null 2>&1 && apk add --no-cache --quiet unzip; }

  local api="${CI_SERVER_URL}/api/v4/projects/${CI_PROJECT_ID}"
  local job_id=""

  log "Searching for successful artifact of job '${job_name}' on branch '${CI_COMMIT_REF_NAME}'..."

  # Iterate over the 20 most recent pipelines on this branch (covers any
  # PIPELINE_ACTION=plan run done before this apply pipeline was triggered).
  local pipeline_ids
  pipeline_ids=$(curl --fail --silent \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${api}/pipelines?ref=${CI_COMMIT_REF_NAME}&per_page=20" \
    | jq -r '.[].id') || pipeline_ids=""

  for pid in ${pipeline_ids}; do
    # 1. Search jobs directly in this pipeline (plain pipeline, no child).
    local jobs
    jobs=$(curl --fail --silent \
      --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
      "${api}/pipelines/${pid}/jobs?per_page=100&scope[]=success") || jobs="[]"

    job_id=$(printf '%s' "${jobs}" | jq -r --arg n "${job_name}" \
      '.[] | select(.name == $n) | .id' | head -1)

    if [ -n "${job_id}" ] && [ "${job_id}" != "null" ]; then
      log "Found job '${job_name}' (id=${job_id}) in pipeline ${pid}"
      break
    fi

    # 2. Search child (downstream) pipelines triggered from this parent.
    local bridges child_ids
    bridges=$(curl --fail --silent \
      --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
      "${api}/pipelines/${pid}/bridges?per_page=20") || bridges="[]"

    child_ids=$(printf '%s' "${bridges}" | jq -r '.[].downstream_pipeline.id // empty')

    for child_id in ${child_ids}; do
      local child_jobs
      child_jobs=$(curl --fail --silent \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
        "${api}/pipelines/${child_id}/jobs?per_page=100&scope[]=success") || child_jobs="[]"

      job_id=$(printf '%s' "${child_jobs}" | jq -r --arg n "${job_name}" \
        '.[] | select(.name == $n) | .id' | head -1)

      if [ -n "${job_id}" ] && [ "${job_id}" != "null" ]; then
        log "Found job '${job_name}' (id=${job_id}) in child pipeline ${child_id} (parent ${pid})"
        break 2
      fi
    done
  done

  if [ -z "${job_id}" ] || [ "${job_id}" = "null" ]; then
    fail "No successful artifact found for job '${job_name}' on branch '${CI_COMMIT_REF_NAME}'.

  Possible causes:
    - No plan pipeline has run on this branch yet
    - The plan artifact has expired (artifacts expire after 1 hour)
    - The plan pipeline failed before saving the artifact

  To fix: trigger a new pipeline with PIPELINE_ACTION=plan on branch '${CI_COMMIT_REF_NAME}',
  then re-trigger this apply pipeline."
  fi

  log "Downloading artifacts for job id=${job_id}..."
  curl --fail --silent --show-error --location \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${api}/jobs/${job_id}/artifacts" \
    -o /tmp/plan_artifacts.zip \
    || fail "Failed to download artifacts for job id=${job_id}"

  log "Extracting plan artifact..."
  unzip -o /tmp/plan_artifacts.zip -d "${CI_PROJECT_DIR}"

  test -f "${plan_file}" \
    || fail "Terraform plan file '${plan_file}' not found after extraction."
  test -f "${metadata_file}" \
    || fail "Plan metadata file '${metadata_file}' not found after extraction."

  . "${metadata_file}"
  log "Plan was generated on commit ${PLAN_COMMIT_SHA:-<missing>}, current HEAD is ${CI_COMMIT_SHA}."

  test "${PLAN_COMMIT_SHA:-}" = "${CI_COMMIT_SHA}" \
    || fail "Plan commit ${PLAN_COMMIT_SHA:-unknown} does not match current HEAD ${CI_COMMIT_SHA}. Run a new plan before applying."

  log "Commit SHA verified — applying plan from commit ${CI_COMMIT_SHA}."
}

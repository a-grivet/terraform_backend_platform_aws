#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../runner/common.sh"

AWS_REGION="${AWS_REGION:-eu-west-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-inca-terraform-runner}"
IMAGE_TAG="${IMAGE_TAG:-local}"
DOCKERFILE_PATH="${DOCKERFILE_PATH:-Dockerfile}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.14.7}"
AWS_CLI_VERSION="${AWS_CLI_VERSION:-2.17.44}"

ACCOUNT_ID="$(aws sts get-caller-identity --query 'Account' --output text)"
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
DOCKER_IMAGE="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

log "Ensuring ECR repository ${ECR_REPOSITORY} exists in ${AWS_REGION}"
aws ecr describe-repositories \
  --repository-names "${ECR_REPOSITORY}" \
  --region "${AWS_REGION}" >/dev/null 2>&1 || \
aws ecr create-repository \
  --repository-name "${ECR_REPOSITORY}" \
  --image-scanning-configuration scanOnPush=true \
  --region "${AWS_REGION}" >/dev/null

log "Logging into ECR ${ECR_REGISTRY}"
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

log "Building image ${DOCKER_IMAGE}"
docker build \
  --build-arg TERRAFORM_VERSION="${TERRAFORM_VERSION}" \
  --build-arg AWS_CLI_VERSION="${AWS_CLI_VERSION}" \
  -f "${DOCKERFILE_PATH}" \
  -t "${DOCKER_IMAGE}" \
  "${BUILD_CONTEXT}"

log "Pushing image ${DOCKER_IMAGE}"
docker push "${DOCKER_IMAGE}"

log "Image successfully pushed to ${DOCKER_IMAGE}"

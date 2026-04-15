#!/bin/bash
# ==============================================================================
# destroy.sh
# ==============================================================================
# Tears down the cartoonify stack in reverse order:
#   04-webapp  → 03-api → 01-backend
# The 02-worker stage has no Terraform state (build only).
# ==============================================================================

export AWS_DEFAULT_REGION="us-east-1"
set -euo pipefail

# ------------------------------------------------------------------------------
# Discover names before backend is destroyed.
# ------------------------------------------------------------------------------
pushd 01-backend > /dev/null
WEB_BUCKET=$(terraform output -raw web_bucket_name 2>/dev/null || true)
MEDIA_BUCKET=$(terraform output -raw media_bucket_name 2>/dev/null || true)
popd > /dev/null

if [ -z "${WEB_BUCKET}" ] || [ -z "${MEDIA_BUCKET}" ]; then
  echo "ERROR: Could not read bucket names from 01-backend Terraform state."
  echo "       Is 01-backend initialized and applied?"
  exit 1
fi

# ==============================================================================
# STAGE 04 — WEBAPP
# ==============================================================================
echo "NOTE: Destroying webapp..."

pushd 04-webapp > /dev/null
terraform init
terraform destroy -auto-approve -var="web_bucket_name=${WEB_BUCKET}"
popd > /dev/null

# ==============================================================================
# STAGE 03 — API
# ==============================================================================
echo "NOTE: Destroying API..."

pushd 03-api > /dev/null
terraform init
terraform destroy -auto-approve \
  -var="media_bucket_name=${MEDIA_BUCKET}" \
  -var="worker_image_tag=worker-rc1"
popd > /dev/null

# ==============================================================================
# MEDIA BUCKET CLEANUP
# ==============================================================================
# The media bucket may contain uploaded originals and generated cartoons
# that are retained for 7 days by lifecycle rules. Empty it before backend
# Terraform destroys the bucket (force_destroy is enabled, but explicit
# empty is clearer and avoids partial-failure surprises).
# ==============================================================================
echo "NOTE: Emptying media bucket ${MEDIA_BUCKET}..."
aws s3 rm "s3://${MEDIA_BUCKET}" --recursive || true

# ==============================================================================
# STAGE 01 — BACKEND
# ==============================================================================
echo "NOTE: Destroying backend..."

pushd 01-backend > /dev/null
terraform init
terraform destroy -auto-approve
popd > /dev/null

echo "NOTE: Infrastructure teardown complete."

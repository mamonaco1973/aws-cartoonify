#!/bin/bash
# ==============================================================================
# validate.sh
# ==============================================================================
# Prints the app URL and API endpoint after apply.sh completes.
# ==============================================================================

export AWS_DEFAULT_REGION="us-east-1"
set -euo pipefail

WEB_BUCKET=$(terraform -chdir=01-backend output -raw web_bucket_name 2>/dev/null || true)
API_BASE=$(terraform  -chdir=03-api    output -raw api_endpoint    2>/dev/null || true)

if [ -z "${WEB_BUCKET}" ] || [ -z "${API_BASE}" ]; then
  echo "ERROR: Could not read Terraform outputs. Run ./apply.sh first."
  exit 1
fi

BUCKET_URL="https://${WEB_BUCKET}.s3.${AWS_DEFAULT_REGION}.amazonaws.com"

echo ""
echo "================================================================================="
echo "  Cartoonify — Deployment validated!"
echo "================================================================================="
echo "  API : ${API_BASE}"
echo "  Web : ${BUCKET_URL}/index.html"
echo "================================================================================="

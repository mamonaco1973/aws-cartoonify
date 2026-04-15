#!/bin/bash
# ===============================================================================
# File: validate.sh
# ===============================================================================

# ------------------------------------------------------------------------------
# Step 1: Print out test web application URL.
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# SELECT WEB BUCKET BY PREFIX
# ------------------------------------------------------------------------------
# Finds the S3 bucket used for hosting the web client by matching a
# known prefix. Exactly one bucket must match.
# ------------------------------------------------------------------------------
PREFIX="cnotes"

read -r -a BUCKETS <<< "$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, \`${PREFIX}\`)].Name" \
  --output text)"

# ------------------------------------------------------------------------------
# ENFORCE A SINGLE BUCKET MATCH
# ------------------------------------------------------------------------------
# Avoids deploying to the wrong bucket by requiring exactly one match.
# ------------------------------------------------------------------------------
if [[ "${#BUCKETS[@]}" -eq 0 ]]; then
  echo "ERROR: No S3 bucket found starting with '${PREFIX}'" >&2
  exit 1
elif [[ "${#BUCKETS[@]}" -gt 1 ]]; then
  echo "ERROR: Multiple S3 buckets found starting with '${PREFIX}':" >&2
  for b in "${BUCKETS[@]}"; do
    echo "  - ${b}" >&2
  done
  exit 1
fi

BUCKET_NAME="${BUCKETS[0]}"
echo "NOTE: Bucket name is ${BUCKET_NAME}"

# ------------------------------------------------------------------------------
# DETERMINE BUCKET REGION
# ------------------------------------------------------------------------------
# S3 returns "None" for buckets in us-east-1. Normalize this to the
# canonical region name so we can build a correct bucket URL.
# ------------------------------------------------------------------------------
REGION=$(aws s3api get-bucket-location \
  --bucket "${BUCKET_NAME}" \
  --query "LocationConstraint" \
  --output text)

if [[ "${REGION}" == "None" ]]; then
  REGION="us-east-1"
fi

# ------------------------------------------------------------------------------
# BUILD REGION-AWARE BUCKET URL
# ------------------------------------------------------------------------------
# Used for redirect URIs (callback.html) and other hosted assets.
# ------------------------------------------------------------------------------
BUCKET_URL="https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com"

echo "NOTE: Test application URL - ${BUCKET_URL}/index.html"

# ------------------------------------------------------------------------------
# Step 2: Discover API Gateway endpoint
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"

API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='notes-api-cognito'].ApiId" \
  --output text)

if [[ -z "${API_ID}" || "${API_ID}" == "None" ]]; then
  echo "ERROR: No API found with name 'notes-api-cognito'"
  exit 1
fi

API_BASE=$(aws apigatewayv2 get-api \
  --api-id "${API_ID}" \
  --query "ApiEndpoint" \
  --output text)

# ------------------------------------------------------------------------------
# Step 3: Print Google OAuth values needed for Cognito federation.
# ------------------------------------------------------------------------------
# Google Console needs:
#   - Authorized JavaScript origins: where your SPA runs (this S3 origin)
#   - Authorized redirect URIs: where Google sends the auth response (Cognito)
# ------------------------------------------------------------------------------

# Pull Cognito domain prefix from Terraform outputs (01-lambdas)
COGNITO_DOMAIN="$(terraform -chdir=01-lambdas output -raw cognito_domain 2>/dev/null)"

if [[ -z "${COGNITO_DOMAIN}" ]]; then
  echo "ERROR: Could not read Terraform output 'cognito_domain' from 01-lambdas."
  echo "       Run './apply.sh' (or 'terraform -chdir=01-lambdas apply') first."
  exit 1
fi

COGNITO_IDP_RESPONSE_URL="https://${COGNITO_DOMAIN}.auth.${REGION}.amazoncognito.com/oauth2/idpresponse"

echo ""
echo "================================================================================="
echo "Google Cloud Console (OAuth Client) values"
echo "================================================================================="
echo "Authorized JavaScript origins:"
echo "  ${BUCKET_URL}"
echo ""
echo "Authorized redirect URIs:"
echo "  ${COGNITO_IDP_RESPONSE_URL}"
echo "================================================================================="

echo ""
echo "================================================================================="
echo "  Deployment validated!"
echo "================================================================================="
echo "  API : ${API_BASE}"
echo "  Web : ${BUCKET_URL}/index.html"
echo "================================================================================="

#!/bin/bash
# ================================================================================
# File: apply.sh
# ================================================================================
#
# Purpose:
#   Orchestrates end-to-end deployment of the Notes application stack.
#
#   Workflow:
#     - Validate the local environment and AWS credentials
#     - Deploy backend (Lambdas, API Gateway, Cognito) via Terraform
#     - Discover the web S3 bucket and derive its region-aware URL
#     - Generate the web client artifacts (index.html, config.json)
#     - Deploy the web client via Terraform, targeting the existing bucket
#
# ================================================================================
# GLOBAL CONFIGURATION
# ================================================================================

# ------------------------------------------------------------------------------
# AWS REGION CONFIGURATION
# ------------------------------------------------------------------------------
# Defines the default AWS region used by AWS CLI and Terraform.
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"

# ------------------------------------------------------------------------------
# STRICT SHELL EXECUTION MODE
# ------------------------------------------------------------------------------
# Enforces defensive shell behavior:
#   -e  Exit immediately if any command fails
#   -u  Treat unset variables as errors
#   -o pipefail  Fail pipelines if any command fails
# ------------------------------------------------------------------------------
set -euo pipefail

# ================================================================================
# ENVIRONMENT PRE-CHECK
# ================================================================================

# ------------------------------------------------------------------------------
# ENVIRONMENT VALIDATION
# ------------------------------------------------------------------------------
# Ensures required tools, credentials, and environment variables exist
# before any deployment is attempted.
# ------------------------------------------------------------------------------
echo "NOTE: Running environment validation..."

./check_env.sh
if [ $? -ne 0 ]; then
  echo "ERROR: Environment validation failed. Exiting."
  exit 1
fi

# ================================================================================
# BACKEND DEPLOYMENT (LAMBDAS + API GATEWAY + COGNITO)
# ================================================================================

# ------------------------------------------------------------------------------
# DEPLOY BACKEND INFRASTRUCTURE
# ------------------------------------------------------------------------------
# Applies Terraform in 01-lambdas to create the backend stack, including:
#   - Lambda functions
#   - API Gateway (HTTP API)
#   - Cognito (domain + app client outputs are read later)
# ------------------------------------------------------------------------------
echo "NOTE: Building Lambdas and API Gateway..."

cd 01-lambdas || {
  echo "ERROR: 01-lambdas directory missing."
  exit 1
}

terraform init
terraform apply -auto-approve

cd .. || exit 1

# ================================================================================
# WEB BUCKET DISCOVERY
# ================================================================================

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

# ================================================================================
# WEB CLIENT CONFIGURATION
# ================================================================================

# ------------------------------------------------------------------------------
# LOOK UP API GATEWAY ENDPOINT
# ------------------------------------------------------------------------------
# Retrieves the API ID by name, then reads the API endpoint URL for
# injection into the web client template and config.json.
# ------------------------------------------------------------------------------
API_ID=$(aws apigatewayv2 get-apis \
  --query "Items[?Name=='notes-api-cognito'].ApiId" \
  --output text)

if [[ -z "${API_ID}" || "${API_ID}" == "None" ]]; then
  echo "ERROR: No API found with name 'notes-api-cognito'"
  exit 1
fi

URL=$(aws apigatewayv2 get-api \
  --api-id "${API_ID}" \
  --query "ApiEndpoint" \
  --output text)

export API_BASE="${URL}"
echo "NOTE: API Gateway URL - ${API_BASE}"

# ================================================================================
# WEB CLIENT BUILD + DEPLOYMENT
# ================================================================================

# ------------------------------------------------------------------------------
# BUILD WEB CLIENT ARTIFACTS
# ------------------------------------------------------------------------------
# Generates:
#   - index.html from index.html.tmpl (API_BASE substitution)
#   - config.json using Cognito outputs and the bucket callback URL
# ------------------------------------------------------------------------------
echo "NOTE: Building web application..."

cd 02-webapp || {
  echo "ERROR: 02-webapp directory missing."
  exit 1
}

envsubst '${API_BASE}' < index.html.tmpl > index.html || {
  echo "ERROR: Failed to generate index.html."
  exit 1
}

# ------------------------------------------------------------------------------
# READ COGNITO OUTPUTS FROM BACKEND STACK
# ------------------------------------------------------------------------------
# Reads Terraform outputs from 01-lambdas to configure the SPA login:
#   - Cognito domain prefix
#   - App client ID
# ------------------------------------------------------------------------------
echo "NOTE: Reading Cognito outputs..."

COGNITO_DOMAIN_PREFIX=$(cd ../01-lambdas && terraform output -raw cognito_domain)
CLIENT_ID=$(cd ../01-lambdas && terraform output -raw app_client_id)

if [[ -z "${COGNITO_DOMAIN_PREFIX}" || -z "${CLIENT_ID}" ]]; then
  echo "ERROR: Failed to read Cognito outputs."
  exit 1
fi

# ------------------------------------------------------------------------------
# BUILD COGNITO DOMAIN
# ------------------------------------------------------------------------------
# Constructs the Cognito Hosted UI domain from the domain prefix and
# the region derived from the web bucket.
# ------------------------------------------------------------------------------
COGNITO_DOMAIN="${COGNITO_DOMAIN_PREFIX}.auth.${REGION}.amazoncognito.com"

# ------------------------------------------------------------------------------
# WRITE WEB CLIENT CONFIGURATION
# ------------------------------------------------------------------------------
# Writes config.json consumed by the SPA. redirectUri must match the
# Hosted UI callback URL registered in the Cognito app client.
# ------------------------------------------------------------------------------
echo "NOTE: Writing config.json..."

cat > config.json <<EOF
{
  "cognitoDomain": "${COGNITO_DOMAIN}",
  "clientId": "${CLIENT_ID}",
  "redirectUri": "${BUCKET_URL}/callback.html",
  "apiBaseUrl": "${API_BASE}"
}
EOF

# ------------------------------------------------------------------------------
# DEPLOY WEB CLIENT (TERRAFORM)
# ------------------------------------------------------------------------------
# Applies Terraform in 02-webapp, targeting an existing bucket passed
# via web_bucket_name. This module should not create the bucket.
# ------------------------------------------------------------------------------
terraform init
terraform apply -auto-approve \
  -var="web_bucket_name=${BUCKET_NAME}"

cd .. || exit 1

# ================================================================================
# POST-DEPLOYMENT VALIDATION (OPTIONAL)
# ================================================================================

# ------------------------------------------------------------------------------
# RUNTIME VALIDATION
# ------------------------------------------------------------------------------
# Enable once validate.sh is implemented.
# ------------------------------------------------------------------------------
echo "NOTE: Running post-deployment validation..."
./validate.sh

# ================================================================================
# END OF SCRIPT
# ================================================================================

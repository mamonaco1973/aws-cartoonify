#!/bin/bash
# ==============================================================================
# apply.sh
# ==============================================================================
# Orchestrates deployment of the cartoonify stack in four stages:
#   01-backend : SQS, DynamoDB, S3 buckets (web + media), ECR, Cognito
#   02-worker  : Docker build of the Bedrock Nova Canvas worker → ECR
#   03-api     : API Gateway + 5 API Lambdas + worker Lambda + SQS trigger
#   04-webapp  : Upload SPA (index.html, callback.html, config.json, favicon)
#                to the web bucket created in 01-backend
#
# Requires: aws, terraform, docker, jq, envsubst
# ==============================================================================

export AWS_DEFAULT_REGION="us-east-1"
set -euo pipefail

WORKER_TAG="worker-rc2"

# ------------------------------------------------------------------------------
# Pre-flight
# ------------------------------------------------------------------------------
echo "NOTE: Running environment validation..."
./check_env.sh

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "${AWS_ACCOUNT_ID}" ]; then
  echo "ERROR: Could not retrieve AWS account ID."
  exit 1
fi

# ==============================================================================
# STAGE 01 — BACKEND (S3, DynamoDB, SQS, ECR, Cognito)
# ==============================================================================
echo "NOTE: Stage 01 — provisioning backend resources..."

pushd 01-backend > /dev/null
terraform init
terraform apply -auto-approve

WEB_BUCKET=$(terraform output -raw web_bucket_name)
MEDIA_BUCKET=$(terraform output -raw media_bucket_name)
COGNITO_DOMAIN_PREFIX=$(terraform output -raw cognito_domain)
CLIENT_ID=$(terraform output -raw app_client_id)
WORKER_REPO=$(terraform output -raw worker_repo_name)
popd > /dev/null

echo "NOTE: web_bucket   = ${WEB_BUCKET}"
echo "NOTE: media_bucket = ${MEDIA_BUCKET}"

# ==============================================================================
# STAGE 02 — DOCKER BUILD + PUSH (Bedrock worker image)
# ==============================================================================
echo "NOTE: Stage 02 — building worker Docker image..."

ECR_HOST="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_DEFAULT_REGION}.amazonaws.com"
IMAGE_URI="${ECR_HOST}/${WORKER_REPO}:${WORKER_TAG}"

aws ecr get-login-password --region "${AWS_DEFAULT_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_HOST}"

pushd 02-worker/cartoonify > /dev/null

if aws ecr describe-images \
      --repository-name "${WORKER_REPO}" \
      --image-ids imageTag="${WORKER_TAG}" \
      --region "${AWS_DEFAULT_REGION}" > /dev/null 2>&1; then
  echo "NOTE: Image already exists in ECR: ${IMAGE_URI}"
else
  echo "NOTE: Building image ${IMAGE_URI}"
  docker buildx build \
    --platform linux/amd64 \
    --provenance=false \
    --sbom=false \
    --output type=docker \
    -t "${IMAGE_URI}" .
  docker push "${IMAGE_URI}"
fi

popd > /dev/null

# ==============================================================================
# STAGE 03 — API (API Gateway, API Lambdas, worker Lambda, SQS trigger)
# ==============================================================================
echo "NOTE: Stage 03 — deploying API Gateway and Lambdas..."

pushd 03-api > /dev/null
terraform init
terraform apply -auto-approve \
  -var="media_bucket_name=${MEDIA_BUCKET}" \
  -var="worker_image_tag=${WORKER_TAG}"

API_BASE=$(terraform output -raw api_endpoint)
popd > /dev/null

echo "NOTE: api_endpoint = ${API_BASE}"

# ==============================================================================
# STAGE 04 — WEB APP (generate index.html + config.json, upload to web bucket)
# ==============================================================================
echo "NOTE: Stage 04 — building and uploading SPA..."

pushd 04-webapp > /dev/null

export API_BASE
envsubst '${API_BASE}' < index.html.tmpl > index.html

COGNITO_DOMAIN="${COGNITO_DOMAIN_PREFIX}.auth.${AWS_DEFAULT_REGION}.amazoncognito.com"
BUCKET_URL="https://${WEB_BUCKET}.s3.${AWS_DEFAULT_REGION}.amazonaws.com"

cat > config.json <<EOF
{
  "cognitoDomain": "${COGNITO_DOMAIN}",
  "clientId":      "${CLIENT_ID}",
  "redirectUri":   "${BUCKET_URL}/callback.html",
  "apiBaseUrl":    "${API_BASE}"
}
EOF

terraform init
terraform apply -auto-approve -var="web_bucket_name=${WEB_BUCKET}"

popd > /dev/null

# ==============================================================================
# Validation
# ==============================================================================
echo "NOTE: Running post-deployment validation..."
./validate.sh

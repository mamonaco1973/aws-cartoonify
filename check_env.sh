#!/bin/bash
# ==============================================================================
# check_env.sh
# ==============================================================================
# Validates the local tooling and AWS credentials needed for apply.sh and
# destroy.sh. Also confirms that Bedrock access to Nova Canvas is available
# in the target region.
# ==============================================================================

set -u

REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "NOTE: Validating that required commands are found in your PATH."
commands=("aws" "terraform" "docker" "jq" "envsubst")
missing=0
for cmd in "${commands[@]}"; do
  if ! command -v "$cmd" > /dev/null 2>&1; then
    echo "ERROR: $cmd is not found in the current PATH."
    missing=1
  else
    echo "NOTE: $cmd is found in the current PATH."
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "ERROR: One or more required commands are missing."
  exit 1
fi

echo "NOTE: Checking AWS cli connection."
if ! aws sts get-caller-identity --query "Account" --output text > /dev/null 2>&1; then
  echo "ERROR: Failed to connect to AWS. Check credentials/environment."
  exit 1
fi
echo "NOTE: Successfully logged into AWS."

MODEL_ID="stability.stable-image-control-structure-v1:0"
echo "NOTE: Checking Bedrock access to ${MODEL_ID} in ${REGION}."
if ! aws bedrock list-foundation-models --region "${REGION}" \
       --query "modelSummaries[?modelId=='${MODEL_ID}'].modelId" \
       --output text 2>/dev/null | grep -q "${MODEL_ID}"; then
  echo "ERROR: ${MODEL_ID} is not available in ${REGION}."
  echo "       Enable model access in the Bedrock console:"
  echo "         https://console.aws.amazon.com/bedrock/home?region=${REGION}#/modelaccess"
  exit 1
fi
echo "NOTE: Bedrock model is accessible."

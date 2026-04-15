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

PROFILE_ID="us.stability.stable-image-control-structure-v1:0"
MODEL_ID="stability.stable-image-control-structure-v1:0"

echo "NOTE: Checking Bedrock inference profile ${PROFILE_ID} in ${REGION}."

# Check 1: Profile exists
if ! aws bedrock list-inference-profiles --region "${REGION}" \
       --query "inferenceProfileSummaries[?inferenceProfileId=='${PROFILE_ID}'].inferenceProfileId" \
       --output text 2>/dev/null | grep -q "${PROFILE_ID}"; then
  echo "ERROR: Inference profile ${PROFILE_ID} is not available in ${REGION}."
  echo "       Enable access: https://console.aws.amazon.com/bedrock/home?region=${REGION}#/modelaccess"
  exit 1
fi

echo "NOTE: Testing Bedrock model invocation (dry-run)..."
TEST_PAYLOAD=$(echo '{"image":"","prompt":"test","control_strength":0.5,"output_format":"png"}' | base64)

if ! aws bedrock invoke-model \
  --region "${REGION}" \
  --model-id "${PROFILE_ID}" \
  --content-type "application/json" \
  --accept "application/json" \
  --body '{"image":"iVBORw0KGgo=","prompt":"test","output_format":"png"}' \
  /tmp/bedrock-test-out.json 2>&1 | grep -qE "ValidationException|could not be satisfied"; then
    ERR=$(cat /tmp/bedrock-test-out.json 2>/dev/null)
    if echo "$ERR" | grep -q "AccessDeniedException"; then
        echo "ERROR: Bedrock invocation failed — likely missing Marketplace subscription."
        echo "       Go to: https://console.aws.amazon.com/bedrock/home?region=${REGION}#/modelaccess"
        echo "       And verify: https://console.aws.amazon.com/marketplace/home#/subscriptions"
        exit 1
    fi
fi
echo "NOTE: Bedrock invocation access confirmed."



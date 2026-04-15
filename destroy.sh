#!/bin/bash
# ================================================================================
# File: destroy.sh
# ================================================================================
#
# Purpose:
#   Tears down the Notes application stack deployed by apply.sh.
#
#   Destruction order:
#     1. Static web client (02-webapp)
#     2. Backend services (01-lambdas)
#
#   The S3 web bucket is discovered dynamically and passed into the
#   web teardown module to ensure the correct resources are targeted.
#
# ================================================================================
# GLOBAL CONFIGURATION
# ================================================================================

# ------------------------------------------------------------------------------
# AWS REGION CONFIGURATION
# ------------------------------------------------------------------------------
# Sets the default AWS region used by:
#   - AWS CLI commands
#   - Terraform providers
# ------------------------------------------------------------------------------
export AWS_DEFAULT_REGION="us-east-1"

# ------------------------------------------------------------------------------
# STRICT SHELL EXECUTION MODE
# ------------------------------------------------------------------------------
# Enforces defensive Bash behavior:
#   -e  Exit immediately on command failure
#   -u  Treat unset variables as errors
#   -o pipefail  Fail pipelines if any command fails
# ------------------------------------------------------------------------------
set -euo pipefail

# ================================================================================
# WEB BUCKET DISCOVERY
# ================================================================================

# ------------------------------------------------------------------------------
# SELECT WEB BUCKET BY PREFIX
# ------------------------------------------------------------------------------
# Finds the S3 bucket hosting the static web client by matching a
# known prefix. Exactly one bucket must match.
# ------------------------------------------------------------------------------
PREFIX="cnotes"

read -r -a BUCKETS <<< "$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, \`${PREFIX}\`)].Name" \
  --output text)"

# ------------------------------------------------------------------------------
# ENFORCE A SINGLE BUCKET MATCH
# ------------------------------------------------------------------------------
# Prevents accidental teardown of unintended buckets.
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

# ================================================================================
# STATIC WEB APPLICATION TEARDOWN
# ================================================================================

# ------------------------------------------------------------------------------
# DESTROY STATIC WEB CLIENT
# ------------------------------------------------------------------------------
# Destroys the S3-hosted static web application and associated
# Terraform-managed resources in the 02-webapp directory.
# ------------------------------------------------------------------------------
echo "NOTE: Destroying Web Application..."

cd 02-webapp || {
  echo "ERROR: Directory 02-webapp not found."
  exit 1
}

terraform init
terraform destroy -auto-approve \
  -var="web_bucket_name=${BUCKET_NAME}"

cd .. || exit 1

# ================================================================================
# BACKEND INFRASTRUCTURE TEARDOWN
# ================================================================================

# ------------------------------------------------------------------------------
# DESTROY BACKEND SERVICES
# ------------------------------------------------------------------------------
# Removes backend infrastructure provisioned by Terraform, including:
#   - Lambda functions
#   - API Gateway routes and integrations
# ------------------------------------------------------------------------------
echo "NOTE: Destroying Lambdas and API Gateway..."

cd 01-lambdas || {
  echo "ERROR: Directory 01-lambdas not found."
  exit 1
}

terraform init
terraform destroy -auto-approve

cd .. || exit 1

# ================================================================================
# COMPLETION
# ================================================================================

# ------------------------------------------------------------------------------
# TEARDOWN COMPLETE
# ------------------------------------------------------------------------------
# Indicates that all Terraform stacks were destroyed successfully.
# ------------------------------------------------------------------------------
echo "NOTE: Infrastructure teardown complete."

# ================================================================================
# END OF SCRIPT
# ================================================================================

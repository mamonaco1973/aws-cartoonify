# ==============================================================================
# bedrock-config.sh
# ==============================================================================
# Single source of truth for Bedrock model selection. Sourced by apply.sh and
# destroy.sh so both stay in sync.
#
# To switch models (e.g. to Nova Canvas or a newer Stability version), edit
# these three values. They flow to:
#   • check_env.sh        — pre-flight probe (via exported env)
#   • 03-api Terraform    — worker IAM Resource ARNs + worker Lambda env var
#   • 02-worker Lambda    — reads BEDROCK_MODEL_ID at runtime
#
# BEDROCK_MODEL_REGIONS lists every region the cross-region inference profile
# may route to. Each region needs a foundation-model ARN entry in IAM.
# ==============================================================================

export BEDROCK_MODEL_ID="stability.stable-image-control-structure-v1:0"
export BEDROCK_INFERENCE_PROFILE_ID="us.stability.stable-image-control-structure-v1:0"
export BEDROCK_MODEL_REGIONS='["us-east-1","us-east-2","us-west-2"]'

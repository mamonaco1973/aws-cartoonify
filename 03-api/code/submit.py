# ================================================================================
# submit.py — POST /generate
# ================================================================================
# Purpose:
#   Kick off a cartoonify job after the browser has uploaded the original via
#   the presigned POST returned by /upload-url.
#
#   Steps:
#     1. Validate style + job_id
#     2. Enforce daily quota (DAILY_QUOTA per Cognito user per UTC day)
#     3. Confirm the original object exists at originals/<owner>/<job_id>.*
#     4. Write the job row (status=submitted)
#     5. Enqueue the job on SQS for the worker
#
# Request body:  {"job_id": "...", "key": "...", "style": "..."}
# Response:      202 {"job_id": "...", "status": "submitted"}
#                429 when the daily quota has been reached
# ================================================================================

import json
import logging
import os
import time

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

from common import (
    ALLOWED_STYLES,
    DAILY_QUOTA,
    JOB_TTL_SECONDS,
    MAX_PROMPT_EXTRA,
    get_owner,
    job_id_ms,
    parse_body,
    response,
    start_of_utc_day_ms,
)

JOBS_TABLE_NAME = os.environ["JOBS_TABLE_NAME"]
MEDIA_BUCKET    = os.environ["MEDIA_BUCKET_NAME"]
JOBS_QUEUE_URL  = os.environ["JOBS_QUEUE_URL"]

dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(JOBS_TABLE_NAME)
s3       = boto3.client("s3")
sqs      = boto3.client("sqs")

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _count_today(owner: str) -> int:
    """Count jobs this owner has submitted since start of the current UTC day."""
    start_prefix = f"{start_of_utc_day_ms():013d}-"
    res = table.query(
        KeyConditionExpression = Key("owner").eq(owner) & Key("job_id").gte(start_prefix),
        Select = "COUNT",
    )
    return res.get("Count", 0)


def lambda_handler(event, context):
    try:
        owner = get_owner(event)
    except PermissionError as e:
        return response(401, {"error": str(e)})

    body         = parse_body(event)
    job_id       = body.get("job_id")
    style        = body.get("style")
    key          = body.get("key")
    prompt_extra = (body.get("prompt_extra") or "").strip()

    if not job_id or not key:
        return response(400, {"error": "Missing job_id or key"})

    if style not in ALLOWED_STYLES:
        return response(400, {"error": "Unsupported style",
                              "allowed": sorted(ALLOWED_STYLES)})

    if len(prompt_extra) > MAX_PROMPT_EXTRA:
        return response(400, {"error": f"prompt_extra exceeds {MAX_PROMPT_EXTRA} chars"})

    # Defend against a client reusing another user's key.
    expected_prefix = f"originals/{owner}/{job_id}."
    if not key.startswith(expected_prefix):
        return response(400, {"error": "Key does not match owner/job_id"})

    # Confirm the upload actually happened.
    try:
        s3.head_object(Bucket=MEDIA_BUCKET, Key=key)
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code")
        if code in ("404", "NoSuchKey", "NotFound"):
            return response(400, {"error": "Original not uploaded yet"})
        logger.exception("head_object failed")
        return response(500, {"error": "Failed to verify upload"})

    # Daily quota
    count = _count_today(owner)
    if count >= DAILY_QUOTA:
        return response(429, {
            "error":   f"Daily limit of {DAILY_QUOTA} reached",
            "used":    count,
            "resets":  "at 00:00 UTC",
        })

    # Write the job row. created_at is an epoch in seconds; ttl is 7 days out.
    now = int(time.time())
    created_at_ms = job_id_ms(job_id)
    item = {
        "owner":         owner,
        "job_id":        job_id,
        "status":        "submitted",
        "style":         style,
        "original_key":  key,
        "created_at":    now,
        "created_at_ms": created_at_ms,
        "ttl":           now + JOB_TTL_SECONDS,
    }
    if prompt_extra:
        item["prompt_extra"] = prompt_extra
    table.put_item(Item=item)

    sqs.send_message(
        QueueUrl    = JOBS_QUEUE_URL,
        MessageBody = json.dumps({
            "job_id":       job_id,
            "owner":        owner,
            "style":        style,
            "original_key": key,
            "prompt_extra": prompt_extra,
        }),
    )

    logger.info("Submitted job_id=%s owner=%s style=%s", job_id, owner, style)

    return response(202, {"job_id": job_id, "status": "submitted"})

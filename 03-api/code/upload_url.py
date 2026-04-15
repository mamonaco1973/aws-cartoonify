# ================================================================================
# upload_url.py — POST /upload-url
# ================================================================================
# Purpose:
#   Issue a presigned S3 POST so the browser can upload the original image
#   directly to the private media bucket.
#
#   The presigned POST policy enforces:
#     - content-length-range 0..MAX_UPLOAD_BYTES   (caps file size server-side)
#     - Content-Type exactly equal to the requested type
#     - Key exactly equal to originals/<owner>/<job_id>.<ext>
#
# Request body:   {"content_type": "image/jpeg"}
# Response body:  {"job_id": "...", "url": "...", "fields": {...}, "key": "..."}
# ================================================================================

import logging
import os

import boto3
from botocore.client import Config

from common import (
    ALLOWED_CONTENT_TYPES,
    MAX_UPLOAD_BYTES,
    get_owner,
    make_job_id,
    parse_body,
    response,
)

MEDIA_BUCKET = os.environ["MEDIA_BUCKET_NAME"]

# Use SigV4 explicitly; presigned POST requires it for content-length-range.
s3 = boto3.client("s3", config=Config(signature_version="s3v4"))

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    try:
        owner = get_owner(event)
    except PermissionError as e:
        return response(401, {"error": str(e)})

    body = parse_body(event)
    content_type = body.get("content_type")

    if content_type not in ALLOWED_CONTENT_TYPES:
        return response(400, {
            "error": "Unsupported content_type",
            "allowed": sorted(ALLOWED_CONTENT_TYPES.keys()),
        })

    ext = ALLOWED_CONTENT_TYPES[content_type]
    job_id = make_job_id()
    key = f"originals/{owner}/{job_id}.{ext}"

    presigned = s3.generate_presigned_post(
        Bucket = MEDIA_BUCKET,
        Key    = key,
        Fields = {"Content-Type": content_type},
        Conditions = [
            {"Content-Type": content_type},
            ["content-length-range", 0, MAX_UPLOAD_BYTES],
        ],
        ExpiresIn = 300,
    )

    logger.info("Issued presigned POST owner=%s job_id=%s key=%s", owner, job_id, key)

    return response(200, {
        "job_id": job_id,
        "key":    key,
        "url":    presigned["url"],
        "fields": presigned["fields"],
    })

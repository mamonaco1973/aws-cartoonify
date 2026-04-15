# ================================================================================
# result.py — GET /result/{job_id}
# ================================================================================
# Purpose:
#   Return the current status of a single job, plus presigned GET URLs for the
#   original and generated cartoon when available. Used by the SPA to poll
#   after submission.
#
# Response shape (200):
#   {
#     "job_id": "...",
#     "status": "submitted|processing|complete|error",
#     "style":  "...",
#     "created_at": 1700000000,
#     "original_url": "...",         # presigned, status>=submitted
#     "cartoon_url":  "...",         # presigned, status=complete
#     "error_message": "..."         # status=error only
#   }
# ================================================================================

import logging
import os

import boto3
from botocore.client import Config

from common import PRESIGNED_GET_TTL, get_owner, response

JOBS_TABLE_NAME = os.environ["JOBS_TABLE_NAME"]
MEDIA_BUCKET    = os.environ["MEDIA_BUCKET_NAME"]

dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(JOBS_TABLE_NAME)
s3       = boto3.client("s3", config=Config(signature_version="s3v4"))

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def _presign(key: str, download_filename: str | None = None) -> str:
    params = {"Bucket": MEDIA_BUCKET, "Key": key}
    if download_filename:
        # Forces "Save As" rather than inline render. <img src=...> ignores
        # Content-Disposition, so the same URL still works for tile display.
        params["ResponseContentDisposition"] = f'attachment; filename="{download_filename}"'
    return s3.generate_presigned_url(
        "get_object",
        Params    = params,
        ExpiresIn = PRESIGNED_GET_TTL,
    )


def lambda_handler(event, context):
    try:
        owner = get_owner(event)
    except PermissionError as e:
        return response(401, {"error": str(e)})

    path = event.get("pathParameters") or {}
    job_id = path.get("job_id")
    if not job_id:
        return response(400, {"error": "Missing job_id"})

    res = table.get_item(Key={"owner": owner, "job_id": job_id})
    item = res.get("Item")
    if not item:
        return response(404, {"error": "Not found"})

    out = {
        "job_id":     item["job_id"],
        "status":     item.get("status"),
        "style":      item.get("style"),
        "created_at": item.get("created_at"),
    }

    original_key = item.get("original_key")
    if original_key:
        out["original_url"] = _presign(original_key)

    cartoon_key = item.get("cartoon_key")
    if cartoon_key:
        out["cartoon_url"] = _presign(cartoon_key, f"cartoonify-{item['job_id']}.png")

    if item.get("error_message"):
        out["error_message"] = item["error_message"]

    return response(200, out)

# ================================================================================
# history.py — GET /history
# ================================================================================
# Purpose:
#   Return up to the 50 newest jobs for the authenticated user, newest first.
#   Each entry includes presigned GET URLs for the cartoon (when complete) so
#   the gallery view can render without additional round trips.
#
#   Jobs older than 7 days are removed by DynamoDB TTL and S3 lifecycle, so
#   this naturally self-bounds.
# ================================================================================

import logging
import os

import boto3
from boto3.dynamodb.conditions import Key
from botocore.client import Config

from common import PRESIGNED_GET_TTL, get_owner, response

JOBS_TABLE_NAME = os.environ["JOBS_TABLE_NAME"]
MEDIA_BUCKET    = os.environ["MEDIA_BUCKET_NAME"]
PAGE_SIZE       = 50

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

    # job_id is time-sortable → ScanIndexForward=False gives newest first.
    res = table.query(
        KeyConditionExpression = Key("owner").eq(owner),
        ScanIndexForward       = False,
        Limit                  = PAGE_SIZE,
    )

    items = []
    for item in res.get("Items", []):
        entry = {
            "job_id":     item["job_id"],
            "status":     item.get("status"),
            "style":      item.get("style"),
            "created_at": item.get("created_at"),
        }
        if item.get("cartoon_key"):
            entry["cartoon_url"] = _presign(item["cartoon_key"], f"cartoonify-{item['job_id']}.png")
        if item.get("original_key"):
            entry["original_url"] = _presign(item["original_key"])
        if item.get("error_message"):
            entry["error_message"] = item["error_message"]
        items.append(entry)

    return response(200, {"items": items, "count": len(items)})

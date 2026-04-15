# ================================================================================
# delete.py — DELETE /history/{job_id}
# ================================================================================
# Purpose:
#   Remove a single job row and its associated S3 objects (original + cartoon).
#   Only the owner of the row can delete it — authorization is enforced by the
#   (owner, job_id) composite key.
# ================================================================================

import logging
import os

import boto3

from common import get_owner, response

JOBS_TABLE_NAME = os.environ["JOBS_TABLE_NAME"]
MEDIA_BUCKET    = os.environ["MEDIA_BUCKET_NAME"]

dynamodb = boto3.resource("dynamodb")
table    = dynamodb.Table(JOBS_TABLE_NAME)
s3       = boto3.client("s3")

logger = logging.getLogger()
logger.setLevel(logging.INFO)


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

    keys_to_delete = [k for k in (item.get("original_key"), item.get("cartoon_key")) if k]
    if keys_to_delete:
        s3.delete_objects(
            Bucket = MEDIA_BUCKET,
            Delete = {"Objects": [{"Key": k} for k in keys_to_delete]},
        )

    table.delete_item(Key={"owner": owner, "job_id": job_id})

    logger.info("Deleted job_id=%s owner=%s", job_id, owner)
    return response(200, {"job_id": job_id, "deleted": True})

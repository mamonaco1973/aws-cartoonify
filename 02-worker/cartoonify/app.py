# ================================================================================
# app.py — Bedrock Nova Canvas cartoonify worker
# ================================================================================
# Purpose:
#   Lambda consumer for the cartoonify SQS queue. For each message:
#     1. Download the uploaded original image from S3
#     2. Normalize (EXIF strip, center-square-crop, downscale to 1024x1024, PNG)
#     3. Invoke Amazon Nova Canvas (IMAGE_VARIATION) with a style-specific prompt
#     4. Upload the generated cartoon to S3 under cartoons/<owner>/<job_id>.png
#     5. Update the DynamoDB job row to status=complete (or status=error)
#
# SQS message shape (produced by the submit Lambda):
#   {
#     "job_id":       "<ms>-<hex>",
#     "owner":        "<cognito sub>",
#     "style":        "<style id from STYLE_PROMPTS>",
#     "original_key": "originals/<owner>/<job_id>.<ext>"
#   }
#
# Environment:
#   JOBS_TABLE_NAME
#   MEDIA_BUCKET_NAME
#   BEDROCK_MODEL_ID  (default: amazon.nova-canvas-v1:0)
# ================================================================================

import base64
import io
import json
import logging
import os
import time
from typing import Tuple

import boto3
from PIL import Image, ImageOps

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
AWS_REGION       = os.environ.get("AWS_REGION", "us-east-1")
JOBS_TABLE_NAME  = os.environ["JOBS_TABLE_NAME"]
MEDIA_BUCKET     = os.environ["MEDIA_BUCKET_NAME"]
BEDROCK_MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-canvas-v1:0")

TARGET_SIZE        = 1024          # Nova Canvas square dimension
SIMILARITY         = 0.7           # 0.2-1.0; higher = closer to source
CFG_SCALE          = 8.0
NEGATIVE_PROMPT    = (
    "blurry, low quality, distorted, extra limbs, deformed, watermark, text"
)

# ------------------------------------------------------------------------------
# Style prompts. Keys are sent by the client; full prompt text stays server-side
# so the UI can evolve independently from the prompt engineering.
# ------------------------------------------------------------------------------
STYLE_PROMPTS = {
    "studio_ghibli": "in the style of Studio Ghibli, soft watercolor anime, hand-drawn, whimsical",
    "pixar_3d":      "Pixar-style 3D animated character, cinematic lighting, expressive features",
    "simpsons":      "The Simpsons cartoon style, yellow skin, bold black outlines, flat colors",
    "comic_book":    "vintage comic book style, halftone dots, bold ink lines, saturated colors",
    "anime":         "anime illustration, cel-shaded, vibrant colors, sharp lineart",
    "watercolor":    "soft watercolor painting, pastel tones, flowing brush strokes",
    "pencil_sketch": "detailed pencil sketch, graphite shading, paper texture, monochrome",
}

# ------------------------------------------------------------------------------
# AWS clients (module-scoped for connection reuse)
# ------------------------------------------------------------------------------
s3       = boto3.client("s3", region_name=AWS_REGION)
bedrock  = boto3.client("bedrock-runtime", region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(JOBS_TABLE_NAME)

logger = logging.getLogger()
logger.setLevel(logging.INFO)


# ------------------------------------------------------------------------------
# Image preparation
# ------------------------------------------------------------------------------
def prepare_image(src_bytes: bytes) -> str:
    """Normalize an uploaded image to a base64-encoded 1024x1024 PNG."""
    img = Image.open(io.BytesIO(src_bytes))
    img = ImageOps.exif_transpose(img)         # apply EXIF rotation
    img = img.convert("RGB")                   # strip alpha / palettes

    # Center-square-crop, then downscale to TARGET_SIZE.
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top  = (h - side) // 2
    img  = img.crop((left, top, left + side, top + side))
    img  = img.resize((TARGET_SIZE, TARGET_SIZE), Image.LANCZOS)

    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode("ascii")


# ------------------------------------------------------------------------------
# Bedrock Nova Canvas invocation
# ------------------------------------------------------------------------------
def invoke_nova_canvas(source_b64: str, style_id: str) -> bytes:
    """Call Nova Canvas IMAGE_VARIATION and return the generated PNG bytes."""
    prompt = STYLE_PROMPTS.get(style_id)
    if not prompt:
        raise ValueError(f"Unknown style id: {style_id}")

    payload = {
        "taskType": "IMAGE_VARIATION",
        "imageVariationParams": {
            "text":               prompt,
            "negativeText":       NEGATIVE_PROMPT,
            "images":             [source_b64],
            "similarityStrength": SIMILARITY,
        },
        "imageGenerationConfig": {
            "numberOfImages": 1,
            "height":         TARGET_SIZE,
            "width":          TARGET_SIZE,
            "cfgScale":       CFG_SCALE,
        },
    }

    logger.info("Invoking Bedrock model=%s style=%s", BEDROCK_MODEL_ID, style_id)
    res = bedrock.invoke_model(
        modelId     = BEDROCK_MODEL_ID,
        contentType = "application/json",
        accept      = "application/json",
        body        = json.dumps(payload),
    )

    body = json.loads(res["body"].read())

    if body.get("error"):
        raise RuntimeError(f"Bedrock returned error: {body['error']}")

    images = body.get("images") or []
    if not images:
        raise RuntimeError("Bedrock returned no images")

    return base64.b64decode(images[0])


# ------------------------------------------------------------------------------
# DynamoDB status updates
# ------------------------------------------------------------------------------
def mark_processing(owner: str, job_id: str) -> None:
    table.update_item(
        Key={"owner": owner, "job_id": job_id},
        UpdateExpression="SET #s = :s",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":s": "processing"},
    )


def mark_complete(owner: str, job_id: str, cartoon_key: str) -> None:
    table.update_item(
        Key={"owner": owner, "job_id": job_id},
        UpdateExpression="SET #s = :s, cartoon_key = :c, completed_at = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": "complete",
            ":c": cartoon_key,
            ":t": int(time.time()),
        },
    )


def mark_error(owner: str, job_id: str, message: str) -> None:
    table.update_item(
        Key={"owner": owner, "job_id": job_id},
        UpdateExpression="SET #s = :s, error_message = :m, completed_at = :t",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":s": "error",
            ":m": message[:500],
            ":t": int(time.time()),
        },
    )


# ------------------------------------------------------------------------------
# Per-message processing
# ------------------------------------------------------------------------------
def process_message(body: dict) -> None:
    job_id       = body["job_id"]
    owner        = body["owner"]
    style        = body["style"]
    original_key = body["original_key"]

    logger.info("Processing job=%s owner=%s style=%s key=%s",
                job_id, owner, style, original_key)

    mark_processing(owner, job_id)

    # 1. Download original
    obj = s3.get_object(Bucket=MEDIA_BUCKET, Key=original_key)
    src_bytes = obj["Body"].read()

    # 2. Normalize
    prepared_b64 = prepare_image(src_bytes)

    # 3. Bedrock call
    cartoon_bytes = invoke_nova_canvas(prepared_b64, style)

    # 4. Upload result
    cartoon_key = f"cartoons/{owner}/{job_id}.png"
    s3.put_object(
        Bucket      = MEDIA_BUCKET,
        Key         = cartoon_key,
        Body        = cartoon_bytes,
        ContentType = "image/png",
    )

    # 5. Update job
    mark_complete(owner, job_id, cartoon_key)
    logger.info("Completed job=%s → %s", job_id, cartoon_key)


# ------------------------------------------------------------------------------
# Lambda entry point
# ------------------------------------------------------------------------------
def lambda_handler(event, context):
    """Triggered by SQS. Each Record.body is a JSON string from the submit Lambda."""
    for record in event.get("Records", []):
        body = {}
        try:
            body = json.loads(record["body"])
            process_message(body)
        except Exception as e:
            logger.exception("Failed to process message: %s", e)
            owner  = body.get("owner")
            job_id = body.get("job_id")
            if owner and job_id:
                try:
                    mark_error(owner, job_id, str(e))
                except Exception:
                    logger.exception("Failed to mark job as error")
            # Swallow the exception so SQS does not redrive. The job row's
            # status=error is the canonical failure signal for the client.

    return {"statusCode": 200, "body": "Batch processed"}

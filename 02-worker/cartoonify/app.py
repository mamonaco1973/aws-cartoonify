# ================================================================================
# app.py — Bedrock cartoonify worker (Stability Image Control Structure)
# ================================================================================
# Purpose:
#   Lambda consumer for the cartoonify SQS queue. For each message:
#     1. Download the uploaded original image from S3
#     2. Normalize (EXIF strip, center-square-crop, downscale to 1024x1024, PNG)
#     3. Invoke Stability `stable-image-control-structure-v1:0` — preserves the
#        photo's composition/pose while regenerating it in the requested style
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
#   BEDROCK_MODEL_ID  — required; set by 03-api Terraform from the values in
#                       apply.sh (single source of truth for model selection).
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
BEDROCK_MODEL_ID = os.environ["BEDROCK_MODEL_ID"]

TARGET_SIZE      = 1024   # square output
CONTROL_STRENGTH = 0.7    # 0.0-1.0; higher = stick closer to input composition

# ------------------------------------------------------------------------------
# Style prompts. Keys are sent by the client; full prompt text stays server-side
# so the UI can evolve independently from the prompt engineering.
# ------------------------------------------------------------------------------
STYLE_PROMPTS = {
    "pixar_3d":      (
        "Pixar 3D animated portrait, subsurface skin shading, warm rim lighting, "
        "large expressive eyes, smooth stylized features, vibrant color grading, "
        "cinematic depth of field, high-quality render"
    ),
    "simpsons":      (
        "The Simpsons animated style, bright yellow skin, bold black outlines, "
        "flat cel-shaded colors, D-shaped ears, overbite, Springfield cartoon aesthetic"
    ),
    "comic_book":    (
        "Marvel comic book illustration, Ben-Day dot shading, bold ink outlines, "
        "dramatic shadows, saturated primary colors, dynamic superhero rendering"
    ),
    "anime":         (
        "Japanese anime portrait, detailed cel-shading, vibrant hair, large luminous eyes, "
        "clean sharp lineart, soft highlight gloss, manga-style rendering"
    ),
    "watercolor":    (
        "fine art watercolor portrait, loose wet-on-wet washes, soft color blooms, "
        "visible paper texture, delicate brushwork, impressionist light"
    ),
    "pencil_sketch": (
        "detailed graphite portrait sketch, cross-hatching, tonal shading, "
        "textured paper grain, charcoal smudge, monochrome rendering, artist sketchbook"
    ),
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
# Bedrock invocation — Stability stable-image-control-structure-v1:0
# ------------------------------------------------------------------------------
# Request shape:
#   { "image": "<b64>", "prompt": "...",
#     "control_strength": 0.0-1.0, "output_format": "png" }
# Response shape:
#   { "seeds": [...], "finish_reasons": ["SUCCESS"|"CONTENT_FILTERED"|...],
#     "images": ["<b64 png>"] }
# ------------------------------------------------------------------------------
def invoke_bedrock(source_b64: str, style_id: str, prompt_extra: str = "") -> bytes:
    """Call Stability Control-Structure and return generated PNG bytes."""
    prompt = STYLE_PROMPTS.get(style_id)
    if not prompt:
        raise ValueError(f"Unknown style id: {style_id}")

    if prompt_extra:
        prompt = f"{prompt}, {prompt_extra}"

    payload = {
        "image":            source_b64,
        "prompt":           prompt,
        "control_strength": CONTROL_STRENGTH,
        "output_format":    "png",
    }

    logger.info("Invoking Bedrock model=%s style=%s", BEDROCK_MODEL_ID, style_id)
    res = bedrock.invoke_model(
        modelId     = BEDROCK_MODEL_ID,
        contentType = "application/json",
        accept      = "application/json",
        body        = json.dumps(payload),
    )

    body = json.loads(res["body"].read())

    # Stability control-structure returns finish_reasons: [null] on success;
    # a non-null value (e.g. "CONTENT_FILTERED", "ERROR") signals failure.
    finish_reasons = body.get("finish_reasons") or []
    if finish_reasons and finish_reasons[0] is not None:
        raise RuntimeError(f"Bedrock finish_reason: {finish_reasons[0]}")

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
    prompt_extra = body.get("prompt_extra") or ""

    logger.info("Processing job=%s owner=%s style=%s key=%s extra=%r",
                job_id, owner, style, original_key, prompt_extra)

    mark_processing(owner, job_id)

    # 1. Download original
    obj = s3.get_object(Bucket=MEDIA_BUCKET, Key=original_key)
    src_bytes = obj["Body"].read()

    # 2. Normalize
    prepared_b64 = prepare_image(src_bytes)

    # 3. Bedrock call
    cartoon_bytes = invoke_bedrock(prepared_b64, style, prompt_extra)

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

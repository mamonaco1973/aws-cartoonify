# ================================================================================
# common.py — shared helpers for the cartoonify API Lambdas
# ================================================================================

import json
import os
import time
import uuid
from decimal import Decimal

# ------------------------------------------------------------------------------
# Style whitelist (must match STYLE_PROMPTS in the worker; client sees these
# IDs, full prompt text lives in the worker)
# ------------------------------------------------------------------------------
ALLOWED_STYLES = {
    "pixar_3d",
    "simpsons",
    "anime",
    "comic_book",
    "watercolor",
    "pencil_sketch",
}

# ------------------------------------------------------------------------------
# Upload constraints (must match presigned POST conditions)
# ------------------------------------------------------------------------------
ALLOWED_CONTENT_TYPES = {
    "image/jpeg": "jpg",
    "image/png":  "png",
    "image/webp": "webp",
}
MAX_UPLOAD_BYTES  = 5 * 1024 * 1024  # 5 MB
DAILY_QUOTA       = 10
JOB_TTL_SECONDS   = 7 * 24 * 3600
PRESIGNED_GET_TTL = 4 * 3600         # 4 hours
MAX_PROMPT_EXTRA  = 500              # chars — user-supplied prompt augmentation


# ------------------------------------------------------------------------------
# API Gateway helpers
# ------------------------------------------------------------------------------
def _decimal_default(obj):
    if isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    raise TypeError(f"Not serializable: {type(obj)}")


def response(status: int, body):
    return {
        "statusCode": status,
        "headers":    {"Content-Type": "application/json"},
        "body":       json.dumps(body, default=_decimal_default),
    }


def get_owner(event) -> str:
    """Extract the Cognito `sub` claim from an API Gateway v2 JWT-authorized event."""
    try:
        return event["requestContext"]["authorizer"]["jwt"]["claims"]["sub"]
    except (KeyError, TypeError):
        raise PermissionError("Missing JWT claims on request")


def parse_body(event) -> dict:
    raw = event.get("body")
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


# ------------------------------------------------------------------------------
# Job ID helpers
# ------------------------------------------------------------------------------
def make_job_id() -> str:
    """Return a lexicographically time-sortable job id: <ms:013d>-<hex8>."""
    ms = int(time.time() * 1000)
    return f"{ms:013d}-{uuid.uuid4().hex[:8]}"


def job_id_ms(job_id: str) -> int:
    """Extract the millisecond timestamp prefix from a job_id."""
    return int(job_id.split("-", 1)[0])


def start_of_utc_day_ms(now_ms: int = None) -> int:
    """Epoch ms of 00:00 UTC today."""
    if now_ms is None:
        now_ms = int(time.time() * 1000)
    day_seconds = 86400
    return (now_ms // 1000 // day_seconds) * day_seconds * 1000

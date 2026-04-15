"""
notes.py — Lambda handlers for the Cognito-authenticated Notes CRUD API.

This module consolidates all five CRUD operations into a single Python file.
Each operation is exposed as a separate top-level handler function so that
Terraform can wire each one to its own Lambda function (and its own scoped
IAM role), while keeping the shared code — configuration, helpers, and the
DynamoDB client — in one place.

Handler → Lambda function → API Gateway route mapping:
    create_handler  →  create-note-cognito  →  POST   /notes
    list_handler    →  list-notes-cognito   →  GET    /notes
    get_handler     →  get-note-cognito     →  GET    /notes/{id}
    update_handler  →  update-note-cognito  →  PUT    /notes/{id}
    delete_handler  →  delete-note-cognito  →  DELETE /notes/{id}

Event format:
    All handlers receive an API Gateway v2 (HTTP API) payload format 2.0 event.
    Relevant fields used here:
        event["body"]                                         — JSON request body (string)
        event["pathParameters"]["id"]                         — path parameter extracted by API GW
        event["requestContext"]["authorizer"]["jwt"]["claims"] — JWT claims injected by the
                                                                 Cognito JWT authorizer

Storage:
    Amazon DynamoDB with a composite key:
        PK: owner  (string, Cognito sub claim — one partition per user)
        SK: id     (string, UUID4)

Authentication:
    API Gateway validates the JWT signature against Cognito JWKS before invoking
    any Lambda. The Lambda then extracts the "sub" claim as the owner, ensuring
    each user can only read and write their own notes.

Environment variables:
    NOTES_TABLE_NAME   The DynamoDB table name injected by Terraform at
                       deploy time via the Lambda environment block.
                       All five handlers read this variable.
"""

import json
import os
import uuid
from datetime import datetime, timezone

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Module-level singletons
# ---------------------------------------------------------------------------

# DynamoDB table name sourced from the Lambda environment.
TABLE_NAME = os.environ.get("NOTES_TABLE_NAME", "").strip()

# DynamoDB resource client.  Initialised once per Lambda container so the
# connection is reused across warm invocations rather than re-established on
# every request.
dynamodb = boto3.resource("dynamodb")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _response(status_code: int, body: dict) -> dict:
    """Build an API Gateway-compatible HTTP response dict.

    API Gateway v2 (HTTP API) expects Lambda to return a dict with at minimum
    `statusCode` and `body`.  The body must be a string, so the payload is
    JSON-serialised here.

    Args:
        status_code (int): The HTTP status code to return to the caller.
        body (dict):       The response payload — must be JSON-serialisable.

    Returns:
        dict: A response object with `statusCode`, `headers`, and `body`.
    """
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body)
    }


def _table():
    """Return the DynamoDB Table resource, validating the environment first.

    Raises:
        ValueError: If NOTES_TABLE_NAME is not set in the environment.

    Returns:
        boto3.resources.factory.dynamodb.Table: The DynamoDB table resource.
    """
    if not TABLE_NAME:
        raise ValueError("NOTES_TABLE_NAME environment variable is required")
    return dynamodb.Table(TABLE_NAME)


def _get_owner(event: dict) -> str:
    """Extract the authenticated user identifier from the JWT authorizer context.

    API Gateway HTTP API v2 with a JWT authorizer injects the verified claims
    into event["requestContext"]["authorizer"]["jwt"]["claims"] before Lambda
    is invoked.  The "sub" claim is the stable, unique Cognito user identifier
    and is used as the DynamoDB partition key so each user's notes are isolated.

    Args:
        event (dict): The Lambda event object from API Gateway.

    Returns:
        str: The Cognito sub claim for the authenticated caller.

    Raises:
        ValueError: If the sub claim is absent or the authorizer context is
                    missing (indicates an unauthenticated request).
    """
    try:
        claims = event["requestContext"]["authorizer"]["jwt"]["claims"]
        owner = str(claims.get("sub", "")).strip()
        if not owner:
            raise KeyError("sub claim missing")
        return owner
    except Exception:
        raise ValueError("Unauthorized: missing or invalid JWT claims")


def _note_id(event: dict) -> str:
    """Extract the note ID from the API Gateway path parameters.

    Args:
        event (dict): The Lambda event object from API Gateway.

    Returns:
        str: The trimmed note ID, or an empty string if not present.
    """
    try:
        return event.get("pathParameters", {}).get("id", "").strip()
    except AttributeError:
        return ""


# ---------------------------------------------------------------------------
# CRUD handlers
# ---------------------------------------------------------------------------

def create_handler(event, context):
    """Create a new note and persist it to DynamoDB.

    Reads `title` and `note` from the JSON request body, generates a UUID4
    as the composite sort key, records timestamps, and writes the item using
    put_item.  The owner is derived from the verified Cognito JWT so the note
    is scoped to the authenticated caller.

    Request body (JSON):
        {
            "title": "string (required)",
            "note":  "string (required)"
        }

    Args:
        event   (dict): API Gateway v2 HTTP event.
        context (obj):  Lambda context object (unused).

    Returns:
        dict: 201 with {"id", "title", "note"} on success.
              400 if title or note are missing/empty or body is invalid JSON.
              401 if the JWT authorizer context is absent or invalid.
              500 if the DynamoDB write fails or the environment is misconfigured.
    """
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        owner = _get_owner(event)
    except ValueError as exc:
        return _response(401, {"error": str(exc)})

    try:
        payload = json.loads(event.get("body", "{}"))
        title   = str(payload.get("title", "")).strip()
        note    = str(payload.get("note", "")).strip()
        if not title:
            raise ValueError("title is required")
        if not note:
            raise ValueError("note is required")
    except (ValueError, json.JSONDecodeError) as exc:
        return _response(400, {"error": f"Invalid request body: {str(exc)}"})

    note_id = str(uuid.uuid4())
    now     = datetime.now(timezone.utc).isoformat()

    item = {
        "owner":      owner,
        "id":         note_id,
        "title":      title,
        "note":       note,
        "created_at": now,
        "updated_at": now
    }

    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(#id)",
            ExpressionAttributeNames={"#id": "id"}
        )
    except ClientError:
        return _response(500, {"error": "Failed to create note"})

    return _response(201, {"id": note_id, "title": title, "note": note})


def list_handler(event, context):
    """List all notes belonging to the authenticated caller.

    Queries DynamoDB using the partition key (owner = Cognito sub) to return
    only the notes owned by the caller.  A Query is used rather than a Scan
    because the owner is known — this avoids a full table scan and keeps each
    user's data isolated.

    Args:
        event   (dict): API Gateway v2 HTTP event.
        context (obj):  Lambda context object (unused).

    Returns:
        dict: 200 with {"items": [<note>, ...]} on success.
              401 if the JWT authorizer context is absent or invalid.
              500 if the query fails or the environment is misconfigured.
    """
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        owner = _get_owner(event)
    except ValueError as exc:
        return _response(401, {"error": str(exc)})

    try:
        resp = table.query(KeyConditionExpression=Key("owner").eq(owner))
    except ClientError:
        return _response(500, {"error": "Failed to list notes"})

    return _response(200, {"items": resp.get("Items", [])})


def get_handler(event, context):
    """Retrieve a single note by its ID, scoped to the authenticated caller.

    Performs a direct get_item lookup using the composite key (owner, id).
    Because owner is the partition key, a note belonging to a different user
    will simply not be found — no explicit ownership check needed.

    Args:
        event   (dict): API Gateway v2 HTTP event.  The note ID is read from
                        event["pathParameters"]["id"].
        context (obj):  Lambda context object (unused).

    Returns:
        dict: 200 with the full note item dict on success.
              400 if no note ID is present in the path.
              401 if the JWT authorizer context is absent or invalid.
              404 if no item with the given ID exists for this owner.
              500 if the read fails or the environment is misconfigured.
    """
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        owner = _get_owner(event)
    except ValueError as exc:
        return _response(401, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        resp = table.get_item(Key={"owner": owner, "id": note_id})
    except ClientError:
        return _response(500, {"error": "Failed to retrieve note"})

    item = resp.get("Item")
    if not item:
        return _response(404, {"error": "Note not found"})

    return _response(200, item)


def update_handler(event, context):
    """Update the title and body of an existing note.

    Uses update_item with a ConditionExpression to verify the item exists
    before applying the field updates.  Because owner is the partition key,
    updates are automatically scoped to the authenticated caller's notes.

    Args:
        event   (dict): API Gateway v2 HTTP event.  Note ID from path params;
                        updated fields from the JSON body.
        context (obj):  Lambda context object (unused).

    Returns:
        dict: 200 with {"id", "title", "note"} on success.
              400 if title/note are missing or the request body is invalid.
              401 if the JWT authorizer context is absent or invalid.
              404 if the ConditionExpression fails (item does not exist).
              500 if the update fails or the environment is misconfigured.
    """
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        owner = _get_owner(event)
    except ValueError as exc:
        return _response(401, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        payload = json.loads(event.get("body", "{}"))
        title   = str(payload.get("title", "")).strip()
        note    = str(payload.get("note", "")).strip()
        if not title:
            raise ValueError("title is required")
        if not note:
            raise ValueError("note is required")
    except (ValueError, json.JSONDecodeError) as exc:
        return _response(400, {"error": f"Invalid request body: {str(exc)}"})

    now = datetime.now(timezone.utc).isoformat()

    try:
        table.update_item(
            Key={"owner": owner, "id": note_id},
            UpdateExpression="SET #title = :title, #note = :note, updated_at = :updated",
            ConditionExpression="attribute_exists(id)",
            ExpressionAttributeNames={
                "#title": "title",
                "#note":  "note"
            },
            ExpressionAttributeValues={
                ":title":   title,
                ":note":    note,
                ":updated": now
            }
        )
    except ClientError as exc:
        # ConditionalCheckFailedException means the item does not exist
        code = exc.response.get("Error", {}).get("Code", "")
        if code == "ConditionalCheckFailedException":
            return _response(404, {"error": "Note not found"})
        return _response(500, {"error": "Failed to update note"})

    return _response(200, {"id": note_id, "title": title, "note": note})


def delete_handler(event, context):
    """Delete a note by its ID, scoped to the authenticated caller.

    Because owner is the partition key, delete_item will silently no-op if
    the ID belongs to a different user — cross-user deletion is impossible
    without knowing the victim's owner key.

    Args:
        event   (dict): API Gateway v2 HTTP event.  Note ID from path params.
        context (obj):  Lambda context object (unused).

    Returns:
        dict: 200 with {"deleted": True, "id": <id>} on success.
              400 if no note ID is present in the path.
              401 if the JWT authorizer context is absent or invalid.
              500 if the delete fails or the environment is misconfigured.
    """
    try:
        table = _table()
    except ValueError as exc:
        return _response(500, {"error": str(exc)})

    try:
        owner = _get_owner(event)
    except ValueError as exc:
        return _response(401, {"error": str(exc)})

    note_id = _note_id(event)
    if not note_id:
        return _response(400, {"error": "Note id is required"})

    try:
        table.delete_item(Key={"owner": owner, "id": note_id})
    except ClientError:
        return _response(500, {"error": "Failed to delete note"})

    return _response(200, {"deleted": True, "id": note_id})

# ================================================================================
# File: dynamodb.tf
# ================================================================================
# Purpose:
#   Creates a DynamoDB table used by the Notes API to store user-owned
#   notes. Each note is uniquely identified by an (owner, id) composite
#   key, where id is a UUID stored as a string.
#
# Notes:
#   - PAY_PER_REQUEST billing mode eliminates capacity management.
#   - DynamoDB is schemaless beyond key attributes, so "title" and "note"
#     are stored per item without being declared in the table schema.
# ================================================================================
#
# Item Shape (example):
#   {
#     "owner": "<user identity / username / subject>",
#     "id"   : "<uuid>",
#     "title": "<note title>",
#     "note" : "<note body>"
#   }
#
# --------------------------------------------------------------------------------
# RESOURCE: aws_dynamodb_table.notes
# --------------------------------------------------------------------------------
# Description:
#   Defines the DynamoDB table where the Notes API stores notes for each
#   owner. The partition key groups all notes for a user, and the sort
#   key supports efficient queries like "list all notes for owner" and
#   "get a specific note by (owner, id)".
#
# Configuration:
#   - Partition key: owner (string)
#   - Sort key     : id    (string, UUID)
# --------------------------------------------------------------------------------
resource "aws_dynamodb_table" "notes" {
  name         = "notes-cognito"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "owner"
  range_key    = "id"

  attribute {
    name = "owner"
    type = "S"
  }

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "notes"
  }
}

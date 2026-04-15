# aws-cognito-app

Serverless CRUD API for managing notes, secured with Amazon Cognito JWT authentication. No EC2 — fully Lambda + API Gateway + DynamoDB, with a static S3-hosted SPA frontend.

## Architecture

```
Browser → S3 (SPA) → Cognito Hosted UI → callback.html (PKCE) → sessionStorage (JWT)
                                                                        ↓
Browser → API Gateway (JWT authorizer) → Lambda (Python 3.14) → DynamoDB (notes-cognito)
```

**AWS services:** API Gateway (HTTP API v2), Lambda, DynamoDB, Cognito User Pool, S3, IAM, CloudWatch Logs

## Project Structure

```
aws-cognito-app/
├── 01-lambdas/          # Backend IaC + Lambda source
│   └── code/            # Python Lambda handlers
├── 02-webapp/           # Frontend SPA + S3 upload IaC
├── apply.sh             # Full deploy (backend → frontend)
├── destroy.sh           # Full teardown (frontend → backend)
├── validate.sh          # Post-deploy: prints app URL and OAuth config
└── check_env.sh         # Validates aws, terraform, jq + AWS credentials
```

## Deploy / Destroy

```bash
./apply.sh      # Full deploy — runs check_env, terraform for both stages, builds config.json
./destroy.sh    # Full teardown — destroys webapp first, then backend
./validate.sh   # Print app URL after deploy
```

**Prerequisites:** `aws`, `terraform`, `jq` in PATH; AWS credentials configured (`AWS_PROFILE` or env vars).

Region is hardcoded to `us-east-1` in the scripts and Terraform providers.

## Backend: 01-lambdas

Terraform deploys all backend resources. Each Lambda has its own IAM role with least-privilege DynamoDB permissions.

| Route | Lambda file | DynamoDB op |
|---|---|---|
| `POST /notes` | `code/create.py` | PutItem |
| `GET /notes` | `code/list.py` | Query |
| `GET /notes/{id}` | `code/get.py` | GetItem |
| `PUT /notes/{id}` | `code/update.py` | UpdateItem |
| `DELETE /notes/{id}` | `code/delete.py` | DeleteItem |

**DynamoDB table:** `notes-cognito`
- Partition key: `owner` (Cognito `sub` claim)
- Sort key: `id` (UUID)
- Billing: PAY_PER_REQUEST

**Lambda packaging:** All `code/` Python files are zipped together via `archive_file` in `lambda-get.tf`. Handler format: `<filename>.lambda_handler`. Runtime: `python3.14`.

**Environment variable injected into all Lambdas:**
```
NOTES_TABLE_NAME=notes-cognito
```

**API Gateway authorizer:** JWT type, issuer = Cognito User Pool endpoint, audience = app client ID. Validates `Authorization: Bearer <token>` before invoking any Lambda.

**CORS:** Origins `*` (tighten for production), methods GET/POST/PUT/DELETE/OPTIONS.

## Frontend: 02-webapp

Vanilla JS SPA — no build step, no npm.

- `index.html.tmpl` — template with `${API_BASE}` placeholder; `apply.sh` generates `index.html` via `envsubst`
- `callback.html` — handles Cognito redirect, exchanges auth code for tokens (PKCE), stores tokens in `sessionStorage`
- `config.json` — generated at deploy time by `apply.sh`; never commit this file

**Generated `config.json` shape:**
```json
{
  "cognitoDomain": "notes-auth-<random>.auth.us-east-1.amazoncognito.com",
  "clientId": "<cognito-app-client-id>",
  "redirectUri": "https://cnotes-web-<random>.s3.us-east-1.amazonaws.com/callback.html",
  "apiBaseUrl": "https://<api-id>.execute-api.us-east-1.amazonaws.com"
}
```

The `02-webapp` Terraform module does NOT create the S3 bucket — it uploads to the bucket created by `01-lambdas`. The bucket name is discovered dynamically by prefix `cnotes` in `apply.sh`.

## Cognito

- User Pool: `notes-user-pool`, email-based sign-in
- Hosted UI domain: `notes-auth-<random>`
- App client: SPA (no client secret), Authorization Code + PKCE flow, scopes: openid/email/profile
- Callback URL: `https://<bucket>.s3.<region>.amazonaws.com/callback.html`

## Terraform State

Local state only — `.terraform/` directories inside `01-lambdas/` and `02-webapp/`. No remote backend. Do not delete these directories between apply and destroy.

## Modifying Lambda Code

1. Edit files under `01-lambdas/code/`
2. Re-run `./apply.sh` — Terraform detects the zip hash change and redeploys affected functions

No local testing setup. Test against deployed infrastructure using `curl` with a JWT from `sessionStorage`.

## Manual API Test

```bash
JWT="<paste from browser sessionStorage.access_token>"
BASE="<from validate.sh output>"

curl -H "Authorization: Bearer $JWT" $BASE/notes
curl -X POST -H "Authorization: Bearer $JWT" -H "Content-Type: application/json" \
  -d '{"title":"Test","note":"Body"}' $BASE/notes
```

## Authorization Model

- API Gateway validates JWT signature against Cognito JWKS before Lambda runs
- Lambda extracts `sub` claim as `owner`; all DynamoDB keys include `owner` as partition key
- Users can only read/write their own notes — enforced at the storage layer

# aws-cartoonify

Serverless **image-to-cartoon** web application on AWS. Users sign in with
Cognito, upload a photo, pick a cartoon style, and a queue-driven worker
invokes a **Bedrock image model** (default: Stability `stable-image-control-structure-v1:0`,
via the `us.*` cross-region inference profile) to generate a stylized cartoon.
The model is fully parameterized — see [Changing the Bedrock model](#changing-the-bedrock-model).
Results are stored privately in S3 for 7 days and served to the owner through
short-lived presigned URLs.

Built on a **serverless, event-driven** architecture using **API Gateway
(HTTP API v2)**, **Cognito** (PKCE auth), **SQS**, **DynamoDB**, **Lambda**
(zip + container image), **ECR**, **S3**, and **Bedrock** — provisioned with
**Terraform** in four stages.

## Features

- **Cognito-authenticated** SPA with self-service signup (email-based)
- **Style presets:** Studio Ghibli · Pixar 3D · Simpsons · Anime · Comic Book · Watercolor · Pencil Sketch
- **Asynchronous pipeline:** browser uploads original → SQS queue → Bedrock worker → S3
- **Per-user history gallery** (last 50 cartoons, newest first)
- **Safety rails:**
  - 5 MB file size cap (client-side + S3 presigned POST policy)
  - 2048×2048 max dimensions (client-side check)
  - 100 generations per user per UTC day (enforced in DynamoDB query)
  - 7-day S3 lifecycle + DynamoDB TTL retention
  - Bedrock IAM scoped to the configured model + its inference profile only

## Architecture

```
Browser → S3 (SPA) → Cognito Hosted UI → callback.html (PKCE) → sessionStorage (JWT)

Browser ──POST /upload-url──→ API Gateway (JWT) → upload_url Lambda → presigned POST
Browser ──PUT (direct)─────→ S3 media bucket (private)

Browser ──POST /generate───→ API Gateway (JWT) → submit Lambda → DynamoDB (submitted) + SQS
                                                                        ↓
                                                     Worker Lambda (container image)
                                                     • Pillow normalize → 1024×1024 PNG
                                                     • Bedrock invoke_model (control-structure)
                                                     • S3 put cartoons/<owner>/<job_id>.png
                                                     • DynamoDB (status=complete)

Browser ──GET /result/{job_id}─→ result Lambda (presigned GET URLs)
Browser ──GET /history────────→ history Lambda (newest 50 for owner)
Browser ──DELETE /history/{id}→ delete Lambda (S3 + row)
```

## Deployment stages

| Stage | What it does |
|---|---|
| **01-backend** | SQS, DynamoDB, ECR, S3 (web + media), Cognito User Pool |
| **02-worker**  | `docker buildx` the Bedrock worker image, push to ECR |
| **03-api**     | API Gateway HTTP API + 5 JWT-authorized Lambdas + worker Lambda + SQS trigger |
| **04-webapp**  | Generate `index.html` / `config.json`, upload SPA assets to the web bucket |

## Prerequisites

- [AWS account](https://aws.amazon.com/console/) with Bedrock enabled
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [Docker](https://docs.docker.com/engine/install/) (with `buildx`)
- `jq`, `envsubst` in PATH
- **Bedrock access enabled** for the configured model (default: Stability
  `stable-image-control-structure-v1:0` via the `us.*` inference profile)
  in your Bedrock console:
  https://console.aws.amazon.com/bedrock/home?region=us-east-1#/modelaccess

Region is hardcoded to `us-east-1` (the `us.*` inference profile routes from there).

## Deploy

```bash
git clone <repo> aws-cartoonify
cd aws-cartoonify
./apply.sh
```

`check_env.sh` runs first and will fail fast if Bedrock model access is not
enabled. On success, `validate.sh` prints the app URL:

```
================================================================================
  Cartoonify — Deployment validated!
================================================================================
  API : https://<api-id>.execute-api.us-east-1.amazonaws.com
  Web : https://cartoonify-web-<hex>.s3.us-east-1.amazonaws.com/index.html
================================================================================
```

Open the web URL, sign up, sign in, upload an image, pick a style, and click
**Cartoonify**. The result appears in ~15–30 s.

## Destroy

```bash
./destroy.sh
```

Destroys `04-webapp → 03-api → media bucket contents → 01-backend`. The media
bucket is emptied explicitly before backend teardown so that lifecycle-pending
objects do not block `aws_s3_bucket` deletion.

## API endpoints

All require `Authorization: Bearer <Cognito JWT>`.

| Method | Path | Purpose |
|---|---|---|
| POST | `/upload-url` | Returns a presigned S3 POST with size + content-type policy |
| POST | `/generate` | Validates, enforces quota, writes job row, enqueues on SQS |
| GET | `/result/{job_id}` | Single-job status + presigned GETs for original/cartoon |
| GET | `/history` | Last 50 jobs for the authenticated user |
| DELETE | `/history/{job_id}` | Removes S3 objects + DynamoDB row |

Daily quota responses are `429` with `{"error":"Daily limit of 100 reached", ...}`.

## Changing the Bedrock model

The model is parameterized end-to-end. To retarget, edit the three `export`
lines near the top of [apply.sh](apply.sh):

```bash
export BEDROCK_MODEL_ID="stability.stable-image-control-structure-v1:0"
export BEDROCK_INFERENCE_PROFILE_ID="us.stability.stable-image-control-structure-v1:0"
export BEDROCK_MODEL_REGIONS='["us-east-1","us-east-2","us-west-2"]'
```

These values flow automatically to:

- **`check_env.sh`** — pre-flight probe that the profile + model are accessible
- **`03-api/` Terraform** — worker IAM `Resource` ARNs (inference profile + foundation
  model in every region the profile may route to) and the worker Lambda's
  `BEDROCK_MODEL_ID` environment variable
- **`02-worker/cartoonify/app.py`** — reads `BEDROCK_MODEL_ID` at startup and
  passes it to `bedrock.invoke_model`

If the new model uses a different request/response schema (e.g. Nova Canvas's
`IMAGE_VARIATION` task vs. Stability's control-structure shape), also update
the `invoke_bedrock` payload in
[02-worker/cartoonify/app.py](02-worker/cartoonify/app.py) and bump
`WORKER_TAG` in [apply.sh](apply.sh) so the new image is built and pushed.

## Cost notes

- Image generation is roughly **$0.04 per 1024×1024 image** (check current pricing
  for your chosen model).
- 100-per-user/day cap → worst case ≈ **$4/user/day** on Bedrock alone.
- SQS, Lambda, DynamoDB, S3 costs for this workload are negligible.

## Project layout

```
aws-cartoonify/
├── 01-backend/        # Terraform: Cognito, DynamoDB, SQS, S3, ECR
├── 02-worker/
│   └── cartoonify/    # Dockerfile + app.py + requirements.txt
├── 03-api/
│   ├── code/          # Python Lambda handlers + common.py
│   ├── api.tf         # HTTP API + JWT authorizer + 5 routes
│   ├── data.tf
│   ├── lambda-api.tf  # 5 zip-packaged API Lambdas (shared role)
│   └── lambda-worker.tf  # Container-image worker Lambda + SQS ESM
├── 04-webapp/         # Vanilla SPA + upload Terraform
├── apply.sh  destroy.sh  validate.sh  check_env.sh
└── CLAUDE.md
```

See [CLAUDE.md](CLAUDE.md) for a deeper walkthrough of the data model,
IAM scoping, and how to modify styles, limits, and the worker image.

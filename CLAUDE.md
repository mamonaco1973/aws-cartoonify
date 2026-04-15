# aws-cartoonify

Serverless image-to-cartoon service on AWS. Users sign in via Cognito, upload
a photo, pick a style, and a queue-driven worker invokes a Bedrock image model
(default: Stability `stable-image-control-structure-v1:0` via the `us.*`
cross-region inference profile) to generate a cartoon. Results live in S3 for
7 days and are accessed through short-lived presigned URLs.

The Bedrock model is fully parameterized — see
[Changing the Bedrock model](#changing-the-bedrock-model).

## Architecture

```
Browser → S3 (SPA, public) → Cognito Hosted UI → callback.html (PKCE) → sessionStorage (JWT)

Browser ──POST /upload-url──→ API Gateway (JWT) ─→ upload_url Lambda ─→ presigned POST
Browser ──PUT (direct)─────→ S3 media bucket (private, originals/<owner>/<job_id>.<ext>)

Browser ──POST /generate───→ API Gateway (JWT) ─→ submit Lambda ─→ DynamoDB (status=submitted)
                                                                 └→ SQS cartoonify-jobs
                                                                        ↓
                                                     Worker Lambda (container image, Bedrock)
                                                     • Pillow: EXIF strip, 1024×1024 crop/resize
                                                     • Bedrock invoke_model (control-structure)
                                                     • S3 put cartoons/<owner>/<job_id>.png
                                                     • DynamoDB (status=complete)

Browser ──GET /result/{job_id}─→ result Lambda  → presigned GET URLs
Browser ──GET /history────────→ history Lambda → newest 50 for owner
Browser ──DELETE /history/{id}→ delete Lambda  → removes S3 objects + row
```

**AWS services:** API Gateway HTTP API v2, Lambda (zip + container), SQS,
DynamoDB, S3 (web + media), Cognito User Pool, ECR, Bedrock (image model —
configurable), CloudWatch Logs.

## Project structure

```
aws-cartoonify/
├── 01-backend/          # Terraform: SQS, DynamoDB, S3, ECR, Cognito
├── 02-worker/
│   └── cartoonify/      # Dockerfile + app.py + requirements.txt (Bedrock worker)
├── 03-api/
│   ├── code/            # Python Lambda handlers (zipped together)
│   │   ├── common.py    # Shared helpers (JWT claims, styles, quota, job_id)
│   │   ├── upload_url.py
│   │   ├── submit.py
│   │   ├── result.py
│   │   ├── history.py
│   │   └── delete.py
│   ├── api.tf
│   ├── data.tf          # Looks up backend resources by name
│   ├── lambda-api.tf    # Zip-packaged API Lambdas (one shared role)
│   └── lambda-worker.tf # Container-image worker Lambda + SQS trigger
├── 04-webapp/           # Vanilla SPA + upload Terraform
├── apply.sh             # Full deploy (4 stages)
├── destroy.sh           # Full teardown (reverse order)
├── validate.sh          # Prints app URL + API endpoint
└── check_env.sh         # Validates aws/terraform/docker/jq/envsubst + Bedrock access
```

## Deploy / destroy

```bash
./apply.sh      # 01-backend → 02-worker (docker push) → 03-api → 04-webapp
./destroy.sh    # 04-webapp → 03-api → empty media bucket → 01-backend
./validate.sh   # Print app URL + API endpoint
```

**Prerequisites:** `aws`, `terraform`, `docker`, `jq`, `envsubst` in PATH;
AWS credentials configured; Bedrock access enabled in the console for the
model + inference profile configured in [apply.sh](apply.sh) (defaults to
Stability `stable-image-control-structure-v1:0` / `us.stability.stable-image-control-structure-v1:0`).

Region is hardcoded to `us-east-1` — the `us.*` cross-region inference profile
routes from there.

## Stage 01: backend (`01-backend/`)

Creates everything that has no dependency on the worker image:

| Resource | Name |
|---|---|
| DynamoDB table | `cartoonify-jobs` (PK=owner, SK=job_id, TTL=ttl) |
| SQS queue | `cartoonify-jobs` (visibility 180s) |
| ECR repo | `cartoonify` |
| S3 web bucket | `cartoonify-web-<hex>` (public read, SPA hosting) |
| S3 media bucket | `cartoonify-media-<hex>` (private, CORS, 7-day lifecycle on originals/ + cartoons/) |
| Cognito User Pool | `cartoonify-user-pool` (email sign-in, self-service signup) |
| Cognito domain | `cartoonify-auth-<hex>.auth.us-east-1.amazoncognito.com` |

**Outputs** (read by `apply.sh`): `web_bucket_name`, `media_bucket_name`,
`cognito_domain`, `app_client_id`, `worker_repo_name`, `jobs_table_name`,
`jobs_queue_url`.

## Stage 02: worker image (`02-worker/cartoonify/`)

No Terraform. `apply.sh` runs `docker buildx build --platform linux/amd64`,
tags with `worker-rc1`, pushes to the ECR repo from stage 01. The build
checks ECR first and skips if the tag already exists.

**Image contents:** `public.ecr.aws/lambda/python:3.11` base + Pillow +
`app.py` handler.

**Worker behavior** ([app.py](02-worker/cartoonify/app.py)):
1. For each SQS Record: parse JSON body `{job_id, owner, style, original_key}`
2. Mark `status=processing` in DynamoDB
3. Download original from `cartoonify-media-*/originals/<owner>/<job_id>.*`
4. Pillow: EXIF-transpose, convert to RGB, center-square-crop, resize to 1024×1024, re-encode PNG
5. Call Bedrock `invoke_model` on `$BEDROCK_MODEL_ID` (default: `us.stability.stable-image-control-structure-v1:0`) with the style prompt, `negative_prompt`, and `control_strength=0.7` — preserves the photo's composition while regenerating it in the requested style
6. Upload cartoon PNG to `cartoons/<owner>/<job_id>.png`
7. Mark `status=complete` + store `cartoon_key`

On exception: mark `status=error` with the first 500 chars of the message, then swallow — the job row's status is the canonical failure signal for the client. The exception is **not** re-raised, so SQS does not redrive.

## Stage 03: API (`03-api/`)

Looks up backend resources by name via `data` sources. Bucket names (which
have random suffixes) come in as variables from `apply.sh`.

### Routes — all JWT-authorized against the Cognito User Pool

| Method | Path | Lambda | Purpose |
|---|---|---|---|
| POST | `/upload-url` | upload_url | Presigned POST with 5 MB limit + exact content-type |
| POST | `/generate` | submit | Validate style, verify upload, enforce daily quota, enqueue |
| GET | `/result/{job_id}` | result | Status + presigned GETs for original/cartoon |
| GET | `/history` | history | Last 50 jobs for owner, newest first |
| DELETE | `/history/{job_id}` | delete | Remove S3 objects + row |

### Per-user daily quota (100/day)

Enforced in `submit.py` via a DynamoDB KeyCondition query using the time-sorted
`job_id` format `{epoch_ms_13digits}-{hex8}`:

```python
Key("owner").eq(sub) & Key("job_id").gte(f"{start_of_utc_day_ms():013d}-")
```

No GSI needed. The 7-day TTL bounds the scanned rows to ≤700 per user.

### Worker Lambda + SQS trigger

Container image from ECR; 2048 MB memory, 120 s timeout. Event source mapping
with `batch_size=1` so one Bedrock call per invocation. Bedrock IAM is scoped
to `var.bedrock_inference_profile_id` plus the underlying foundation model
(`var.bedrock_model_id`) in every region the profile may route to
(`var.bedrock_model_regions`). Values are fed in from [apply.sh](apply.sh).

### Lambda packaging

All five API Lambdas share one zip of `./code/` and one IAM role. Each has its
own `aws_lambda_function` resource with a distinct handler. Runtime: `python3.11`.
Changing any file under `code/` updates all five on the next `apply` because
they share the same `source_code_hash`.

## Stage 04: webapp (`04-webapp/`)

- `index.html.tmpl` — `${API_BASE}` placeholder; `apply.sh` generates `index.html` via `envsubst`
- `callback.html` — Cognito PKCE callback (exchanges code → tokens → sessionStorage)
- `config.json` — generated at deploy time (gitignored)
- `favicon.ico`

The Terraform in this stage does NOT create the web bucket — it uploads to the
one created by `01-backend`. The bucket name is passed via `-var=web_bucket_name=`.

## SPA features

- Cognito Hosted UI sign-in/out via PKCE
- File picker (JPEG/PNG/WebP, 5 MB max, 2048×2048 max) with client-side validation
- Style dropdown: `studio_ghibli`, `pixar_3d`, `simpsons`, `anime`, `comic_book`, `watercolor`, `pencil_sketch`
- Submit flow: `/upload-url` → browser POSTs to S3 → `/generate` → poll `/result/{id}` every 2 s
- Gallery: `/history` on page load, tile per job with download + delete

## Data model

**DynamoDB `cartoonify-jobs`** (PAY_PER_REQUEST, TTL on `ttl`):

| Attribute | Type | Purpose |
|---|---|---|
| `owner` | S (PK) | Cognito `sub` claim |
| `job_id` | S (SK) | `{epoch_ms:013d}-{hex8}` — time-sortable |
| `status` | S | submitted → processing → complete \| error |
| `style` | S | One of the seven style IDs |
| `original_key` | S | `originals/<owner>/<job_id>.<ext>` |
| `cartoon_key` | S | `cartoons/<owner>/<job_id>.png` (when complete) |
| `created_at` | N | Epoch seconds |
| `created_at_ms` | N | Epoch ms (matches `job_id` prefix) |
| `completed_at` | N | Epoch seconds (complete/error) |
| `error_message` | S | First 500 chars of exception on failure |
| `ttl` | N | Epoch seconds, created_at + 7 days |

**S3 `cartoonify-media-<hex>`** (private, 7-day lifecycle):
- `originals/<owner>/<job_id>.<ext>` — user uploads (presigned POST, ≤5 MB)
- `cartoons/<owner>/<job_id>.png` — generated cartoons (worker PUT, ~1 MB)

## Image size controls

| Layer | Enforcement |
|---|---|
| Client | File `accept=` attribute, `File.size ≤ 5 MB`, probe dimensions ≤ 2048 px |
| Presigned POST | `content-length-range [0, 5242880]`, `Content-Type` exact match |
| Worker | EXIF strip, RGB convert, center-square-crop, resize to 1024×1024 before Bedrock |

## Authorization model

- API Gateway validates JWT signature against Cognito JWKS before any Lambda runs
- Every Lambda extracts `sub` from `event.requestContext.authorizer.jwt.claims`
- DynamoDB PK is `owner` — users cannot read or delete rows they don't own
- S3 access uses short-lived presigned URLs generated by the API (never direct bucket access)

## Modifying code

| Change | Action |
|---|---|
| Anything under `03-api/code/` | Re-run `./apply.sh` — Terraform re-zips and updates all five API Lambdas |
| `02-worker/cartoonify/*.py` or `Dockerfile` | Bump `WORKER_TAG` in `apply.sh` (e.g. `worker-rc2`), then re-run `./apply.sh` — the image-exists check will rebuild + push, and Terraform will update the worker Lambda's `image_uri` |
| Style prompts | Edit `STYLE_PROMPTS` in `02-worker/cartoonify/app.py` **and** `ALLOWED_STYLES` in `03-api/code/common.py` **and** `<option>` list in `04-webapp/index.html.tmpl` |
| Upload limits | Edit `MAX_UPLOAD_BYTES` in `03-api/code/common.py` **and** the two `MAX_*` constants in `04-webapp/index.html.tmpl` |
| Bedrock model | Edit the three `export BEDROCK_*` lines in [bedrock-config.sh](bedrock-config.sh) — see below |

## Changing the Bedrock model

The model is parameterized end-to-end. A single edit in
[bedrock-config.sh](bedrock-config.sh) retargets the pre-flight probe, the
worker Lambda env var, and the worker IAM policy. Both `apply.sh` and
`destroy.sh` source this file so they stay in sync:

```bash
export BEDROCK_MODEL_ID="stability.stable-image-control-structure-v1:0"
export BEDROCK_INFERENCE_PROFILE_ID="us.stability.stable-image-control-structure-v1:0"
export BEDROCK_MODEL_REGIONS='["us-east-1","us-east-2","us-west-2"]'
```

Flow:

- **`check_env.sh`** reads `BEDROCK_INFERENCE_PROFILE_ID` / `BEDROCK_MODEL_ID` (exported by `apply.sh`) and probes `bedrock list-inference-profiles` + a dry-run `invoke-model` before any Terraform runs
- **`apply.sh`** passes all three values to the 03-api stage as `-var=bedrock_model_id=...` / `-var=bedrock_inference_profile_id=...` / `-var=bedrock_model_regions=...`
- **`03-api/lambda-worker.tf`** builds the `bedrock:InvokeModel` IAM `Resource` list as `[inference-profile ARN in current region] + [foundation-model ARN for var.bedrock_model_id in each of var.bedrock_model_regions]`, and sets `BEDROCK_MODEL_ID = var.bedrock_inference_profile_id` on the worker Lambda
- **`02-worker/cartoonify/app.py`** reads `BEDROCK_MODEL_ID` at startup (now required — no default) and passes it to `bedrock.invoke_model`

Note: the worker's `BEDROCK_MODEL_ID` env var is set to the *inference profile*
ID, not the bare model ID — that's what `invoke_model` expects for cross-region
routing. The bare model ID (`var.bedrock_model_id`) only shows up in IAM.

If the new model uses a different request/response schema (e.g. Nova Canvas
`IMAGE_VARIATION` vs. Stability control-structure), also update the
`invoke_bedrock` payload in
[02-worker/cartoonify/app.py](02-worker/cartoonify/app.py) and bump
`WORKER_TAG` in `apply.sh` so the container is rebuilt and pushed.

## Manual API test

```bash
JWT="<paste sessionStorage.access_token from browser>"
BASE=$(cd 03-api && terraform output -raw api_endpoint)

# Request presigned upload
curl -s -X POST "$BASE/upload-url" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"content_type":"image/jpeg"}'

# Submit a job (after uploading to the presigned URL)
curl -s -X POST "$BASE/generate" \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"job_id":"...","key":"originals/.../....jpg","style":"pixar_3d"}'

# Poll
curl -s -H "Authorization: Bearer $JWT" "$BASE/result/<job_id>"

# Gallery
curl -s -H "Authorization: Bearer $JWT" "$BASE/history"
```

## Terraform state

Local state only — `.terraform/` directories inside each stage. No remote
backend. `destroy.sh` reads `web_bucket_name` and `media_bucket_name` from
`01-backend`'s state before destroying, so don't remove those files between
`apply.sh` and `destroy.sh`.

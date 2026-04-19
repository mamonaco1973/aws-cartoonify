#AWS #Serverless #AWSLambda #Bedrock #SQS #DynamoDB #APIGateway #Cognito #Terraform #Python #GenerativeAI

*Build an AI Image Pipeline on AWS (Bedrock + Lambda + SQS)*

Turn any photo into a cartoon using a fully serverless, event-driven pipeline on AWS — provisioned with Terraform and deployed with a single script. Users sign in with Cognito, upload a photo, pick a cartoon style, and a queue-driven worker invokes Amazon Bedrock's Stability image model to generate a stylized result. Originals and cartoons are stored privately in S3 and served through short-lived presigned URLs.

In this project we build an asynchronous AI image-processing pipeline from scratch — the browser uploads directly to S3, SQS decouples the slow Bedrock inference call from the API response, and a container-image Lambda running Pillow normalizes the photo before sending it to Bedrock. The whole thing runs without a single EC2 instance.

WHAT YOU'LL LEARN
• Invoking Amazon Bedrock image models (Stability stable-image-control-structure-v1:0) from Lambda
• Using SQS to decouple a slow AI inference call from a synchronous API response
• Running a container-image Lambda (ECR) with Pillow for image normalization
• Implementing PKCE OAuth2 Authorization Code flow with Cognito in a static SPA
• Attaching a JWT authorizer to API Gateway HTTP API v2
• Generating presigned S3 POST URLs with content-type and size enforcement
• Enforcing per-user daily quotas with a DynamoDB range query — no GSI required
• Proactive JWT token refresh using the Cognito /oauth2/token endpoint

INFRASTRUCTURE DEPLOYED
• Cognito User Pool with Hosted UI domain and SPA app client (PKCE, no secret)
• API Gateway HTTP API v2 with JWT authorizer (validates against Cognito JWKS)
• Five zip-packaged API Lambdas (Python 3.11): upload-url, submit, result, history, delete
• Worker Lambda (container image from ECR, 2048 MB, 120 s timeout) triggered by SQS
• SQS queue (cartoonify-jobs, visibility timeout 180 s, batch size 1)
• DynamoDB table (PAY_PER_REQUEST, PK=owner, SK=job_id time-sortable, 7-day TTL)
• S3 web bucket (public SPA hosting) + S3 media bucket (private, 7-day lifecycle)
• ECR repository for the worker container image
• IAM roles scoped per Lambda — API role cannot invoke Bedrock; worker role cannot delete

GitHub
https://github.com/mamonaco1973/aws-cartoonify

README
https://github.com/mamonaco1973/aws-cartoonify/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:14 Architecture
00:49 Build the Code
01:05 Build Results
01:49 Demo

#AWS #Serverless #AWSLambda #DynamoDB #APIGateway #Cognito #Terraform #Python #CRUD

*Secure a Serverless API in AWS (Cognito + API Gateway)*

Secure a serverless notes API on AWS using Amazon Cognito, API Gateway JWT authorization, and a PKCE OAuth2 flow — all provisioned with Terraform and deployed with a single script. The backend runs on five Python Lambda functions, DynamoDB stores the data, and a static S3 frontend handles the Cognito login redirect and token exchange.

In this project we build on the serverless CRUD API from the previous video and add real user authentication — each user can only read and write their own notes, enforced at the storage layer.

WHAT YOU'LL LEARN
• Provisioning a Cognito User Pool and Hosted UI with Terraform
• Implementing PKCE OAuth2 Authorization Code flow in a static SPA
• Attaching a JWT authorizer to API Gateway HTTP API v2
• Extracting the Cognito sub claim in Lambda as the per-user DynamoDB partition key
• Generating runtime config (config.json) at deploy time using Terraform outputs

INFRASTRUCTURE DEPLOYED
• Cognito User Pool with Hosted UI domain and SPA app client (PKCE, no secret)
• API Gateway HTTP API v2 with JWT authorizer (validates against Cognito JWKS)
• Five Lambda functions (Python 3.14, one per route: create/list/get/update/delete)
• Five IAM roles with least-privilege DynamoDB policies per operation
• DynamoDB table (PAY_PER_REQUEST, PK=owner (Cognito sub), SK=id)
• S3 bucket hosting the SPA (index.html + callback.html + config.json)

GitHub
https://github.com/mamonaco1973/aws-cognito-app

README
https://github.com/mamonaco1973/aws-cognito-app/blob/main/README.md

TIMESTAMPS
00:00 Introduction
00:18 Architecture
00:41 Build the Code
00:58 Build Results
01:38 Demo

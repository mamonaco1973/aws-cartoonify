# Video Script — Secure your Serverless API in AWS (Cognito + API Gateway)

---

## Introduction

[ Screen recording of the Notes Demo web app — logging in via Cognito Hosted UI, then creating and deleting notes ]

"In the last video we built a serverless CRUD API on AWS using Lambda, DynamoDB, and API Gateway. In this video we secure it with real user authentication using Amazon Cognito."

[ Architecture diagram — walk through it: browser, S3, Cognito, API Gateway, Lambda, DynamoDB ]

"We'll add a Cognito User Pool with a Hosted UI, a PKCE OAuth2 login flow, and a JWT authorizer on API Gateway — so every API call is verified before Lambda ever runs."

[ Terminal running apply.sh — Terraform output, ending with the website URL ]

"Follow along and in minutes you'll have a working authenticated API running in AWS."

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Highlight left block: Browser + S3 + Cognito ]

"The user opens a static web app from S3 and signs in with Cognito."

[ Highlight JWT arrow ]

"Cognito returns a JWT — and that token is sent with every API request."

[ Highlight API Gateway ]

"API Gateway validates the token before the request is allowed through."

[ Highlight Lambda ]

"Lambda handles the request and runs the application logic."

[ Highlight DynamoDB ]

"DynamoDB stores the data — the owner field is scoped to the authenticated user."

---

## Build Results

[ AWS Console — us-east-1 resources ]

"Let's look at what was deployed."

[ AWS Console — Cognito User Pool ]

"First — the Cognito User Pool. This is where user accounts live. Email-based sign-in, no custom code needed."

[ AWS Console — Cognito App Client ]

The app client is configured to authorize API access from a Single Page Application.

[ AWS Console — API Gateway]

Next — the API Gateway. 

[ Show Authorizers Section]

The JWT authorizer is attached here. 

[Show API call] 

API Gateway validates the caller's Bearer token before calling the lambda.

[ AWS Console — Lambda functions list ]

"Five Lambda functions are defined, each with least-privilege access."

[ AWS Console — DynamoDB table, notes-cognito ]

"DynamoDB stores the notes — partitioned by user"."

[ AWS Console — S3 bucket ]

"Finally, S3 hosts the frontend — index.html, callback.html, and config.json."

[ Browser — Notes Demo login page ]

"Navigate to the URL to launch the test app."

---

## Demo

[ Browser — Notes Demo, Login button visible ]

"When the app loads initially we are not logged in yet — the note list is empty and the controls are disabled"

[ Clicking Login — Cognito Hosted UI opens ]

"Click Login. The browser redirects to the Cognito Hosted UI."

[ Creating a new user account or signing in ]

"Sign in with an existing account — or create one here."

[ Cognito redirects back to callback.html ]

"Cognito redirects back to callback.html. The page exchanges the authorization code for tokens and stores the access token in sessionStorage."

[ Browser — Notes Demo, now logged in, DevTools → Network tab ]

"We're back in the app, now authenticated. Open DevTools so we can watch the API calls."

[ Refresh — GET /notes call visible with Authorization header ]

"The app calls the list endpoint — and you can see the Bearer token in the Authorization header."

[ Clicking New — modal opens, typing a title, clicking Create ]

"Create a new note."

[ Show network tab — POST with auth header ]

"A POST is made with the JWT. API Gateway validates it, Lambda extracts the sub, and the note is stored under this user's partition key."

[ Editing and clicking Save ]

"Update the note."

[ Show network tab ]

"A PUT call — same auth flow."

[ Clicking Delete ]

"Delete the note."

[ Browser — empty list ]

"In this demo we've exercised every API endpoint — all secured with Cognito JWT authentication."

---

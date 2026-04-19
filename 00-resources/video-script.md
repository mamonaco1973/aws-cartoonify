# Video Script — Secure your Serverless API in AWS (Cognito + API Gateway)

---

## Introduction

[ Opening Sequence ]

“Do you want to build an AI-powered image pipeline on AWS?”

[ Show Diagram ]

"In this project, we build a fully serverless pipeline that turns photos into cartoons using AWS and Bedrock."

[ Build B Roll ]

Follow along and in minutes you’ll have a fully working AI pipeline running on AWS.

---

## Architecture

[ Full diagram ]

"Let's walk through the architecture before we build."

[ Diagram then Congito ]

"First, the user signs into the web application using Cognito."

[ Choose File then Diagam ]

"When the user selects “Choose File”, the image is uploaded to an S3 bucket."

[  Cartoonify ]

When the user selects “Cartoonify”, the API does two things:

[ Highlight Dynamo DB]

It creates a job record in DynamoDB

[ Highlight SQS queue ]

Then it sends a message to the image processing SQS queue.

[ Highlight Lambda ]

"SQS triggers the worker Lambda."

[ Show bedrock ]

"The worker Lambda calls Bedrock to generate the cartoon."

[ Show S3 Media Bucket]

"The generated image is written back to S3".

[ Final Dynamo DB State]

When processing completes, the job status is updated in DynamoDB.

[ Show final result ]

The web application refreshes and displays the generated image.

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

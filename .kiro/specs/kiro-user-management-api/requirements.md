# Requirements Document

## Introduction

The Kiro User Management API is a serverless system that automates the upgrade of users to Kiro Pro when their free credits are depleted. The system analyzes credit usage screenshots using AWS Bedrock AI (Nova Pro model) and automatically provisions access through IAM Identity Center. The application consists of backend infrastructure (Lambda functions, API Gateway, S3), frontend infrastructure (CloudFront, S3), a web interface (vanilla JavaScript), and deployment/testing scripts.

## Glossary

- **System**: The Kiro User Management API application
- **User**: An end user who wants to upgrade to Kiro Pro
- **Admin**: An administrator who can directly create users
- **Identity_Center**: AWS IAM Identity Center service for user management
- **Bedrock**: AWS Bedrock service with Nova Pro model for AI image analysis
- **Screenshot**: PNG image showing credit usage in the Kiro application
- **Kiro_Pro_Group**: The IAM Identity Center group that grants Kiro Pro access
- **API_Gateway**: AWS API Gateway REST API service
- **Lambda_Function**: AWS Lambda serverless compute function
- **CloudFormation**: AWS Infrastructure as Code service
- **CloudFront**: AWS CDN service for global content delivery
- **Parameter_Store**: AWS Systems Manager Parameter Store for configuration
- **S3_Bucket**: AWS S3 storage bucket

## Requirements

### Requirement 1: User Credit Verification and Auto-Provisioning

**User Story:** As a user with depleted credits, I want to upload a screenshot of my credit usage, so that I can be automatically upgraded to Kiro Pro.

#### Acceptance Criteria

1. WHEN a user submits a screenshot with their email, first name, and last name, THE System SHALL validate that all required fields are present
2. WHEN a screenshot is submitted, THE System SHALL verify that the email address in the screenshot matches the submitted email address
3. WHEN a screenshot is analyzed, THE System SHALL use Bedrock Nova Pro model to determine if credits are depleted
4. IF credits are depleted and email matches, THEN THE System SHALL create the user in Identity_Center and add them to Kiro_Pro_Group
5. IF credits are not depleted, THEN THE System SHALL reject the request and return an appropriate error message
6. WHEN a user is successfully provisioned, THE System SHALL return a success response with user details
7. WHEN a screenshot is processed, THE System SHALL store it in S3_Bucket with a timestamp and email identifier

### Requirement 2: Duplicate User Detection

**User Story:** As a system administrator, I want to prevent duplicate user creation, so that the system maintains data integrity.

#### Acceptance Criteria

1. WHEN a user creation request is received, THE System SHALL check if a user with the same email already exists in Identity_Center
2. IF a user already exists, THEN THE System SHALL check if they are already in Kiro_Pro_Group
3. IF the user exists and is already in Kiro_Pro_Group, THEN THE System SHALL return a success response indicating the user already has access
4. IF the user exists but is not in Kiro_Pro_Group, THEN THE System SHALL add them to the group and return success

### Requirement 2.1: Lambda Cross-Invocation Pattern

**User Story:** As a system architect, I want the CheckCreditsFunction to invoke UserManagementFunction, so that user creation logic is centralized.

#### Acceptance Criteria

1. WHEN CheckCreditsFunction needs to add a user to Kiro Pro, THE System SHALL invoke UserManagementFunction using Lambda invoke API
2. WHEN invoking UserManagementFunction, THE System SHALL use InvocationType RequestResponse for synchronous execution
3. WHEN an existing user needs to be added to Kiro Pro, THE System SHALL pass existing_user_id parameter to skip user creation
4. WHEN UserManagementFunction receives existing_user_id, THE System SHALL skip user creation and only add the user to Kiro_Pro_Group
5. WHEN the Lambda invocation fails, THE System SHALL return an error response with the failure reason
6. WHEN the Lambda invocation succeeds, THE System SHALL parse the response payload and extract the user_id

### Requirement 3: Administrative User Creation

**User Story:** As an administrator, I want to directly create users without credit verification, so that I can manually provision Kiro Pro access.

#### Acceptance Criteria

1. WHEN an admin submits a create-user request with name, email, firstName, and lastName, THE System SHALL validate all required fields
2. WHEN a valid admin request is received, THE System SHALL create the user in Identity_Center without requiring screenshot verification
3. WHEN creating an admin user, THE System SHALL add them to Kiro_Pro_Group automatically
4. WHEN an admin user is created, THE System SHALL return the user details including userId

### Requirement 4: Kiro Pro Group Management

**User Story:** As a system, I want to automatically manage the Kiro Pro group, so that users can be provisioned without manual setup.

#### Acceptance Criteria

1. WHEN the System needs to add a user to Kiro_Pro_Group, THE System SHALL first check if the group exists
2. IF Kiro_Pro_Group does not exist, THEN THE System SHALL create it with the display name "Kiro Pro"
3. WHEN Kiro_Pro_Group is created or found, THE System SHALL store the group ID in Parameter_Store
4. WHEN adding a user to a group, THE System SHALL verify the operation succeeded

### Requirement 5: Screenshot Storage and Lifecycle

**User Story:** As a compliance officer, I want all screenshots stored with audit trails, so that we can review upgrade decisions.

#### Acceptance Criteria

1. WHEN a screenshot is processed, THE System SHALL store it in S3_Bucket under the screenshots/ prefix
2. WHEN storing a screenshot, THE System SHALL use the naming format: {timestamp}-{email}.png for approved requests
3. WHEN storing a screenshot, THE System SHALL use the naming format: {timestamp}-{email}-deny.png for denied requests
4. WHEN a screenshot is stored, THE System SHALL apply a 90-day lifecycle policy for automatic deletion
5. WHEN storing a screenshot, THE System SHALL decode the base64-encoded image data correctly
6. WHEN generating the S3 key, THE System SHALL sanitize the email address by replacing @ with _at_, . with _, and + with _plus_
7. WHEN generating the S3 key, THE System SHALL remove any non-alphanumeric characters except underscore and hyphen
8. WHEN storing a screenshot, THE System SHALL include metadata with email and upload timestamp
9. WHEN storing a screenshot, THE System SHALL set ContentType to image/png

### Requirement 5.1: Bedrock Prompt Template

**User Story:** As a system administrator, I want a configurable Bedrock prompt template, so that I can adjust the AI analysis criteria.

#### Acceptance Criteria

1. WHEN the backend stack is deployed, THE System SHALL create a Parameter_Store entry with a default Bedrock prompt template
2. THE Bedrock prompt template SHALL include instructions to verify both email match and credit depletion
3. THE Bedrock prompt template SHALL use {email} as a placeholder for dynamic email substitution
4. THE Bedrock prompt template SHALL instruct the AI to check for 500 bonus credits and 50 monthly credits
5. THE Bedrock prompt template SHALL require a two-part response format: MATCH/NOMATCH for email and YES/NO for credits
6. THE Bedrock prompt template SHALL provide examples of valid responses (MATCH,YES / MATCH,NO / NOMATCH,YES / NOMATCH,NO)
7. WHEN the prompt template is updated, THE System SHALL allow administrators to modify it via Parameter_Store without redeploying

### Requirement 6: API Authentication and Rate Limiting

**User Story:** As a security administrator, I want API requests authenticated and rate-limited, so that the system is protected from abuse.

#### Acceptance Criteria

1. WHEN a request is received by API_Gateway, THE System SHALL require an x-api-key header
2. IF the x-api-key header is missing or invalid, THEN THE System SHALL return a 403 Forbidden response
3. WHEN rate limiting is configured, THE System SHALL enforce 1 request per second steady rate
4. WHEN rate limiting is configured, THE System SHALL allow burst capacity of 5 requests
5. WHEN rate limiting is configured, THE System SHALL enforce a quota of 10,000 requests per day

### Requirement 7: Backend Infrastructure Deployment

**User Story:** As a DevOps engineer, I want to deploy backend infrastructure using CloudFormation, so that the system is reproducible and maintainable.

#### Acceptance Criteria

1. WHEN deploying the backend, THE System SHALL create two Lambda_Functions with inline Python 3.12 code
2. WHEN deploying the backend, THE System SHALL create an API_Gateway REST API with two endpoints: POST /create-user and POST /check-credits
3. WHEN deploying the backend, THE System SHALL create an S3_Bucket for screenshot storage
4. WHEN deploying the backend, THE System SHALL create IAM roles with least privilege permissions for Lambda execution
5. WHEN deploying the backend, THE System SHALL store configuration in Parameter_Store including API key, Bedrock prompt, and group ID
6. WHEN deploying the backend, THE System SHALL configure Lambda timeout of 30 seconds for UserManagementFunction
7. WHEN deploying the backend, THE System SHALL configure Lambda timeout of 60 seconds for CheckCreditsFunction
8. WHEN deploying the backend, THE System SHALL enable CORS on API_Gateway endpoints

### Requirement 8: Frontend Infrastructure Deployment

**User Story:** As a DevOps engineer, I want to deploy frontend infrastructure using CloudFormation, so that users can access the web interface globally.

#### Acceptance Criteria

1. WHEN deploying the frontend, THE System SHALL create a CloudFront distribution with Origin Access Control
2. WHEN deploying the frontend, THE System SHALL create an S3_Bucket for static website hosting
3. WHEN deploying the frontend, THE System SHALL configure HTTPS-only access with redirect-to-https viewer protocol policy
4. WHEN deploying the frontend, THE System SHALL configure custom error responses to redirect 403 and 404 errors to index.html
5. WHEN deploying the frontend, THE System SHALL set index.html as the DefaultRootObject
6. WHEN deploying the frontend, THE System SHALL store the API endpoint URL in Parameter_Store

### Requirement 9: Web Interface Implementation

**User Story:** As a user, I want a web interface to upload screenshots and check my credit status, so that I can easily upgrade to Kiro Pro.

#### Acceptance Criteria

1. WHEN the web interface loads, THE System SHALL display an API configuration card for entering the API key
2. WHEN a user enters an API key, THE System SHALL store it in browser session storage
3. WHEN a user toggles API key visibility, THE System SHALL switch between password and text display modes
4. WHEN a user selects an image file, THE System SHALL preview the image before submission
5. WHEN a user submits the form without an API key, THE System SHALL display an alert and focus the API key input field
6. WHEN a user submits the form, THE System SHALL validate that required fields (email, image) are present
7. WHEN submitting the form, THE System SHALL encode the image as base64 PNG data without the data URL prefix
8. WHEN the API request is in progress, THE System SHALL disable the submit button and show a loading indicator
9. WHEN the API returns a 403 status, THE System SHALL display an authentication failed message with instructions to retrieve the API key
10. WHEN the API returns a 429 status, THE System SHALL display a rate limit exceeded message
11. WHEN the API request completes successfully, THE System SHALL display result messages based on the response data (already in Kiro Pro, email mismatch, credits available, upgrade successful, or upgrade failed)
12. WHEN a successful upgrade occurs, THE System SHALL reset the form and clear the image preview
13. WHEN a network error occurs, THE System SHALL display a connection error message with troubleshooting guidance

### Requirement 10: Backend Deployment Script

**User Story:** As a DevOps engineer, I want an automated deployment script for the backend, so that I can deploy consistently without manual steps.

#### Acceptance Criteria

1. WHEN the deployment script runs, THE System SHALL auto-detect the Identity_Center instance ARN in the current region
2. IF no Identity_Center instance exists, THEN THE System SHALL prompt the user to create one
3. WHEN no API key is provided, THE System SHALL generate a secure 32-character API key using OpenSSL
4. WHEN deploying, THE System SHALL check if the stack already exists
5. IF the stack exists and is in a failed state, THEN THE System SHALL prompt the user to delete it first
6. WHEN the -f flag is provided, THE System SHALL skip confirmation prompts and force update
7. WHEN deployment completes, THE System SHALL output the API endpoint URL and API key

### Requirement 11: Frontend Deployment Script

**User Story:** As a DevOps engineer, I want an automated deployment script for the frontend, so that I can deploy the web interface consistently.

#### Acceptance Criteria

1. WHEN the frontend deployment script runs, THE System SHALL retrieve the API endpoint from Parameter_Store
2. WHEN deploying the frontend, THE System SHALL create or update the CloudFormation stack
3. WHEN the -f flag is provided, THE System SHALL skip confirmation prompts and force update
4. WHEN deployment completes, THE System SHALL output the CloudFront URL

### Requirement 12: Frontend File Upload Script

**User Story:** As a DevOps engineer, I want to upload frontend files and invalidate the CloudFront cache, so that users see the latest version.

#### Acceptance Criteria

1. WHEN the upload script runs, THE System SHALL retrieve the S3_Bucket name and CloudFront distribution ID from CloudFormation outputs
2. WHEN uploading files, THE System SHALL generate a config.js file with the API endpoint URL
3. WHEN uploading files, THE System SHALL upload index.html, styles.css, app.js, and config.js to S3_Bucket
4. WHEN files are uploaded, THE System SHALL create a CloudFront cache invalidation for all files (/*) 
5. WHEN invalidation is created, THE System SHALL wait for the invalidation to complete before exiting

### Requirement 13: API Testing Script

**User Story:** As a developer, I want automated API tests, so that I can verify the system works correctly after deployment.

#### Acceptance Criteria

1. WHEN the test script runs, THE System SHALL automatically retrieve the API endpoint from CloudFormation outputs
2. WHEN the test script runs, THE System SHALL automatically retrieve the API key from Parameter_Store
3. WHEN testing the create-user endpoint, THE System SHALL send a valid request and verify a 200 response
4. WHEN testing the check-credits endpoint, THE System SHALL send a request with a base64-encoded screenshot
5. WHEN tests complete, THE System SHALL output clear success or failure messages

### Requirement 13.1: Bedrock Prompt Update Script

**User Story:** As a system administrator, I want to update the Bedrock prompt without redeploying, so that I can adjust AI analysis criteria quickly.

#### Acceptance Criteria

1. WHEN the update script runs, THE System SHALL accept a new prompt text as input
2. WHEN updating the prompt, THE System SHALL update the Parameter_Store entry at /kiro/kiro-user-management-api/bedrock-prompt
3. WHEN the prompt is updated, THE System SHALL preserve the {email} placeholder for dynamic substitution
4. WHEN the update completes, THE System SHALL confirm the new prompt has been stored
5. WHEN the CheckCreditsFunction runs after update, THE System SHALL use the new prompt immediately without requiring Lambda redeployment

### Requirement 14: Bedrock Image Analysis

**User Story:** As a system, I want to analyze screenshots using AI, so that I can accurately determine if credits are depleted.

#### Acceptance Criteria

1. WHEN analyzing a screenshot, THE System SHALL invoke Bedrock Nova Pro model (us.amazon.nova-pro-v1:0) in us-west-2 region
2. WHEN invoking Bedrock, THE System SHALL retrieve the system prompt from Parameter_Store at /kiro/kiro-user-management-api/bedrock-prompt
3. IF the prompt cannot be retrieved from Parameter_Store, THEN THE System SHALL use a default fallback prompt
4. WHEN constructing the prompt, THE System SHALL substitute the {email} placeholder with the user's email address
5. WHEN invoking Bedrock, THE System SHALL pass the base64-encoded image data in the request with format "png"
6. WHEN invoking Bedrock, THE System SHALL configure inference with max_new_tokens of 10 and temperature of 0.0
7. WHEN Bedrock responds, THE System SHALL parse the response to extract a two-part answer: email match status (MATCH/NOMATCH) and credit status (YES/NO)
8. IF the Bedrock response format is unexpected, THEN THE System SHALL default to safe values (email_match=false, credits_used_up=false)
9. IF email does not match, THEN THE System SHALL save the screenshot with -deny suffix regardless of credit status
10. IF email matches and credits are depleted, THEN THE System SHALL save the screenshot without suffix and proceed with user creation
11. IF email matches but credits are not depleted, THEN THE System SHALL save the screenshot with -deny suffix

### Requirement 15: Error Handling and Logging

**User Story:** As a developer, I want comprehensive error handling and logging, so that I can troubleshoot issues effectively.

#### Acceptance Criteria

1. WHEN an error occurs in a Lambda_Function, THE System SHALL log the error to CloudWatch with full context
2. WHEN an API request fails, THE System SHALL return a JSON response with an error message
3. WHEN a validation error occurs, THE System SHALL return a 400 Bad Request status code
4. WHEN an authentication error occurs, THE System SHALL return a 403 Forbidden status code
5. WHEN an internal error occurs, THE System SHALL return a 500 Internal Server Error status code
6. WHEN logging, THE System SHALL include request IDs for traceability

### Requirement 16: Infrastructure Constraints

**User Story:** As a system architect, I want the system to respect AWS service constraints, so that deployment succeeds reliably.

#### Acceptance Criteria

1. THE System SHALL support only one Identity_Center instance per AWS region
2. WHEN generating S3_Bucket names, THE System SHALL ensure global uniqueness by including the AWS account ID
3. WHEN deploying Lambda_Functions, THE System SHALL embed Python code inline in CloudFormation templates
4. THE System SHALL use pure CloudFormation without SAM CLI
5. THE System SHALL require Bedrock model access to be enabled in us-west-2 region before deployment

### Requirement 17: Security Best Practices

**User Story:** As a security engineer, I want the system to follow security best practices, so that user data and access are protected.

#### Acceptance Criteria

1. WHEN creating IAM roles, THE System SHALL apply least privilege permissions
2. WHEN storing sensitive data in Parameter_Store, THE System SHALL use SecureString type
3. WHEN serving frontend content, THE System SHALL enforce HTTPS-only access
4. WHEN configuring S3_Bucket access, THE System SHALL use Origin Access Control instead of public bucket access
5. WHEN handling API keys, THE System SHALL never log or expose them in responses
6. THE System SHALL include a security review notice indicating AI-generated code requires review before production use

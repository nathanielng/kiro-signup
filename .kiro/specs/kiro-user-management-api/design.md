# Design Document: Kiro User Management API

## Overview

The Kiro User Management API is a serverless application built entirely on AWS services that automates the upgrade of users to Kiro Pro when their free credits are depleted. The system uses AI-powered image analysis (AWS Bedrock Nova Pro) to verify credit depletion from screenshots, validates email ownership, and automatically provisions access through IAM Identity Center.

The application follows a pure Infrastructure as Code approach using CloudFormation templates with inline Lambda code (no SAM CLI), vanilla JavaScript for the frontend (no build process), and bash scripts for deployment automation.

### Key Design Principles

1. **Serverless Architecture**: No servers to manage, automatic scaling, pay-per-use pricing
2. **Infrastructure as Code**: All resources defined in CloudFormation templates for reproducibility
3. **Security First**: Least privilege IAM roles, API key authentication, HTTPS-only, no public S3 access
4. **Audit Trail**: All screenshots stored in S3 with 90-day retention for compliance
5. **Simplicity**: Inline Lambda code, vanilla JavaScript, no build tools or frameworks

## Architecture

### High-Level Architecture

```
┌─────────────┐
│   User      │
│  (Browser)  │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────────────────────────────────────────┐
│              CloudFront Distribution                    │
│         (Global CDN with Origin Access Control)         │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
              ┌────────────────┐
              │  S3 Bucket     │
              │  (Frontend)    │
              │  - index.html  │
              │  - styles.css  │
              │  - app.js      │
              │  - config.js   │
              └────────────────┘

┌─────────────┐
│   User      │
│  (Browser)  │
└──────┬──────┘
       │ HTTPS + x-api-key
       ▼
┌─────────────────────────────────────────────────────────┐
│              API Gateway (REST API)                     │
│         - POST /create-user (admin)                     │
│         - POST /check-credits (primary flow)            │
│         - Rate limiting: 1/sec, burst 5, 10K/day        │
└──────────────────────┬──────────────────────────────────┘
                       │
       ┌───────────────┴───────────────┐
       │                               │
       ▼                               ▼
┌──────────────────┐          ┌──────────────────┐
│ UserManagement   │◄─────────│ CheckCredits     │
│ Lambda Function  │  invoke  │ Lambda Function  │
│ (Python 3.12)    │          │ (Python 3.12)    │
│ - 30s timeout    │          │ - 60s timeout    │
└────────┬─────────┘          └────────┬─────────┘
         │                             │
         │                             │
         ▼                             ▼
┌─────────────────────────────────────────────────────────┐
│         IAM Identity Center                             │
│         - User creation                                 │
│         - Group management (Kiro Pro)                   │
│         - Group membership                              │
└─────────────────────────────────────────────────────────┘

                                       │
                                       ▼
                              ┌─────────────────┐
                              │  AWS Bedrock    │
                              │  Nova Pro       │
                              │  (us-west-2)    │
                              └─────────────────┘

                                       │
                                       ▼
                              ┌─────────────────┐
                              │  S3 Bucket      │
                              │  (Screenshots)  │
                              │  90-day policy  │
                              └─────────────────┘

                                       │
                                       ▼
                              ┌─────────────────┐
                              │ Parameter Store │
                              │ - API key       │
                              │ - Bedrock prompt│
                              │ - Group ID      │
                              └─────────────────┘
```

### Component Interaction Flow

**Primary User Flow (Check Credits)**:
1. User enters API key in web interface (stored in session storage)
2. User uploads screenshot showing depleted credits
3. Frontend encodes image as base64 and sends POST to /check-credits
4. API Gateway validates API key and rate limits
5. CheckCreditsFunction receives request:
   - Checks if user already exists and has Kiro Pro (early return if yes)
   - Invokes Bedrock to analyze screenshot (email match + credit depletion)
   - Saves screenshot to S3 with appropriate suffix
   - If verified, invokes UserManagementFunction to add user to Kiro Pro
6. UserManagementFunction:
   - Creates user in Identity Center (or uses existing user ID)
   - Gets/creates Kiro Pro group
   - Adds user to group
7. Response returned to frontend with detailed status
8. Frontend displays appropriate message based on result

**Admin Flow (Create User)**:
1. Admin sends POST to /create-user with user details
2. API Gateway validates API key
3. UserManagementFunction creates user and adds to Kiro Pro group
4. Response returned with user ID

## Components and Interfaces

### 1. Backend Infrastructure (CloudFormation)

**Template**: `backend-template.yaml`

**Resources**:
- **UserManagementLambdaRole**: IAM role with permissions for Identity Center operations
- **CheckCreditsLambdaRole**: IAM role with permissions for Bedrock, S3, Lambda invoke, SSM, Identity Center
- **UserManagementFunction**: Lambda function for user creation and group management
- **CheckCreditsFunction**: Lambda function for credit verification and orchestration
- **UserManagementApi**: API Gateway REST API
- **CreateUserResource**: API Gateway resource for /create-user
- **CheckCreditsResource**: API Gateway resource for /check-credits
- **CreateUserMethod**: POST method with API key authentication
- **CheckCreditsMethod**: POST method with API key authentication
- **OPTIONS methods**: CORS support for both endpoints
- **ApiDeployment**: API Gateway deployment to prod stage
- **ApiKey**: API Gateway API key (immutable)
- **UsagePlan**: Rate limiting configuration (1/sec, burst 5, 10K/day)
- **UsagePlanKey**: Links API key to usage plan
- **Lambda permissions**: Allow API Gateway to invoke Lambda functions
- **ApiKeyParameter**: SSM Parameter for API key storage
- **KiroProGroupParameter**: SSM Parameter for group ID (placeholder, updated by Lambda)
- **BedrockPromptParameter**: SSM Parameter for Bedrock prompt template

**Parameters**:
- `IdentityCenterInstanceArn`: ARN of IAM Identity Center instance
- `ApiKeyValue`: API key value (NoEcho, minimum 20 characters)

**Outputs**:
- `ApiEndpoint`: Full API Gateway URL
- `CreateUserEndpoint`: /create-user endpoint URL
- `CheckCreditsEndpoint`: /check-credits endpoint URL
- `ApiKeyParameterName`: SSM parameter name for API key
- `BedrockPromptParameterName`: SSM parameter name for Bedrock prompt
- `ApiKeyId`: API key resource ID
- `UserManagementLambdaArn`: Lambda function ARN
- `CheckCreditsLambdaArn`: Lambda function ARN

### 2. Frontend Infrastructure (CloudFormation)

**Template**: `frontend-template.yaml`

**Resources**:
- **CloudFrontOAC**: Origin Access Control for S3 bucket access
- **CloudFrontDistribution**: CDN distribution with:
  - DefaultRootObject: index.html
  - ViewerProtocolPolicy: redirect-to-https
  - Custom error responses (403/404 → index.html)
  - Caching configuration
- **S3BucketPolicy**: Allows CloudFront to access S3 bucket
- **ApiEndpointParameter**: SSM Parameter storing API endpoint URL

**Parameters**:
- `ApiEndpoint`: API Gateway endpoint URL (from backend stack)
- `S3BucketName`: Existing S3 bucket name for frontend files

**Outputs**:
- `CloudFrontURL`: Distribution URL
- `CloudFrontDistributionId`: Distribution ID for cache invalidation
- `S3BucketName`: Bucket name
- `FrontendPath`: Path in bucket (root)

### 3. UserManagementFunction (Lambda)

**Runtime**: Python 3.12  
**Timeout**: 30 seconds  
**Handler**: `index.lambda_handler`

**Environment Variables**:
- `IDENTITY_CENTER_INSTANCE_ARN`: IAM Identity Center instance ARN

**Functions**:

```python
def lambda_handler(event, context) -> dict:
    """
    Main entry point. Handles both direct user creation and 
    adding existing users to Kiro Pro group.
    
    Input (from API Gateway or Lambda invoke):
    {
        "name": str,
        "email": str,
        "firstName": str (optional),
        "lastName": str (optional),
        "existing_user_id": str (optional, skips user creation)
    }
    
    Output:
    {
        "statusCode": int,
        "headers": dict (CORS headers),
        "body": str (JSON)
    }
    """

def get_identity_store_id(instance_arn: str) -> str:
    """
    Extract identity store ID from Identity Center instance.
    Falls back to first available instance if ARN doesn't match.
    
    Returns: Identity store ID or None
    """

def create_identity_center_user(
    identity_store_id: str,
    name: str,
    email: str,
    first_name: str,
    last_name: str
) -> dict:
    """
    Create user in IAM Identity Center.
    Checks for duplicates first.
    
    Returns: {"success": bool, "user_id": str, "error": str}
    """

def find_user_by_email(identity_store_id: str, email: str) -> dict:
    """
    Search for user by email address.
    
    Returns: User object or None
    """

def get_kiro_pro_group_id(identity_store_id: str) -> str:
    """
    Get Kiro Pro group ID. Creates group if it doesn't exist.
    Checks environment variable first, then searches, then creates.
    
    Returns: Group ID or None
    """

def add_user_to_group(
    identity_store_id: str,
    user_id: str,
    group_id: str
) -> dict:
    """
    Add user to group membership.
    
    Returns: {"success": bool, "error": str}
    """

def create_response(status_code: int, body: any) -> dict:
    """
    Format HTTP response with CORS headers.
    """
```

**IAM Permissions**:
- `sso-admin:*` - Identity Center administration
- `identitystore:*` - Identity store operations
- `sso:ListInstances` - List Identity Center instances
- CloudWatch Logs (via managed policy)

### 4. CheckCreditsFunction (Lambda)

**Runtime**: Python 3.12  
**Timeout**: 60 seconds  
**Handler**: `index.lambda_handler`

**Environment Variables**:
- `KIRO_S3_BUCKET`: S3 bucket name for screenshots
- `USER_MANAGEMENT_FUNCTION_NAME`: Name of UserManagementFunction

**Functions**:

```python
def lambda_handler(event, context) -> dict:
    """
    Main entry point. Orchestrates credit verification flow.
    
    Input (from API Gateway):
    {
        "image": str (base64 PNG without data URL prefix),
        "email": str,
        "firstName": str (optional),
        "lastName": str (optional),
        "image_name": str (optional)
    }
    
    Output:
    {
        "statusCode": int,
        "headers": dict (CORS headers),
        "body": str (JSON with detailed status)
    }
    """

def check_user_kiro_pro_status(email: str) -> dict:
    """
    Check if user exists and is in Kiro Pro group.
    
    Returns: {
        "user_exists": bool,
        "user_id": str or None,
        "in_kiro_pro": bool
    }
    """

def add_user_to_kiro_pro(
    email: str,
    first_name: str,
    last_name: str,
    existing_user_id: str = None
) -> dict:
    """
    Invoke UserManagementFunction to add user to Kiro Pro.
    Extracts names from email if not provided.
    
    Returns: {"success": bool, "user_id": str, "error": str}
    """

def check_credits_used_up(
    image_base64: str,
    email: str,
    image_name: str
) -> dict:
    """
    Analyze screenshot with Bedrock and save to S3.
    
    Returns: {
        "email_match": bool,
        "credits_used_up": bool,
        "s3_uri": str,
        "timestamp": str (ISO format)
    }
    """

def get_s3_bucket_name() -> str:
    """
    Get S3 bucket name from environment or construct default.
    Default: kiro-user-management-api-screenshots-{account_id}
    """

def generate_s3_key(email: str, credits_used_up: bool) -> str:
    """
    Generate S3 key with timestamp and sanitized email.
    Format: screenshots/{timestamp}-{sanitized_email}[-deny].png
    
    Sanitization:
    - @ → _at_
    - . → _
    - + → _plus_
    - Remove non-alphanumeric except _ and -
    """

def save_image_to_s3(
    image_data: bytes,
    bucket_name: str,
    s3_key: str,
    email: str
) -> str:
    """
    Upload image to S3 with metadata.
    
    Returns: S3 URI (s3://bucket/key) or None
    """

def create_response(status_code: int, body: any) -> dict:
    """
    Format HTTP response with CORS headers.
    """
```

**IAM Permissions**:
- `bedrock:InvokeModel` - Invoke Bedrock models
- `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` - S3 operations
- `sts:GetCallerIdentity` - Get AWS account ID
- `lambda:InvokeFunction` - Invoke UserManagementFunction
- `ssm:GetParameter` - Read Bedrock prompt from Parameter Store
- `sso:ListInstances` - List Identity Center instances
- `identitystore:ListUsers`, `identitystore:ListGroups`, `identitystore:ListGroupMemberships` - Read Identity Center data
- CloudWatch Logs (via managed policy)

### 5. Frontend Application

**Files**: `index.html`, `styles.css`, `app.js`, `config.js`

**index.html Structure**:
- Header with title and subtitle
- API Configuration Card:
  - API key input (password type with toggle visibility)
  - Session storage persistence
  - Hint text
- Credit Check Form:
  - Email input (required)
  - First name input (optional)
  - Last name input (optional)
  - File upload with drag-and-drop support
  - Image preview
  - Submit button with loading state
- Result display area (hidden by default)
- Footer

**app.js Functions**:

```javascript
function toggleApiKeyVisibility()
// Toggle between password and text input types

function getApiKey() -> string
// Retrieve API key from input field

function validateApiKey() -> boolean
// Check if API key is provided, show alert if not

function fileToBase64(file) -> Promise<string>
// Convert File object to base64 string (without data URL prefix)

// Event Listeners:
// - screenshot-upload change: Preview image
// - check-credits-form submit: Handle form submission
// - api-key-input change: Save to sessionStorage
// - DOMContentLoaded: Load API key from sessionStorage
```

**Form Submission Flow**:
1. Validate API key is present
2. Disable submit button, show loading indicator
3. Read file as base64
4. Construct payload with image, email, optional names
5. POST to /check-credits with x-api-key header
6. Handle response:
   - 403: Authentication failed message
   - 429: Rate limit exceeded message
   - 200: Parse response and display appropriate message:
     - already_in_kiro_pro: Success message
     - email_match=false: Email verification failed
     - credits_used_up=false: Credits still available
     - credits_used_up=true && user_added_to_kiro_pro=true: Upgrade successful
     - credits_used_up=true && user_added_to_kiro_pro=false: Upgrade failed
   - Other errors: Generic error message
7. Reset form on success
8. Re-enable submit button, hide loading indicator

**styles.css Features**:
- CSS variables for theming
- Responsive design (mobile-friendly with media queries)
- Card-based layout with shadows
- Gradient background for API config card
- Smooth transitions and animations
- File upload with dashed border and hover effects
- Result display with color-coded backgrounds (success/error/warning)

### 6. Deployment Scripts

**deploy-backend.sh**:
- Checks for Identity Center instance, prompts to create if missing
- Generates secure 32-character API key if not provided
- Checks existing stack status, handles failed states
- Supports -f flag for force update (skip prompts)
- Deploys CloudFormation stack with parameters
- Outputs API endpoint and API key

**deploy-frontend.sh**:
- Retrieves API endpoint from backend stack
- Creates S3 bucket if it doesn't exist
- Applies lifecycle policy for screenshots (90-day retention)
- Checks if frontend stack exists, prompts for update/recreate
- Supports -f flag for force update
- Deploys CloudFormation stack
- Outputs CloudFront URL

**upload-frontend.sh**:
- Retrieves S3 bucket name and CloudFront distribution ID
- Generates config.js with API endpoint
- Uploads HTML, CSS, JS files to S3 with appropriate content types and cache control
- Creates CloudFront cache invalidation for all files (/*) 
- Waits for invalidation to complete
- Outputs CloudFront URL

**update-bedrock-prompt.sh** (mentioned in structure):
- Updates Bedrock prompt in Parameter Store
- Allows changing AI analysis criteria without redeployment

## Data Models

### API Request/Response Models

**POST /create-user Request**:
```json
{
  "name": "string (required)",
  "email": "string (required, email format)",
  "firstName": "string (optional)",
  "lastName": "string (optional)"
}
```

**POST /create-user Response (Success)**:
```json
{
  "message": "User created successfully",
  "user_id": "string (Identity Center user ID)",
  "email": "string",
  "group": "Kiro Pro"
}
```

**POST /check-credits Request**:
```json
{
  "image": "string (required, base64 PNG without data URL prefix)",
  "email": "string (required, email format)",
  "firstName": "string (optional)",
  "lastName": "string (optional)",
  "image_name": "string (optional, default: screenshot.png)"
}
```

**POST /check-credits Response (Already in Kiro Pro)**:
```json
{
  "email": "string",
  "already_in_kiro_pro": true,
  "message": "You are already on the Kiro Pro plan."
}
```

**POST /check-credits Response (Email Mismatch)**:
```json
{
  "email": "string",
  "user_exists": boolean,
  "already_in_kiro_pro": false,
  "email_match": false,
  "credits_used_up": boolean,
  "s3_uri": "string",
  "timestamp": "string (ISO format)",
  "user_added_to_kiro_pro": false,
  "message": "Email verification failed..."
}
```

**POST /check-credits Response (Credits Available)**:
```json
{
  "email": "string",
  "user_exists": boolean,
  "already_in_kiro_pro": false,
  "email_match": true,
  "credits_used_up": false,
  "s3_uri": "string",
  "timestamp": "string (ISO format)",
  "user_added_to_kiro_pro": false,
  "message": "Credits are still available..."
}
```

**POST /check-credits Response (Upgrade Successful)**:
```json
{
  "email": "string",
  "user_exists": boolean,
  "already_in_kiro_pro": false,
  "email_match": true,
  "credits_used_up": true,
  "s3_uri": "string",
  "timestamp": "string (ISO format)",
  "user_added_to_kiro_pro": true,
  "user_id": "string",
  "message": "Credits depleted. User successfully added to Kiro Pro group."
}
```

### Bedrock Request/Response Models

**Bedrock Invoke Model Request**:
```json
{
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "image": {
            "format": "png",
            "source": {
              "bytes": "string (base64)"
            }
          }
        },
        {
          "text": "string (prompt with {email} substituted)"
        }
      ]
    }
  ],
  "inferenceConfig": {
    "max_new_tokens": 10,
    "temperature": 0.0
  }
}
```

**Bedrock Response**:
```json
{
  "output": {
    "message": {
      "content": [
        {
          "text": "MATCH,YES" // or "NOMATCH,NO", etc.
        }
      ]
    }
  }
}
```

**Parsed Bedrock Response**:
- First part: `MATCH` or `NOMATCH` (email verification)
- Second part: `YES` or `NO` (credits depleted)
- Examples: `MATCH,YES`, `MATCH,NO`, `NOMATCH,YES`, `NOMATCH,NO`

### S3 Object Models

**Screenshot Object**:
- **Key**: `screenshots/{timestamp}-{sanitized_email}[-deny].png`
- **ContentType**: `image/png`
- **Metadata**:
  - `email`: Original email address
  - `upload_timestamp`: ISO format timestamp
- **Lifecycle**: 90-day expiration

**Frontend Object**:
- **Keys**: `index.html`, `styles.css`, `app.js`, `config.js`
- **ContentType**: `text/html`, `text/css`, `application/javascript`
- **CacheControl**: 
  - HTML/config.js: `max-age=300` (5 minutes)
  - CSS/JS: `max-age=86400` (24 hours)

### Parameter Store Models

**API Key Parameter**:
- **Name**: `/kiro/kiro-user-management-api/api-key`
- **Type**: String (Advanced tier)
- **Value**: 32-character alphanumeric string

**Bedrock Prompt Parameter**:
- **Name**: `/kiro/kiro-user-management-api/bedrock-prompt`
- **Type**: String
- **Value**: Multi-line prompt template with {email} placeholder

**Kiro Pro Group ID Parameter**:
- **Name**: `/kiro/kiro-user-management-api/kiro-pro-group-id`
- **Type**: String
- **Value**: Identity Center group ID (or "PLACEHOLDER_GROUP_ID" initially)

**API Endpoint Parameter**:
- **Name**: `/kiro/kiro-user-management-frontend/api-endpoint`
- **Type**: String
- **Value**: API Gateway endpoint URL

## Correctness Properties


*A property is a characteristic or behavior that should hold true across all valid executions of a system—essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Core Application Properties

**Property 1: Input Validation Completeness**  
*For any* API request (create-user or check-credits), if required fields are missing, the system should return a 400 Bad Request status code with an error message indicating which fields are missing.  
**Validates: Requirements 1.1, 3.1, 9.6**

**Property 2: Screenshot Storage Consistency**  
*For any* processed screenshot, the system should store it in S3 under the screenshots/ prefix with a filename matching the pattern `{timestamp}-{sanitized_email}[-deny].png`, where the -deny suffix is present if and only if the request was denied (email mismatch or credits available).  
**Validates: Requirements 1.7, 5.1, 5.2, 5.3**

**Property 3: Screenshot Metadata Completeness**  
*For any* screenshot stored in S3, the object should have ContentType set to "image/png" and metadata containing both the original email address and upload timestamp in ISO format.  
**Validates: Requirements 5.8, 5.9**

**Property 4: Email Sanitization Correctness**  
*For any* email address, the sanitized version used in S3 keys should replace @ with _at_, . with _, + with _plus_, and remove all characters except alphanumerics, underscores, and hyphens.  
**Validates: Requirements 5.6, 5.7**

**Property 5: Base64 Encoding Round Trip**  
*For any* valid image file, encoding it to base64 (without data URL prefix) and then decoding should produce the original image data.  
**Validates: Requirements 5.5, 9.7**

**Property 6: Duplicate User Check**  
*For any* user creation request, the system should query Identity Center to check if a user with the same email already exists before attempting to create a new user.  
**Validates: Requirements 2.1**

**Property 7: Lambda Invocation Pattern**  
*For any* CheckCreditsFunction invocation that needs to add a user to Kiro Pro, the system should invoke UserManagementFunction with InvocationType "RequestResponse", and if an existing user ID is available, should include it in the existing_user_id parameter.  
**Validates: Requirements 2.1.1, 2.1.2, 2.1.3**

**Property 8: Lambda Response Parsing**  
*For any* successful Lambda invocation response, the system should parse the response payload as JSON and extract the user_id field; for any failed invocation, the system should return an error response containing the failure reason.  
**Validates: Requirements 2.1.5, 2.1.6**

**Property 9: Admin User Group Membership**  
*For any* user created through the admin endpoint (/create-user), the system should automatically add them to the Kiro Pro group and return a response containing the user_id.  
**Validates: Requirements 3.3, 3.4**

**Property 10: Group Existence Check**  
*For any* operation that adds a user to Kiro Pro group, the system should first check if the group exists, create it if it doesn't (with display name "Kiro Pro"), and store the group ID in Parameter Store.  
**Validates: Requirements 4.1, 4.2, 4.3**

**Property 11: Group Operation Verification**  
*For any* add-user-to-group operation, the system should verify the operation succeeded before returning a success response.  
**Validates: Requirements 4.4**

**Property 12: Error Response Format**  
*For any* error condition, the system should return a JSON response with an error message and appropriate HTTP status code: 400 for validation errors, 403 for authentication errors, 500 for internal errors.  
**Validates: Requirements 15.2, 15.3, 15.4, 15.5**

**Property 13: Error Logging with Context**  
*For any* error that occurs in a Lambda function, the system should log the error to CloudWatch with full context including the request ID for traceability.  
**Validates: Requirements 15.1, 15.6**

**Property 14: Successful Provisioning Response**  
*For any* successful user provisioning (either admin or credit-based), the system should return a response containing the user_id, email, and group name.  
**Validates: Requirements 1.6**

### Frontend Properties

**Property 15: API Key Session Persistence**  
*For any* API key entered in the web interface, the system should store it in browser sessionStorage and retrieve it on page load if present.  
**Validates: Requirements 9.2**

**Property 16: API Key Visibility Toggle**  
*For any* toggle action on the API key input, the system should switch the input type between "password" and "text", and update the toggle icon accordingly.  
**Validates: Requirements 9.3**

**Property 17: Image Preview Display**  
*For any* image file selected in the file upload input, the system should display a preview of the image before form submission.  
**Validates: Requirements 9.4**

**Property 18: Form Submission Loading State**  
*For any* API request initiated from the form, the system should disable the submit button and display a loading indicator until the request completes (success or failure).  
**Validates: Requirements 9.8**

**Property 19: Response-Based Message Display**  
*For any* successful API response, the system should display a message that corresponds to the response data: success message if already_in_kiro_pro is true, email verification failed if email_match is false, credits available if credits_used_up is false, upgrade successful if user_added_to_kiro_pro is true, or upgrade failed otherwise.  
**Validates: Requirements 9.11**

**Property 20: Form Reset on Success**  
*For any* successful upgrade response (user_added_to_kiro_pro is true), the system should reset the form fields and clear the image preview.  
**Validates: Requirements 9.12**

### Example Test Cases

These are specific scenarios that should be tested with concrete examples rather than property-based testing:

**Example 1: Already in Kiro Pro**  
Given a user who already exists in Identity Center and is already in the Kiro Pro group, when they submit a credit check request, the system should return early with a message "You are already on the Kiro Pro plan" without analyzing the screenshot.  
**Validates: Requirements 2.3**

**Example 2: Existing User Not in Group**  
Given a user who exists in Identity Center but is not in the Kiro Pro group, when they submit a valid credit check request with depleted credits, the system should add them to the group without creating a new user.  
**Validates: Requirements 2.4, 2.1.4**

**Example 3: Credits Not Depleted**  
Given a screenshot showing available credits, when a user submits it, the system should reject the request with a message indicating credits are still available.  
**Validates: Requirements 1.5**

**Example 4: Email Mismatch**  
Given a screenshot showing a different email address than the one submitted, when a user submits it, the system should reject the request with an email verification failed message.  
**Validates: Requirements 1.4 (negative case)**

**Example 5: Admin User Creation**  
Given valid admin credentials and user details, when an admin calls the /create-user endpoint, the system should create the user and add them to Kiro Pro without requiring screenshot verification.  
**Validates: Requirements 3.2**

**Example 6: Missing API Key**  
Given a form submission without an API key entered, when the user clicks submit, the system should display an alert and focus the API key input field.  
**Validates: Requirements 9.5**

**Example 7: Authentication Failure (403)**  
Given an invalid API key, when the user submits a request, the system should display an authentication failed message with instructions to retrieve the API key from Parameter Store.  
**Validates: Requirements 9.9**

**Example 8: Rate Limit Exceeded (429)**  
Given too many requests in a short time, when the user submits another request, the system should display a rate limit exceeded message.  
**Validates: Requirements 9.10**

**Example 9: Network Error**  
Given a network connectivity issue, when the user submits a request, the system should display a connection error message with troubleshooting guidance.  
**Validates: Requirements 9.13**

**Example 10: API Key Authentication (API Gateway)**  
Given a request without the x-api-key header, when it reaches API Gateway, the system should return a 403 Forbidden response.  
**Validates: Requirements 6.1, 6.2**

**Example 11: Group Creation**  
Given the Kiro Pro group does not exist in Identity Center, when the system needs to add a user to the group, it should create the group with display name "Kiro Pro" first.  
**Validates: Requirements 4.2**

**Example 12: Credits Depleted and Email Match**  
Given a screenshot showing depleted credits with a matching email address, when a new user submits it, the system should create the user in Identity Center and add them to the Kiro Pro group.  
**Validates: Requirements 1.4**

## Error Handling

### Error Categories

**1. Validation Errors (400 Bad Request)**
- Missing required fields (email, image, name)
- Invalid email format
- Invalid base64 image data
- Empty or whitespace-only fields

**Response Format**:
```json
{
  "message": "Missing required field: email"
}
```

**2. Authentication Errors (403 Forbidden)**
- Missing x-api-key header
- Invalid API key
- API key not found in usage plan

**Response Format**:
```json
{
  "message": "Forbidden"
}
```

**3. Rate Limiting Errors (429 Too Many Requests)**
- Exceeded rate limit (1 req/sec)
- Exceeded burst limit (5 requests)
- Exceeded daily quota (10,000 requests)

**Response Format**:
```json
{
  "message": "Too Many Requests"
}
```

**4. Business Logic Errors (200 OK with error details)**
- Email verification failed (screenshot email doesn't match)
- Credits still available (not depleted)
- User already exists (duplicate)
- Upgrade failed (user creation or group addition failed)

**Response Format**:
```json
{
  "email": "user@example.com",
  "email_match": false,
  "credits_used_up": true,
  "user_added_to_kiro_pro": false,
  "message": "Email verification failed. The email in the screenshot does not match..."
}
```

**5. Internal Server Errors (500 Internal Server Error)**
- Identity Center API failures
- Bedrock API failures
- S3 upload failures
- Lambda invocation failures
- Parameter Store read failures
- Unexpected exceptions

**Response Format**:
```json
{
  "message": "Internal server error: <error details>"
}
```

### Error Handling Strategies

**Lambda Functions**:
- Try-catch blocks around all external service calls
- Detailed error logging with context (request ID, user email, operation)
- Graceful degradation (e.g., continue even if S3 upload fails)
- Return structured error responses with appropriate status codes

**Frontend**:
- Catch network errors (fetch failures)
- Handle HTTP error status codes (403, 429, 400, 500)
- Display user-friendly error messages
- Provide troubleshooting guidance for common errors
- Maintain UI state (re-enable buttons, hide loaders)

**API Gateway**:
- Built-in authentication error handling (403 for invalid API key)
- Built-in rate limiting error handling (429 for exceeded limits)
- CORS error responses for OPTIONS requests

**CloudFormation**:
- Stack rollback on deployment failures
- Detailed error messages in CloudFormation events
- Validation of parameters (minimum length, format)

### Retry and Recovery

**Transient Failures**:
- Frontend: User can retry by resubmitting the form
- Lambda: No automatic retries (synchronous invocation from API Gateway)
- Bedrock: Single attempt (no retries due to cost and latency)

**Permanent Failures**:
- Invalid API key: User must obtain correct key from Parameter Store
- Rate limit exceeded: User must wait before retrying
- Identity Center errors: May require manual intervention or stack redeployment
- Bedrock errors: May require checking Bedrock service availability in us-west-2

**Data Consistency**:
- Screenshot storage failures are logged but don't block user provisioning
- Group creation is idempotent (checks existence first)
- User creation checks for duplicates before attempting creation
- Group membership addition is idempotent (Identity Center handles duplicates)

## Testing Strategy

### Dual Testing Approach

The testing strategy employs both unit tests and property-based tests as complementary approaches:

**Unit Tests**: Verify specific examples, edge cases, and error conditions
- Specific scenarios (Example 1-12 above)
- Edge cases (empty strings, special characters, boundary values)
- Error conditions (missing fields, invalid data, service failures)
- Integration points (API Gateway, Lambda invocations, external services)

**Property-Based Tests**: Verify universal properties across all inputs
- Properties 1-20 above
- Generate random valid inputs to test properties hold
- Minimum 100 iterations per property test
- Each test tagged with feature name and property number

### Property-Based Testing Configuration

**Framework**: Use a property-based testing library appropriate for the language:
- Python: `hypothesis` for Lambda function testing
- JavaScript: `fast-check` for frontend testing

**Test Configuration**:
- Minimum 100 iterations per property test
- Random seed for reproducibility
- Shrinking enabled to find minimal failing examples

**Test Tagging**:
Each property test must include a comment tag:
```python
# Feature: kiro-user-management-api, Property 1: Input Validation Completeness
```

### Unit Testing Focus

Unit tests should focus on:
1. **Specific Examples**: Concrete scenarios that demonstrate correct behavior (Examples 1-12)
2. **Edge Cases**: Boundary conditions, special characters, empty values, maximum lengths
3. **Error Conditions**: Service failures, network errors, invalid responses
4. **Integration Points**: API Gateway integration, Lambda cross-invocation, Bedrock responses

Avoid writing too many unit tests for scenarios that property tests already cover. Property tests handle comprehensive input coverage through randomization.

### Testing Layers

**1. Lambda Function Unit Tests**
- Test individual functions (create_user, check_credits, etc.)
- Mock external services (Identity Center, Bedrock, S3)
- Test error handling and edge cases
- Test response formatting

**2. Lambda Function Property Tests**
- Test properties 1-14 with random inputs
- Generate random user data, emails, images
- Verify invariants hold across all inputs

**3. Frontend Unit Tests**
- Test UI interactions (file upload, form submission, API key toggle)
- Test error message display
- Test form validation
- Mock API responses

**4. Frontend Property Tests**
- Test properties 15-20 with random inputs
- Generate random API responses
- Verify UI state consistency

**5. Integration Tests**
- Test API Gateway → Lambda integration
- Test Lambda → Lambda invocation
- Test Lambda → Identity Center integration
- Test Lambda → Bedrock integration
- Test Lambda → S3 integration
- Use mocked services where possible

**6. End-to-End Tests**
- Test complete user flows (credit check, admin creation)
- Test with real AWS services in test environment
- Verify CloudFormation deployment
- Verify frontend deployment and CloudFront distribution

### Test Data Generation

**For Property Tests**:
- Random email addresses (valid format)
- Random names (various lengths, special characters)
- Random base64 image data
- Random API responses (all possible combinations)
- Random error conditions

**For Unit Tests**:
- Specific test cases from Examples 1-12
- Edge cases: empty strings, very long strings, special characters
- Boundary values: minimum/maximum lengths
- Invalid data: malformed emails, invalid base64, missing fields

### Continuous Testing

**Pre-Deployment**:
- Run all unit tests and property tests
- Run integration tests with mocked services
- Verify CloudFormation template syntax

**Post-Deployment**:
- Run end-to-end tests against deployed stack
- Verify API endpoints are accessible
- Verify CloudFront distribution serves frontend
- Run test_api.py script to verify API functionality

**Monitoring**:
- CloudWatch alarms for Lambda errors
- CloudWatch alarms for API Gateway 4xx/5xx errors
- CloudWatch alarms for rate limit exceeded
- S3 bucket monitoring for screenshot storage

## Implementation Notes

### Technology Choices

**Why Pure CloudFormation (No SAM CLI)**:
- Simpler deployment (no additional tools required)
- Inline Lambda code keeps everything in one file
- Easier to understand and maintain
- No build process or packaging required

**Why Vanilla JavaScript (No Frameworks)**:
- No build process or bundling required
- Faster page load (no framework overhead)
- Simpler deployment (just upload files)
- Easier to understand and modify

**Why Inline Lambda Code**:
- Single source of truth (CloudFormation template)
- No separate deployment artifacts
- Easier to version control
- Simpler CI/CD pipeline

**Why Python 3.12**:
- Native AWS SDK (boto3) support
- Simple syntax for Lambda functions
- Good error handling with try-except
- Fast cold start times

### Security Considerations

**API Key Management**:
- API keys are immutable in API Gateway (require stack recreation to change)
- Stored in Parameter Store (not SecureString, but reference only)
- Never logged or exposed in responses
- Users enter their own key in web interface (not embedded in frontend)

**IAM Roles**:
- Least privilege permissions for each Lambda function
- Separate roles for UserManagement and CheckCredits
- No wildcard permissions except where required by service (e.g., sso-admin:*)

**S3 Security**:
- No public bucket access
- CloudFront uses Origin Access Control (OAC)
- Screenshots stored with 90-day lifecycle
- Bucket policy restricts access to CloudFront only

**HTTPS Only**:
- CloudFront enforces redirect-to-https
- API Gateway uses HTTPS endpoints
- No HTTP access allowed

**CORS Configuration**:
- Allow all origins (*) for API Gateway (public API)
- Specific headers allowed (Content-Type, X-Api-Key, etc.)
- Only POST and OPTIONS methods allowed

### Performance Considerations

**Lambda Timeouts**:
- UserManagementFunction: 30 seconds (sufficient for Identity Center operations)
- CheckCreditsFunction: 60 seconds (allows time for Bedrock analysis)

**API Gateway Rate Limiting**:
- 1 request/second steady rate (prevents abuse)
- 5 request burst (allows occasional spikes)
- 10,000 requests/day quota (reasonable for expected usage)

**CloudFront Caching**:
- HTML/config.js: 5 minutes (allows quick updates)
- CSS/JS: 24 hours (static assets change infrequently)
- Cache invalidation on deployment (ensures users get latest version)

**Bedrock Configuration**:
- max_new_tokens: 10 (minimal response, faster processing)
- temperature: 0.0 (deterministic responses, no randomness)
- Model: Nova Pro (balance of speed and accuracy)

### Operational Considerations

**Monitoring**:
- CloudWatch Logs for all Lambda functions
- API Gateway access logs
- CloudFront access logs
- S3 bucket metrics

**Debugging**:
- Request IDs in all log messages
- Detailed error logging with context
- Screenshot storage for audit trail
- Parameter Store for configuration

**Maintenance**:
- Update Bedrock prompt via Parameter Store (no redeployment)
- Rotate API key by recreating stack (immutable keys)
- Update Lambda code by updating CloudFormation template
- Update frontend by running upload-frontend.sh

**Cost Optimization**:
- Lambda: Pay per invocation (no idle costs)
- API Gateway: Pay per request
- S3: 90-day lifecycle reduces storage costs
- CloudFront: Free tier covers most usage
- Bedrock: Pay per token (minimal with max_new_tokens=10)

### Deployment Workflow

**Initial Deployment**:
1. Run `deploy-backend.sh` (creates Identity Center if needed, generates API key)
2. Run `deploy-frontend.sh` (creates CloudFront distribution)
3. Run `upload-frontend.sh` (uploads files, invalidates cache)
4. Test with `test_api.py`

**Updates**:
1. Modify CloudFormation templates or Lambda code
2. Run `deploy-backend.sh -f` (force update, skip prompts)
3. Run `deploy-frontend.sh -f` (force update)
4. Run `upload-frontend.sh` (upload new files)
5. Test with `test_api.py`

**Bedrock Prompt Updates**:
1. Run `update-bedrock-prompt.sh` with new prompt
2. No redeployment required (Lambda reads from Parameter Store)

**API Key Rotation**:
1. Delete backend stack
2. Run `deploy-backend.sh` with new API key
3. Update frontend users with new key

### Constraints and Limitations

**AWS Service Limits**:
- Only one IAM Identity Center instance per region
- API Gateway API keys are immutable
- S3 bucket names must be globally unique
- Bedrock must be enabled in us-west-2 region

**Application Limits**:
- Screenshot size limited by API Gateway payload size (10 MB)
- Lambda execution time limited by timeout (30s/60s)
- Rate limiting prevents high-volume usage
- No authentication beyond API key (no user-specific permissions)

**Known Issues**:
- AI-generated code requires security review before production use
- API key rotation requires stack deletion and recreation
- No automated testing of Bedrock responses (external service)
- No user management UI (must use AWS Console for Identity Center)

### Future Enhancements

**Potential Improvements**:
- Add user authentication (Cognito) instead of shared API key
- Add admin UI for user management
- Add webhook notifications for successful upgrades
- Add email notifications to users
- Add metrics dashboard for usage tracking
- Add automated Bedrock prompt testing
- Add support for multiple image formats (JPEG, WebP)
- Add image compression before upload
- Add batch user creation endpoint
- Add user removal/downgrade endpoint

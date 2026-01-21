# Kiro User Management - Complete Architecture

## ⚠️ Disclaimer

**This code was generated using AI coding tools and is provided as-is for reference purposes.**

Use this code at your own risk. Before deploying to production:
- Conduct thorough security reviews and penetration testing
- Review all IAM permissions and API configurations
- Test extensively in non-production environments
- Ensure compliance with your organization's security policies
- Implement proper monitoring, logging, and backup procedures

The authors are not responsible for any issues or security vulnerabilities that may arise from using this code.

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Interface Layer                        │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Web Browser  ──HTTPS──>  CloudFront Distribution                   │
│                                    │                                │
│                                    │ (Origin Access Control)        │
│                                    ↓                                │
│                           S3 Bucket (frontend/)                     │
│                           ├── index.html                            │
│                           ├── styles.css                            │
│                           ├── app.js                                │
│                           └── config.js (API credentials)           │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ HTTPS + API Key
                                    ↓
┌─────────────────────────────────────────────────────────────────────┐
│                         API Gateway Layer                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  API Gateway (REST API)                                             │
│  ├── POST /create-user      (API Key Required)                      │
│  ├── POST /check-credits    (API Key Required)                      │
│  ├── OPTIONS /create-user   (CORS)                                  │
│  └── OPTIONS /check-credits (CORS)                                  │
│                                                                     │
│  Rate Limiting: 1 req/sec, 5 burst, 10K/day quota                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
                   │                            │
                   │                            │
                   ↓                            ↓
┌──────────────────────────────┐  ┌───────────────────────────────────┐
│   UserManagementFunction     │  │   CheckCreditsFunction            │
│   (Lambda - Python 3.12)     │  │   (Lambda - Python 3.12)          │
├──────────────────────────────┤  ├───────────────────────────────────┤
│                              │  │                                   │
│ • Validate input             │  │ • Validate input                  │
│ • Check for duplicates       │  │ • Decode base64 image             │
│ • Create user in Identity    │  │ • Invoke Bedrock (Nova Pro)       │
│   Center                     │  │ • Analyze credit status           │
│ • Get/create "Kiro Pro"      │  │ • Save screenshot to S3           │
│   group                      │  │ • If depleted: invoke             │
│ • Add user to group          │  │   UserManagementFunction ─────────┤
│ • Return user details        │  │ • Return analysis result          │
│                              │  │                                   │
└──────────────────────────────┘  └───────────────────────────────────┘
         │                                    │           │
         │                                    │           │
         ↓                                    ↓           ↓
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Services Layer                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  IAM Identity Center          S3 Bucket                 Bedrock     │
│  ├── Identity Store           ├── screenshots/         (us-west-2)  │
│  │   └── Users                │   └── {timestamp}-     Nova Pro     │
│  └── Groups                   │       {email}.png      (Image       │
│      └── "Kiro Pro"           │                        Analysis)    │
│                               └── frontend/                         │
│                                   └── (web files)                   │
│                                                                     │
│  Parameter Store                                                    │
│  ├── /kiro/kiro-user-management-api/api-key                         │
│  ├── /kiro/kiro-user-management-api/kiro-pro-group-id               │
│  ├── /kiro/kiro-user-management-frontend/api-endpoint               │
│  └── /kiro/kiro-user-management-frontend/api-key                    │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### Create User Flow

```
1. User fills form in web UI
   ↓
2. Browser sends POST to CloudFront
   ↓
3. CloudFront forwards to API Gateway
   ↓
4. API Gateway validates API key
   ↓
5. Lambda (UserManagementFunction) invoked
   ↓
6. Lambda checks for duplicate user
   ↓
7. Lambda creates user in Identity Center
   ↓
8. Lambda adds user to "Kiro Pro" group
   ↓
9. Response returned to browser
   ↓
10. Success message displayed
```

### Check Credits Flow

```
1. User uploads screenshot in web UI
   ↓
2. Browser encodes image to base64
   ↓
3. Browser sends POST to CloudFront
   ↓
4. CloudFront forwards to API Gateway
   ↓
5. API Gateway validates API key
   ↓
6. Lambda (CheckCreditsFunction) invoked
   ↓
7. Lambda decodes base64 image
   ↓
8. Lambda invokes Bedrock Nova Pro
   ↓
9. Bedrock analyzes screenshot
   ↓
10. Lambda saves screenshot to S3
    ├── If depleted: screenshots/{timestamp}-{email}.png
    └── If available: screenshots/{timestamp}-{email}-deny.png
   ↓
11. If credits depleted:
    ├── Lambda invokes UserManagementFunction
    ├── User added to "Kiro Pro" group
    └── User ID returned
   ↓
12. Response returned to browser
   ↓
13. Result displayed with status
```

## Deployment Architecture

### Backend Stack (kiro-user-management-api)

```
CloudFormation Template (backend-template.yaml)
├── Lambda Functions
│   ├── UserManagementFunction
│   └── CheckCreditsFunction
├── IAM Roles
│   ├── UserManagementLambdaRole
│   └── CheckCreditsLambdaRole
├── API Gateway
│   ├── REST API
│   ├── Resources (/create-user, /check-credits)
│   ├── Methods (POST, OPTIONS)
│   └── Deployment (prod stage)
├── API Key & Usage Plan
│   ├── API Key
│   ├── Usage Plan (rate limits)
│   └── Usage Plan Key
└── Parameter Store
    ├── API Key
    └── Kiro Pro Group ID

Deployed via: ./deploy-backend.sh
```

### Frontend Stack (kiro-user-management-frontend)

```
CloudFormation Template (frontend-template.yaml)
├── CloudFront Distribution
│   ├── Origin: S3 Bucket
│   ├── Origin Access Control (OAC)
│   ├── DefaultRootObject: index.html (serves index.html at root URL)
│   ├── Cache Behaviors
│   └── Custom Error Responses (403/404 → index.html)
├── S3 Bucket Policy
│   └── Allow CloudFront access via OAC (s3:GetObject on bucket/*)
└── Parameter Store
    └── API Endpoint

Deployed via: ./deploy-frontend.sh

Frontend Files (uploaded via ./upload-frontend.sh)
├── index.html (HTML structure)
├── styles.css (styling)
├── app.js (frontend logic with improved error handling)
└── config.js (generated with API endpoint only, users provide API key)
```

## Security Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Security Layers                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. Transport Security                                               │
│     └── HTTPS only (CloudFront + API Gateway)                        │
│                                                                      │
│  2. API Authentication                                               │
│     ├── API Key (x-api-key header)                                   │
│     ├── API Gateway validates key before Lambda invocation           │
│     └── Parameter Store value is for reference only                  │
│                                                                      │
│  3. Rate Limiting                                                    │
│     ├── 1 request/second (steady-state)                              │
│     ├── 5 burst capacity                                             │
│     └── 10,000 requests/day quota                                    │
│                                                                      │
│  4. Origin Access Control                                            │
│     └── CloudFront OAC for S3 access (no public bucket access)       │
│                                                                      │
│  5. IAM Permissions                                                  │
│     ├── Lambda execution roles (least privilege)                     │
│     ├── Identity Center access                                       │
│     ├── Bedrock invoke permissions                                   │
│     └── S3 read/write permissions                                    │
│                                                                      │
│  6. Parameter Store                                                  │
│     └── API key storage for reference (not used by API Gateway)      │
│                                                                      │
│  7. CORS Configuration                                               │
│     └── Controlled cross-origin access                               │
│                                                                      │
│  8. Frontend Error Handling                                          │
│     ├── 403 → "Invalid API key" with helpful message                 │
│     ├── 429 → "Rate limit exceeded"                                  │
│     ├── Network errors → Connection guidance                         │
│     └── HTTP errors → Specific error messages                        │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

## API Key Management

### How API Keys Work

1. **API Gateway API Key** (Primary)
   - Created by CloudFormation `ApiKey` resource
   - Value set via `ApiKeyValue` parameter during deployment
   - This is the ACTUAL key that API Gateway validates
   - Cannot be updated in-place (immutable name)

2. **Parameter Store Value** (Reference Only)
   - Stores a copy of the API key for retrieval
   - NOT used by API Gateway or Lambda for authentication
   - Allows users/scripts to look up the key later
   - Updating this value does NOT change API authentication

### API Key Rotation Process

To rotate the API key:

```bash
# 1. Generate new key
NEW_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# 2. Get Instance ARN
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)

# 3. Delete existing stack (required due to API key name immutability)
aws cloudformation delete-stack --stack-name kiro-user-management-api
aws cloudformation wait stack-delete-complete --stack-name kiro-user-management-api

# 4. Redeploy with new key
./deploy-backend.sh -f "$INSTANCE_ARN" "$NEW_KEY"

# 5. Update frontend
./upload-frontend.sh
```

**Why delete and recreate?** API Gateway API keys have immutable names. Updating the stack with a new key value attempts to create a new key with the same name, which fails. Deleting and recreating is the cleanest approach.

## Infrastructure as Code

### Backend (backend-template.yaml)
- ~1000 lines of CloudFormation
- Inline Lambda code (Python 3.12)
- 2 Lambda functions (UserManagement, CheckCredits)
- 2 IAM roles
- 1 API Gateway
- 2 API resources (/create-user, /check-credits)
- 4 API methods (POST + OPTIONS for each)
- 1 API key
- 1 usage plan (1 req/sec, 5 burst, 10K/day)
- 1 S3 bucket (screenshots with 90-day lifecycle)
- 3 SSM parameters (API key, Bedrock prompt, Kiro Pro group ID)

### Frontend (frontend-template.yaml)
- CloudFront distribution with OAC
- DefaultRootObject: index.html (fixes AccessDenied at root URL)
- S3 bucket policy (CloudFront access via OAC)
- Origin Access Control (secure S3 access)
- Custom error responses (403/404 → index.html for SPA routing)
- Cache behaviors
- 1 SSM parameter (API endpoint only, API key now user-provided)

### Total Resources: ~30 AWS resources

## Monitoring & Observability

```
CloudWatch Logs
├── /aws/lambda/kiro-user-management-api-user-management
└── /aws/lambda/kiro-user-management-api-check-credits

CloudWatch Metrics
├── Lambda Invocations
├── Lambda Duration
├── Lambda Errors
├── API Gateway Requests
├── API Gateway Latency
├── API Gateway 4XX/5XX Errors
├── CloudFront Requests
└── CloudFront Cache Hit Rate

S3 Audit Trail
└── screenshots/ (90-day retention)
    ├── {timestamp}-{email}.png (depleted)
    └── {timestamp}-{email}-deny.png (available)
```

## Scalability

- **Lambda**: Auto-scales to handle concurrent requests
- **API Gateway**: Handles thousands of requests per second
- **CloudFront**: Global edge locations for low latency
- **S3**: Unlimited storage capacity
- **Bedrock**: Managed service with auto-scaling

## High Availability

- **Multi-AZ**: Lambda and API Gateway are multi-AZ by default
- **Global**: CloudFront distributes content globally
- **Durable**: S3 provides 99.999999999% durability
- **Managed**: All services are fully managed by AWS

## Cost Optimization

- **Lambda**: Pay per invocation (free tier: 1M requests/month)
- **API Gateway**: Pay per request (free tier: 1M requests/month)
- **CloudFront**: Pay per data transfer (free tier: 1TB/month)
- **S3**: Pay per storage + requests (free tier: 5GB storage)
- **Bedrock**: Pay per token (Nova Pro provides better accuracy)

**Estimated Monthly Cost**: $0.20 - $20 depending on usage

## Disaster Recovery

- **Backup**: CloudFormation templates in version control
- **Recovery**: Redeploy from templates
- **Data**: S3 screenshots with lifecycle policies
- **Configuration**: Parameter Store for settings
- **RTO**: ~15 minutes (CloudFormation deployment)
- **RPO**: Near-zero (stateless architecture)

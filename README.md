# Kiro User Management API

This project creates a serverless API for managing IAM Identity Center users and automatically upgrading users to Kiro Pro when their free credits are depleted. The system uses AWS Bedrock for screenshot analysis and includes a web frontend for easy access.

## ⚠️ Disclaimer

**This code was generated using AI coding tools and is provided as-is for reference and educational purposes.**

- Use this code at your own risk
- This code has not undergone professional security auditing
- You should run this code through your own security checks, code reviews, and testing before deploying to production
- Ensure compliance with your organization's security policies and best practices
- Review all IAM permissions, API configurations, and data handling practices
- Test thoroughly in a non-production environment first
- The authors and contributors are not responsible for any issues, damages, or security vulnerabilities that may arise from using this code

**Recommended Actions Before Production Use:**
1. Conduct a thorough security review and penetration testing
2. Review and adjust IAM policies to follow least privilege principles
3. Implement additional monitoring and alerting
4. Add comprehensive logging and audit trails
5. Review data retention and privacy policies
6. Ensure compliance with relevant regulations (GDPR, HIPAA, etc.)
7. Implement proper backup and disaster recovery procedures

## Architecture

- **Lambda Functions**: Two Python 3.12 functions (user management and credit checking with inline code)
- **API Gateway**: REST API with API key authentication and rate limiting
- **IAM Identity Center**: User and group management
- **AWS Bedrock**: Nova Pro model for credit screenshot analysis
- **S3**: Screenshot storage for audit trail and frontend hosting
- **CloudFront**: Global CDN for web frontend
- **CloudFormation**: Infrastructure as Code deployment (pure CloudFormation, no SAM CLI)

## Authentication Method

I've chosen **API Key authentication** over JWT tokens for this use case because:

1. **Simplicity**: API keys are easier to implement and manage for service-to-service communication
2. **AWS Native**: API Gateway has built-in API key support with usage plans and throttling
3. **Security**: Combined with HTTPS, API keys provide adequate security for this internal API
4. **Performance**: No token validation overhead on each request

If you need more advanced authentication (user context, expiration, etc.), JWT tokens with AWS Cognito would be a better choice.

## Prerequisites

- AWS CLI configured with appropriate permissions
- Python 3.12+ (for testing scripts)
- IAM Identity Center instance (the script can create one if needed)
- Bedrock access in us-west-2 region (for Nova Pro model)

## Required Permissions

The deployment requires permissions for:
- CloudFormation stack operations
- Lambda function creation and management
- API Gateway setup
- IAM role and policy creation
- SSM Parameter Store access
- IAM Identity Center (SSO Admin and Identity Store) operations
- S3 bucket creation and management
- Bedrock model invocation (Nova Pro in us-west-2)
- CloudFront distribution creation (for frontend)

## Checking Existing Deployments

Before deploying, you can check if the CloudFormation stack already exists and its current state:

### List All CloudFormation Stacks
```bash
# List all stacks in your account
aws cloudformation list-stacks --query 'StackSummaries[*].[StackName,StackStatus]' --output table

# Filter for stacks containing "kiro" in the name
aws cloudformation list-stacks --query 'StackSummaries[?contains(StackName, `kiro`)].[StackName,StackStatus]' --output table
```

### Check Specific Stack Status
```bash
# Check the status of the kiro-user-management-api stack
aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].StackStatus' --output text
```

### Understanding Stack States

**Successful States** (deployment completed successfully):
- `CREATE_COMPLETE` - Stack was created successfully
- `UPDATE_COMPLETE` - Stack was updated successfully

**Failed States** (deployment failed and may need cleanup):
- `CREATE_FAILED` - Stack creation failed
- `ROLLBACK_COMPLETE` - Stack creation failed and was rolled back
- `UPDATE_ROLLBACK_COMPLETE` - Stack update failed and was rolled back
- `UPDATE_ROLLBACK_FAILED` - Stack update and rollback both failed
- `DELETE_FAILED` - Stack deletion failed

**In-Progress States** (deployment is currently running):
- `CREATE_IN_PROGRESS` - Stack is being created
- `UPDATE_IN_PROGRESS` - Stack is being updated
- `DELETE_IN_PROGRESS` - Stack is being deleted

### Get Detailed Stack Information
```bash
# Get comprehensive stack information including outputs
aws cloudformation describe-stacks --stack-name kiro-user-management-api --output table

# Get just the stack outputs (API endpoints, etc.)
aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' --output table
```

### Check Stack Events (for troubleshooting failures)
```bash
# View recent stack events to understand what went wrong
aws cloudformation describe-stack-events --stack-name kiro-user-management-api --query 'StackEvents[0:10].[Timestamp,ResourceType,ResourceStatus,ResourceStatusReason]' --output table
```

**Note**: The enhanced deployment script (`deploy-backend.sh`) automatically checks stack status and will:
- Prompt you to update existing successful stacks
- Prompt you to delete and recreate failed stacks
- Show current stack information if you choose to skip deployment

## Deployment

### Recommended: Automated Deployment with AI Code Review

For the safest deployment experience, use an AI coding assistant like Kiro CLI to automatically review the codebase and deploy:

**Using Kiro CLI or similar AI coding tools:**

```bash
# Open Kiro CLI in this directory and use a prompt like:

"Please thoroughly review the entire codebase for any security vulnerabilities, 
configuration issues, or potential bugs. Check for:
- IAM permission issues or overly permissive policies
- API security configurations and authentication mechanisms
- Input validation and error handling
- CloudFormation template syntax and best practices
- Hardcoded credentials or sensitive data exposure
- CORS and network security configurations

Fix any critical or high-severity issues you find. If there are unresolved 
security concerns or blocking issues, stop and report them - do not proceed 
with deployment.

Once the codebase is verified and any issues are resolved, deploy the 
application by running:
1. ./deploy-backend.sh (for backend API and Lambda functions)
2. ./deploy-frontend.sh (for CloudFront distribution)
3. ./upload-frontend.sh (to upload web files and invalidate cache)

Provide a summary of any issues found and fixed, and confirm successful deployment."
```

**Benefits of AI-assisted deployment:**
- Automated security review before deployment
- Detection of common misconfigurations
- Validation of CloudFormation templates
- Identification of potential runtime issues
- Safer deployment with pre-flight checks

### Manual Deployment

If you prefer manual deployment or have already completed security reviews:

#### Backend Deployment

The backend deployment script provides a fully automated experience:

**Quick Start (Fully Automated)**
```bash
# Run without any parameters - the script will:
# 1. Auto-detect existing IAM Identity Center instances
# 2. Prompt to create an instance if none exists
# 3. Auto-generate a secure 32-character API key
# 4. Store the API key securely in Parameter Store
./deploy-backend.sh

# Force update mode (skip all prompts)
./deploy-backend.sh -f
```

**Advanced Usage**

1. **Force update with no prompts**:
   ```bash
   ./deploy-backend.sh -f
   ```

2. **With specific Identity Center instance**:
   ```bash
   ./deploy-backend.sh arn:aws:sso:::instance/ssoins-1234567890abcdef
   ```

3. **Force update with specific instance**:
   ```bash
   ./deploy-backend.sh -f arn:aws:sso:::instance/ssoins-1234567890abcdef
   ```

4. **With custom API key**:
   ```bash
   ./deploy-backend.sh arn:aws:sso:::instance/ssoins-1234567890abcdef my-custom-api-key
   ```

5. **With specific region**:
   ```bash
   ./deploy-backend.sh arn:aws:sso:::instance/ssoins-1234567890abcdef my-api-key us-west-2
   ```

#### Frontend Deployment

After deploying the backend, deploy the web frontend:

```bash
# Deploy CloudFront distribution and S3 configuration
./deploy-frontend.sh

# Force update mode (skip all prompts)
./deploy-frontend.sh -f

# Upload frontend files to S3 and invalidate CloudFront cache
./upload-frontend.sh
```

The frontend provides a user-friendly interface for:
- Uploading credit usage screenshots
- Automatic verification and Kiro Pro upgrade
- Real-time status feedback

### What the Script Does Automatically

**Identity Center Management**:
- ✅ Detects existing IAM Identity Center instances in your region
- ✅ Prompts to create a new instance if none exists
- ✅ Uses the first available instance if multiple exist

**API Key Management**:
- ✅ Checks Parameter Store for existing API keys
- ✅ Reuses existing keys to avoid conflicts
- ✅ Auto-generates secure 32-character alphanumeric keys when needed
- ✅ Stores keys securely in AWS Systems Manager Parameter Store

**Stack Management**:
- ✅ Detects existing CloudFormation stacks
- ✅ Prompts to update successful stacks or delete failed ones
- ✅ Shows current stack information if you choose to skip deployment

### Manual Deployment (Alternative)

If you prefer manual deployment or need to integrate with CI/CD:

1. **Get your Identity Center Instance ARN** (if not using auto-detection):
   ```bash
   aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text
   ```

2. **Deploy manually**:
   ```bash
   aws cloudformation deploy \
     --template-file backend-template.yaml \
     --stack-name kiro-user-management-api \
     --parameter-overrides \
       IdentityCenterInstanceArn=arn:aws:sso:::instance/ssoins-your-instance-id \
       ApiKeyValue=your-secure-api-key-here \
     --capabilities CAPABILITY_IAM
   ```

### Deployment Output

After successful deployment, the script displays:
- 📋 **Stack outputs**: API endpoints and resource information
- 🔑 **API credentials**: Your API key and Parameter Store location
- 📝 **Next steps**: Instructions for testing and usage

Example output:
```
=== API CREDENTIALS ===
API Key: AbC123XyZ789SecureKey32Characters
Parameter Store Location: /kiro/kiro-user-management-api/api-key

To retrieve your API key later:
aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption --query 'Parameter.Value' --output text
```

## API Usage

The API provides two main endpoints:

### 1. Check Credits Endpoint (Primary User Flow)

**POST** `/check-credits`

This is the main endpoint users interact with through the web frontend. It analyzes credit usage screenshots and automatically upgrades users to Kiro Pro when credits are depleted.

**Headers**:
- `Content-Type: application/json`
- `x-api-key: <your-api-key>`

**Request Body**:
```json
{
  "image": "<base64-encoded-png>",
  "email": "user@example.com",
  "firstName": "John",           // Optional
  "lastName": "Doe",             // Optional
  "image_name": "screenshot.png" // Optional
}
```

**Response Scenarios**:

**Already in Kiro Pro** (200 OK):
```json
{
  "email": "user@example.com",
  "already_in_kiro_pro": true,
  "message": "You are already on the Kiro Pro plan."
}
```

**Email Mismatch** (200 OK):
```json
{
  "email": "user@example.com",
  "email_match": false,
  "message": "Email verification failed. The email in the screenshot does not match."
}
```

**Credits Still Available** (200 OK):
```json
{
  "credits_used_up": false,
  "s3_uri": "s3://bucket/screenshots/20260121-123456-abcd.png",
  "timestamp": "2026-01-21T12:34:56.789012",
  "email": "user@example.com",
  "user_added_to_kiro_pro": false,
  "message": "Credits are still available. User not added to Kiro Pro group."
}
```

**Credits Depleted - Upgrade Successful** (200 OK):
```json
{
  "credits_used_up": true,
  "s3_uri": "s3://bucket/screenshots/20260121-123456-abcd.png",
  "timestamp": "2026-01-21T12:34:56.789012",
  "email": "user@example.com",
  "user_added_to_kiro_pro": true,
  "user_id": "1234567890abcdef",
  "message": "Credits depleted. User successfully added to Kiro Pro group."
}
```

**Credits Depleted - Upgrade Failed** (200 OK):
```json
{
  "credits_used_up": true,
  "s3_uri": "s3://bucket/screenshots/20260121-123456-abcd.png",
  "timestamp": "2026-01-21T12:34:56.789012",
  "email": "user@example.com",
  "user_added_to_kiro_pro": false,
  "error": "User creation failed",
  "message": "Credits depleted, but failed to add user to Kiro Pro group."
}
```

### 2. Create User Endpoint (Admin Use)

**POST** `/create-user`

This endpoint is for administrative user creation without credit verification.

**Headers**:
- `Content-Type: application/json`
- `x-api-key: <your-api-key>`

**Request Body**:
```json
{
  "name": "John Doe",
  "email": "john.doe@example.com",
  "firstName": "John",    // Optional - extracted from name if not provided
  "lastName": "Doe"       // Optional - extracted from name if not provided
}
```

**Response** (200 OK):
```json
{
  "message": "User created successfully",
  "user_id": "1234567890abcdef",
  "email": "john.doe@example.com",
  "group": "Kiro Pro"
}
```

**Error Response** (500 - Duplicate User):
```json
{
  "message": "User with email john.doe@example.com already exists"
}
```

## Testing

### Automated Testing (Recommended)

The test script can automatically retrieve the API endpoint and key from AWS:

```bash
# Install required Python libraries
pip3 install requests boto3

# Run automated tests (no parameters needed)
python3 test_api.py
```

The script will:
1. Retrieve the API endpoint from CloudFormation stack outputs
2. Retrieve the API key from Parameter Store
3. Create a unique test user
4. Verify the user exists in IAM Identity Center
5. Test duplicate user handling

### Manual Testing

You can also provide the endpoint and key manually:

```bash
# Get the API key
API_KEY=$(aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption --query 'Parameter.Value' --output text)

# Get the API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' --output text)

# Run tests with explicit parameters
python3 test_api.py $API_ENDPOINT $API_KEY
```

### Stack Verification

Check if the stack is deployed and the API is accessible:

```bash
python3 check_stack.py
```

This script verifies:
- CloudFormation stack status
- API key exists in Parameter Store
- API endpoint is accessible

## Manual Testing with curl

```bash
# Get the API key
API_KEY=$(aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption --query 'Parameter.Value' --output text)

# Get the API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' --output text)

# Test the API
curl -X POST $API_ENDPOINT/create-user \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{
    "name": "Test User",
    "email": "test@example.com"
  }'
```

## Features

- ✅ Analyzes credit usage screenshots with AWS Bedrock Nova Pro
- ✅ Automatically upgrades users to Kiro Pro when credits are depleted
- ✅ Checks if user already has Kiro Pro access before processing
- ✅ Verifies email address matches screenshot
- ✅ Creates IAM Identity Center users
- ✅ Automatically adds users to "Kiro Pro" group
- ✅ Creates the group if it doesn't exist
- ✅ Prevents duplicate users (checks by email)
- ✅ Stores screenshots in S3 for audit trail (90-day retention)
- ✅ Web frontend with CloudFront distribution
- ✅ API key authentication with usage plans
- ✅ Rate limiting (1 req/sec steady, 5 burst, 10K/day quota)
- ✅ Proper error handling and logging
- ✅ CORS support for web applications

## Error Handling

The API handles various error scenarios with user-friendly messages:
- Missing required fields (400): `"Missing required field: <field>"`
- Duplicate users (500): `"User with email <email> already exists"`
- Identity Center configuration issues (500)
- Invalid JSON (400): `"Invalid JSON in request body"`
- Authentication failures (403)

## Security Considerations

1. **API Key Security**: 
   - API key is auto-generated as a secure 32-character alphanumeric string
   - Stored as a SecureString in AWS Systems Manager Parameter Store
   - Never logged in CloudFormation outputs or CloudWatch logs
   - Retrieve securely using: `aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption`
   - Existing keys are automatically reused to prevent conflicts
   - **Important**: The Parameter Store value is for reference only - API Gateway uses the key set during CloudFormation deployment

### API Key Rotation

To rotate the API key (recommended periodically for security):

```bash
# Step 1: Generate a new secure API key
NEW_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
echo "New API Key: $NEW_API_KEY"

# Step 2: Get your Identity Center instance ARN
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
echo "Instance ARN: $INSTANCE_ARN"

# Step 3: Delete the existing stack (required because API key names cannot be updated)
aws cloudformation delete-stack --stack-name kiro-user-management-api
aws cloudformation wait stack-delete-complete --stack-name kiro-user-management-api

# Step 4: Redeploy with the new API key
./deploy-backend.sh -f "$INSTANCE_ARN" "$NEW_API_KEY"

# Step 5: Update frontend to use new API endpoint (if endpoint changed)
./upload-frontend.sh
```

**Why delete and recreate?** API Gateway API keys have immutable names. When you try to update the stack with a new API key value, CloudFormation attempts to create a new API key with the same name, which fails. Deleting and recreating the stack is the cleanest approach.

**Note**: After rotation, distribute the new API key to all users/systems that need access to the API.

2. **HTTPS Only**: The API should only be accessed over HTTPS
3. **Rate Limiting**: Usage plans include throttling (1 req/sec steady, 5 burst, 10K/day quota)
4. **Least Privilege**: Lambda roles have minimal required permissions
5. **Input Validation**: All inputs are validated before processing
6. **Email Verification**: Screenshots are verified to match the provided email address
7. **Audit Trail**: All screenshots are stored in S3 with 90-day retention
8. **CloudFront OAC**: Frontend uses Origin Access Control for secure S3 access

## Monitoring

- CloudWatch Logs: Lambda function logs all operations
- API Gateway Metrics: Request count, latency, errors
- Usage Plans: Track API key usage and enforce limits

## Cleanup

To remove all resources:

```bash
# Delete backend stack
aws cloudformation delete-stack --stack-name kiro-user-management-api

# Delete frontend stack
aws cloudformation delete-stack --stack-name kiro-user-management-frontend
```

Note: The S3 bucket with screenshots may need to be emptied before the stack can be deleted.

## Troubleshooting

1. **Identity Center Instance**: The script will auto-detect existing instances or prompt to create one
2. **Permissions**: Ensure your AWS credentials have the required permissions
3. **Group Creation**: The Lambda will create the "Kiro Pro" group if it doesn't exist
4. **API Key**: Auto-generated keys are always 32 characters (exceeds 20-character minimum)
5. **Stack States**: The script handles failed stacks by prompting for deletion and recreation
6. **Existing Deployments**: Use `aws cloudformation list-stacks` to check current stack status

## Cost Considerations

- **Lambda**: Pay per request (free tier: 1M requests/month)
- **API Gateway**: Pay per API call (free tier: 1M requests/month)
- **Bedrock Nova Pro**: Pay per token (~$0.0008 per image analysis)
- **S3**: Pay per storage + requests (free tier: 5GB storage)
- **CloudFront**: Pay per data transfer (free tier: 1TB/month)
- **Identity Center**: No additional charges for user/group management
- **CloudWatch**: Minimal logging costs

**Estimated Monthly Cost**: $1 - $50 depending on usage (primarily Bedrock costs)

This setup is designed to be cost-effective for moderate usage patterns.

## Project Structure

```
├── backend-template.yaml      # Backend CloudFormation template with inline Lambda code
├── frontend-template.yaml     # Frontend CloudFormation template (CloudFront/S3)
├── deploy-backend.sh          # Backend deployment script with force update option
├── deploy-frontend.sh         # Frontend deployment script
├── upload-frontend.sh         # Upload frontend files to S3
├── update-bedrock-prompt.sh   # Update Bedrock prompt in Parameter Store
├── test_api.py                # API testing script (auto-retrieves credentials)
├── check_stack.py             # Stack verification script
├── check_credits.py           # Credit checking script (also deployed as Lambda)
├── test_check_credits.py      # Test script for credit checking
├── frontend/                  # Web frontend files
│   ├── index.html             # Main HTML page
│   ├── styles.css             # CSS styles
│   ├── app.js                 # Frontend JavaScript logic
│   └── config.js              # API configuration (auto-generated)
├── README.md                  # This file
├── ARCHITECTURE.md            # Complete architecture documentation
├── CHANGELOG.md               # Change history
└── archive/                   # Historical documentation files
```

The Lambda function code is embedded directly in the CloudFormation template, making this a completely self-contained deployment with no external dependencies.

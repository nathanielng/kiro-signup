# Kiro User Management - Deployment Guide

## ⚠️ Disclaimer

**This code was generated using AI coding tools and is provided as-is for reference purposes.**

Use this code at your own risk. Before deploying:
- Run security checks and code reviews
- Test in non-production environments first
- Review IAM permissions and API configurations
- Ensure compliance with your organization's policies
- Implement proper monitoring and backup procedures

The authors are not responsible for any issues or security vulnerabilities.

---

Quick reference guide for deploying and managing the Kiro User Management system.

## Prerequisites

### Required Tools

**AWS CLI** (version 2.x recommended)
```bash
# Check version
aws --version

# Install/upgrade: https://aws.amazon.com/cli/
```

**Python 3.9+** (for test scripts)
```bash
# Check version
python3 --version

# Install dependencies
pip3 install requests boto3
```

**Bash Shell** (macOS/Linux native, Windows: Git Bash or WSL)

### AWS Account Requirements

**IAM Identity Center**
- Must have an IAM Identity Center instance (script can create one if needed)
- Instance must be in the same region as deployment

**AWS Bedrock Access**
- Bedrock must be enabled in us-west-2 region
- Nova Pro model access required
- Enable via AWS Console: Bedrock → Model access → Request access

**AWS Permissions**
The deploying user/role needs:
- CloudFormation: Full stack operations
- Lambda: Create/update functions
- API Gateway: Create/configure REST APIs
- IAM: Create roles and policies (`CAPABILITY_IAM`)
- S3: Create/manage buckets
- Systems Manager: Parameter Store access
- IAM Identity Center: SSO Admin and Identity Store APIs
- STS: Get caller identity
- CloudFront: Create/manage distributions
- Bedrock: Invoke model permissions

### Environment Setup

**AWS Credentials**
```bash
# Configure AWS CLI
aws configure

# Or use environment variables
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-1"

# Or use AWS profiles
export AWS_PROFILE="your-profile"
```

**Region Selection**
- Backend can deploy to any region
- Bedrock must be accessed in us-west-2 (handled automatically)
- Default region: us-east-1

### File Dependencies

**Backend Deployment** (`deploy-backend.sh`)
- `backend-template.yaml` - CloudFormation template

**Frontend Deployment** (`deploy-frontend.sh`)
- `frontend-template.yaml` - CloudFormation template
- Backend stack must exist first

**Frontend Upload** (`upload-frontend.sh`)
- `frontend/index.html`
- `frontend/app.js`
- `frontend/styles.css`
- Frontend stack must exist first

### Deployment Order

1. **Backend First**: `./deploy-backend.sh`
   - Creates API, Lambda functions, S3 bucket
   - Generates and stores API key
   
2. **Frontend Second**: `./deploy-frontend.sh`
   - Retrieves backend parameters automatically
   - Creates CloudFront distribution
   
3. **Upload Files**: `./upload-frontend.sh`
   - Uploads web files to S3
   - Invalidates CloudFront cache

## Quick Start

### Recommended: AI-Assisted Deployment

For the safest deployment, use an AI coding assistant (like Kiro CLI, Claude Code, or similar) to review and deploy:

**Example prompt for Kiro CLI or AI coding tools:**

```
Please conduct a comprehensive security and code quality review of this entire 
codebase before deployment. Specifically check for:

1. Security Issues:
   - IAM permissions (ensure least privilege)
   - API authentication and authorization mechanisms
   - Input validation and sanitization
   - Secrets management and credential exposure
   - CORS and network security configurations
   - S3 bucket policies and CloudFront OAC settings

2. Configuration Issues:
   - CloudFormation template syntax and best practices
   - Lambda function configurations and timeouts
   - API Gateway rate limiting and throttling
   - Resource naming and tagging

3. Code Quality:
   - Error handling and logging
   - Python code quality and potential bugs
   - Bash script safety and error handling

Fix any critical or high-severity issues you identify. If there are unresolved 
security vulnerabilities or blocking issues, STOP and report them - do not 
proceed with deployment.

Once the codebase passes all security checks and any issues are resolved, 
deploy the application by executing these commands in order:
1. ./deploy-backend.sh
2. ./deploy-frontend.sh  
3. ./upload-frontend.sh

After deployment, verify that all resources are created successfully and 
provide a summary of:
- Issues found and fixed
- Deployment status
- CloudFront URL for accessing the application
- Any recommendations for post-deployment security hardening
```

**Why use AI-assisted deployment?**
- Automated pre-deployment security scanning
- Detection of common misconfigurations and vulnerabilities
- CloudFormation template validation
- Identification of potential runtime issues
- Safer deployment with comprehensive pre-flight checks
- Documentation of issues found and resolved

### Manual Deployment

If you've already completed security reviews or performed the necessary checks for a manual deployment:

#### 1. Deploy Backend
```bash
./deploy-backend.sh
```
This will:
- Auto-detect or create IAM Identity Center instance
- Generate secure API key
- Deploy Lambda functions, API Gateway, S3 bucket
- Store credentials in Parameter Store

#### 2. Deploy Frontend
```bash
./deploy-frontend.sh
./upload-frontend.sh
```
This will:
- Create CloudFront distribution
- Configure S3 bucket for frontend hosting
- Upload web files and invalidate cache

#### 3. Access the Application
```bash
# Get CloudFront URL
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-frontend \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text
```

Visit: `https://<cloudfront-id>.cloudfront.net/`

**Note**: The CloudFront distribution includes `DefaultRootObject: index.html`, so accessing the root URL will automatically serve the index page.

## Current Configuration

### Stack Names
- Backend: `kiro-user-management-api`
- Frontend: `kiro-user-management-frontend`

### API Endpoints
- `POST /create-user` - Admin user creation
- `POST /check-credits` - Credit verification and auto-upgrade

### Rate Limits
- Steady-state: 1 request/second
- Burst: 5 requests
- Daily quota: 10,000 requests

### AWS Services Used
- **Lambda**: 2 functions (Python 3.12)
  - UserManagementFunction
  - CheckCreditsFunction
- **API Gateway**: REST API with API key auth
- **Bedrock**: Nova Pro model (us-west-2)
- **S3**: Screenshot storage (90-day retention)
- **CloudFront**: Global CDN for frontend
- **IAM Identity Center**: User and group management
- **Parameter Store**: Secure configuration storage

### Parameter Store Paths
- `/kiro/kiro-user-management-api/api-key` - API key (for reference only, not used by API Gateway)
- `/kiro/kiro-user-management-api/bedrock-prompt` - Bedrock system prompt
- `/kiro/kiro-user-management-api/kiro-pro-group-id` - Kiro Pro group ID
- `/kiro/kiro-user-management-frontend/api-endpoint` - API endpoint URL

**Important**: The API key in Parameter Store is for reference/retrieval only. API Gateway uses the key set during CloudFormation deployment via the `ApiKey` resource.

## Common Commands

### Retrieve API Credentials
```bash
# Get API endpoint
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-api \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text

# Get API key (from Parameter Store - for reference only)
aws ssm get-parameter \
  --name /kiro/kiro-user-management-api/api-key \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

### Rotate API Key
```bash
# Generate new secure API key
NEW_API_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)
echo "New API Key: $NEW_API_KEY"

# Get Identity Center instance ARN
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)
echo "Instance ARN: $INSTANCE_ARN"

# Delete existing stack (required due to API key name immutability)
aws cloudformation delete-stack --stack-name kiro-user-management-api
aws cloudformation wait stack-delete-complete --stack-name kiro-user-management-api

# Redeploy with new API key
./deploy-backend.sh -f "$INSTANCE_ARN" "$NEW_API_KEY"

# Update frontend with new API endpoint (if changed)
./upload-frontend.sh
```

**Why delete and recreate?** API Gateway API keys have immutable names. Updating the stack with a new key value attempts to create a new key with the same name, which fails. The Parameter Store value is only for reference - it doesn't control API authentication.

### Update Bedrock Prompt
```bash
./update-bedrock-prompt.sh
```

### Update Frontend
```bash
# After making changes to frontend files
./upload-frontend.sh
```

### Check Stack Status
```bash
# Backend
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-api \
  --query 'Stacks[0].StackStatus' \
  --output text

# Frontend
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-frontend \
  --query 'Stacks[0].StackStatus' \
  --output text
```

### View CloudWatch Logs
```bash
# User management function logs
aws logs tail /aws/lambda/kiro-user-management-api-user-management --follow

# Check credits function logs
aws logs tail /aws/lambda/kiro-user-management-api-check-credits --follow
```

### List S3 Screenshots
```bash
# Get bucket name
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name kiro-user-management-api \
  --query 'Stacks[0].Outputs[?OutputKey==`ScreenshotsBucketName`].OutputValue' \
  --output text)

# List recent screenshots
aws s3 ls s3://$BUCKET/screenshots/ --recursive --human-readable
```

## Testing

### Run Full Test Suite
```bash
# Install dependencies
pip3 install requests boto3

# Test backend API
python3 test_api.py

# Test credit checking
python3 test_check_credits.py --verify-s3

# Verify stack deployment
python3 check_stack.py
```

### Manual API Testing
```bash
# Get credentials
API_KEY=$(aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption --query 'Parameter.Value' --output text)
API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' --output text)

# Test create-user endpoint
curl -X POST $API_ENDPOINT/create-user \
  -H "Content-Type: application/json" \
  -H "x-api-key: $API_KEY" \
  -d '{"name": "Test User", "email": "test@example.com"}'
```

## Troubleshooting

### Stack Deployment Failed
```bash
# View stack events
aws cloudformation describe-stack-events \
  --stack-name kiro-user-management-api \
  --query 'StackEvents[0:10].[Timestamp,ResourceType,ResourceStatus,ResourceStatusReason]' \
  --output table

# Delete failed stack and redeploy
aws cloudformation delete-stack --stack-name kiro-user-management-api
./deploy-backend.sh
```

### CloudFront Cache Issues
```bash
# Get distribution ID
DIST_ID=$(aws cloudformation describe-stacks \
  --stack-name kiro-user-management-frontend \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
  --output text)

# Create cache invalidation
aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/frontend/*"
```

### Lambda Function Errors
```bash
# Check recent errors in logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/kiro-user-management-api-check-credits \
  --filter-pattern "ERROR" \
  --max-items 10
```

### API Gateway 403 Errors
- Verify API key is correct (retrieve from Parameter Store)
- Check usage plan limits haven't been exceeded
- Ensure `x-api-key` header is included in request
- **Note**: Updating the API key in Parameter Store does NOT change authentication - you must redeploy the stack

### CloudFront AccessDenied Errors
- Ensure `DefaultRootObject: index.html` is set in CloudFront distribution
- Verify S3 bucket policy allows CloudFront OAC access
- Check that frontend files are uploaded to S3 bucket root (not in a subfolder)
- Wait 10-15 minutes for CloudFront distribution to fully deploy

### Frontend Error Messages
The frontend now provides specific error messages:
- **403 Forbidden**: "Invalid API key. Please check your API key and try again."
- **429 Too Many Requests**: "Rate limit exceeded. Please wait a moment and try again."
- **Network Errors**: "Unable to connect to the API. Please check your internet connection."
- **Other HTTP Errors**: Specific messages based on status code (400, 500, etc.)

### Bedrock Access Issues
- Verify Bedrock access is enabled in us-west-2 region
- Check IAM role has `bedrock:InvokeModel` permission
- Confirm Nova Pro model is available in your account

## Cleanup

### Delete All Resources
```bash
# Delete frontend stack
aws cloudformation delete-stack --stack-name kiro-user-management-frontend

# Empty S3 bucket (required before deleting backend)
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name kiro-user-management-api \
  --query 'Stacks[0].Outputs[?OutputKey==`ScreenshotsBucketName`].OutputValue' \
  --output text)
aws s3 rm s3://$BUCKET --recursive

# Delete backend stack
aws cloudformation delete-stack --stack-name kiro-user-management-api
```

## Security Best Practices

1. **Rotate API Keys Regularly**: 
   - Generate new key: `openssl rand -base64 32 | tr -d '/+=' | cut -c1-32`
   - Delete and recreate stack with new key (see "Rotate API Key" section)
   - Distribute new key to authorized users
   
2. **Monitor Usage**: 
   - Check CloudWatch metrics for unusual activity
   - Review API Gateway usage plan metrics
   - Set up CloudWatch alarms for rate limit breaches
   
3. **Review S3 Audit Trail**: 
   - Periodically review stored screenshots in S3
   - Screenshots are automatically deleted after 90 days
   
4. **Limit API Key Distribution**: 
   - Only share with authorized users
   - Users enter API key in web UI (not embedded in frontend)
   
5. **Enable CloudTrail**: 
   - Track all API calls for compliance
   - Monitor CloudFormation stack changes
   
6. **Use HTTPS Only**: 
   - CloudFront enforces HTTPS (redirect-to-https)
   - Never access the API over HTTP
   
7. **Review IAM Permissions**: 
   - Ensure Lambda roles follow least privilege
   - Regularly audit IAM policies
   
8. **CloudFront Security**:
   - Origin Access Control (OAC) prevents direct S3 access
   - S3 bucket is not publicly accessible

## Cost Optimization

- **Lambda**: Typically $0-5/month for moderate usage
- **API Gateway**: $0-10/month depending on request volume
- **Bedrock**: ~$0.0008 per image analysis (primary cost driver)
- **S3**: Minimal cost with 90-day lifecycle policy
- **CloudFront**: Free tier covers most usage

**Estimated Total**: $1-50/month depending on screenshot analysis volume

## Support

For issues or questions:
1. Check CloudWatch Logs for error details
2. Review `ARCHITECTURE.md` for system design
3. Consult `README.md` for detailed documentation
4. Check `archive/` folder for historical change documentation

# Kiro User Management - Deployment Guide

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

### 1. Deploy Backend
```bash
./deploy-backend.sh
```
This will:
- Auto-detect or create IAM Identity Center instance
- Generate secure API key
- Deploy Lambda functions, API Gateway, S3 bucket
- Store credentials in Parameter Store

### 2. Deploy Frontend
```bash
./deploy-frontend.sh
./upload-frontend.sh
```
This will:
- Create CloudFront distribution
- Configure S3 bucket for frontend hosting
- Upload web files and invalidate cache

### 3. Access the Application
```bash
# Get CloudFront URL
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-frontend \
  --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
  --output text
```

Visit: `https://<cloudfront-id>.cloudfront.net/frontend/`

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
- `/kiro/kiro-user-management-api/api-key` - API key (SecureString)
- `/kiro/kiro-user-management-api/bedrock-prompt` - Bedrock system prompt
- `/kiro/kiro-user-management-api/kiro-pro-group-id` - Kiro Pro group ID

## Common Commands

### Retrieve API Credentials
```bash
# Get API endpoint
aws cloudformation describe-stacks \
  --stack-name kiro-user-management-api \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
  --output text

# Get API key
aws ssm get-parameter \
  --name /kiro/kiro-user-management-api/api-key \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text
```

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
- Verify API key is correct
- Check usage plan limits haven't been exceeded
- Ensure `x-api-key` header is included in request

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

1. **Rotate API Keys Regularly**: Update the API key parameter and redeploy
2. **Monitor Usage**: Check CloudWatch metrics for unusual activity
3. **Review S3 Audit Trail**: Periodically review stored screenshots
4. **Limit API Key Distribution**: Only share with authorized users
5. **Enable CloudTrail**: Track all API calls for compliance
6. **Use HTTPS Only**: Never access the API over HTTP
7. **Review IAM Permissions**: Ensure Lambda roles follow least privilege

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

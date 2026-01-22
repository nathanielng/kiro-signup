# Technical Stack

## Infrastructure as Code
- **CloudFormation**: Pure CloudFormation templates (no SAM CLI)
- **Inline Lambda Code**: Python code embedded directly in CloudFormation templates
- **Two Stacks**: Separate backend and frontend stacks

## Backend Stack
- **Runtime**: Python 3.12
- **Lambda Functions**: 
  - UserManagementFunction (user creation and group management)
  - CheckCreditsFunction (screenshot analysis and credit verification)
- **API Gateway**: REST API with API key authentication
- **S3**: Screenshot storage with 90-day lifecycle policy
- **Parameter Store**: Secure configuration storage
- **IAM Identity Center**: User and group management

## Frontend Stack
- **CloudFront**: Global CDN with Origin Access Control (OAC)
- **S3**: Static website hosting (HTML, CSS, JavaScript)
- **Vanilla JavaScript**: No frameworks, pure ES6+
- **Session Storage**: API key persistence in browser

## AWS Services
- **Bedrock**: Nova Pro model in us-west-2 for image analysis
- **IAM**: Role-based access control with least privilege
- **CloudWatch**: Logging and monitoring
- **Systems Manager**: Parameter Store for configuration

## Security
- HTTPS only (CloudFront enforces redirect-to-https)
- API key authentication (x-api-key header)
- Rate limiting via API Gateway usage plans
- Origin Access Control for S3 (no public bucket access)
- SecureString parameters for sensitive data

## Common Commands

### Backend Deployment
```bash
# Interactive deployment (auto-detects Identity Center)
./deploy-backend.sh

# Force update (skip prompts)
./deploy-backend.sh -f

# With specific Identity Center instance
./deploy-backend.sh arn:aws:sso:::instance/ssoins-xxxxx

# With custom API key
./deploy-backend.sh <instance-arn> <api-key>

# With specific region
./deploy-backend.sh <instance-arn> <api-key> us-west-2
```

### Frontend Deployment
```bash
# Deploy CloudFront distribution
./deploy-frontend.sh

# Force update
./deploy-frontend.sh -f

# Upload frontend files and invalidate cache
./upload-frontend.sh
```

### Testing
```bash
# Install dependencies
pip3 install requests boto3

# Run automated tests (auto-retrieves credentials)
python3 test_api.py

# Test credit checking
python3 test_check_credits.py --verify-s3

# Verify stack deployment
python3 check_stack.py
```

### Monitoring
```bash
# View Lambda logs
aws logs tail /aws/lambda/kiro-user-management-api-user-management --follow
aws logs tail /aws/lambda/kiro-user-management-api-check-credits --follow

# Check stack status
aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].StackStatus'

# List screenshots
BUCKET=$(aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ScreenshotsBucketName`].OutputValue' --output text)
aws s3 ls s3://$BUCKET/screenshots/ --recursive
```

### Retrieve Credentials
```bash
# Get API endpoint
aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' --output text

# Get API key (reference only, not used by API Gateway)
aws ssm get-parameter --name /kiro/kiro-user-management-api/api-key --with-decryption --query 'Parameter.Value' --output text

# Get CloudFront URL
aws cloudformation describe-stacks --stack-name kiro-user-management-frontend --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' --output text
```

### API Key Rotation
```bash
# Generate new key
NEW_KEY=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)

# Get instance ARN
INSTANCE_ARN=$(aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text)

# Delete and recreate stack (required due to API key immutability)
aws cloudformation delete-stack --stack-name kiro-user-management-api
aws cloudformation wait stack-delete-complete --stack-name kiro-user-management-api
./deploy-backend.sh -f "$INSTANCE_ARN" "$NEW_KEY"
```

### Cleanup
```bash
# Delete frontend
aws cloudformation delete-stack --stack-name kiro-user-management-frontend

# Empty S3 bucket
BUCKET=$(aws cloudformation describe-stacks --stack-name kiro-user-management-api --query 'Stacks[0].Outputs[?OutputKey==`ScreenshotsBucketName`].OutputValue' --output text)
aws s3 rm s3://$BUCKET --recursive

# Delete backend
aws cloudformation delete-stack --stack-name kiro-user-management-api
```

## Development Notes
- Lambda timeout: 30s (UserManagement), 60s (CheckCredits)
- API Gateway stage: prod
- S3 lifecycle: 90-day retention for screenshots
- CloudFormation templates: ~1000 lines (backend), ~150 lines (frontend)
- No external dependencies or build process required

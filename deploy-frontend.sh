#!/bin/bash

# Deploy CloudFront frontend for Kiro User Management API
# This script retrieves parameters from the backend stack and deploys the frontend

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKEND_STACK_NAME="kiro-user-management-api"
FRONTEND_STACK_NAME="kiro-user-management-frontend"
TEMPLATE_FILE="frontend-template.yaml"

# Parse command line arguments
FORCE_UPDATE=false
if [[ "$1" == "-f" ]]; then
    FORCE_UPDATE=true
    shift
fi

# Get AWS region
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Kiro User Management Frontend Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if backend stack exists
echo -e "${YELLOW}Checking backend stack...${NC}"
if ! aws cloudformation describe-stacks --stack-name "$BACKEND_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${RED}Error: Backend stack '$BACKEND_STACK_NAME' not found${NC}"
    echo -e "${RED}Please deploy the backend stack first using deploy-backend.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Backend stack found${NC}"
echo ""

# Retrieve parameters from backend stack
echo -e "${YELLOW}Retrieving parameters from backend stack...${NC}"

# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$BACKEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

if [[ -z "$API_ENDPOINT" ]]; then
    echo -e "${RED}Error: Could not retrieve API endpoint from backend stack${NC}"
    exit 1
fi
echo -e "${GREEN}✓ API Endpoint: $API_ENDPOINT${NC}"

# Note: API key is no longer passed to frontend stack
# Users will enter their own API key in the web interface
echo -e "${GREEN}✓ API key will be entered by users in the web UI${NC}"

# Get S3 bucket name
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$BACKEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ScreenshotsBucketName`].OutputValue' \
    --output text 2>/dev/null)

# If not in outputs, construct it
if [[ -z "$S3_BUCKET" ]]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    S3_BUCKET="kiro-user-management-api-screenshots-${ACCOUNT_ID}"
fi

# Check if S3 bucket exists, create if it doesn't
if ! aws s3 ls "s3://$S3_BUCKET" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${YELLOW}S3 bucket '$S3_BUCKET' not found. Creating...${NC}"
    
    # Create bucket with appropriate configuration based on region
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        # us-east-1 doesn't need LocationConstraint
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$AWS_REGION"
    else
        # Other regions need LocationConstraint
        aws s3api create-bucket \
            --bucket "$S3_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Block public access (security best practice)
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=false,RestrictPublicBuckets=false"
    
    # Add lifecycle policy for screenshots (90-day retention)
    cat > /tmp/lifecycle-policy.json <<EOF
{
    "Rules": [
        {
            "ID": "DeleteOldScreenshots",
            "Status": "Enabled",
            "Prefix": "screenshots/",
            "Expiration": {
                "Days": 90
            }
        }
    ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET" \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json
    
    rm /tmp/lifecycle-policy.json
    
    echo -e "${GREEN}✓ S3 bucket created: $S3_BUCKET${NC}"
else
    echo -e "${GREEN}✓ S3 bucket exists: $S3_BUCKET${NC}"
fi
echo ""

# Check if frontend stack already exists
STACK_EXISTS=false
if aws cloudformation describe-stacks --stack-name "$FRONTEND_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    STACK_EXISTS=true
    STACK_STATUS=$(aws cloudformation describe-stacks \
        --stack-name "$FRONTEND_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].StackStatus' \
        --output text)
    
    echo -e "${YELLOW}Frontend stack already exists with status: $STACK_STATUS${NC}"
    
    if [[ "$FORCE_UPDATE" == false ]]; then
        echo ""
        echo -e "${YELLOW}What would you like to do?${NC}"
        echo "1) Update existing stack"
        echo "2) Delete and recreate stack"
        echo "3) Cancel"
        read -p "Enter choice (1-3): " choice
        
        case $choice in
            1)
                echo -e "${GREEN}Updating existing stack...${NC}"
                ;;
            2)
                echo -e "${YELLOW}Deleting existing stack...${NC}"
                aws cloudformation delete-stack \
                    --stack-name "$FRONTEND_STACK_NAME" \
                    --region "$AWS_REGION"
                
                echo -e "${YELLOW}Waiting for stack deletion...${NC}"
                aws cloudformation wait stack-delete-complete \
                    --stack-name "$FRONTEND_STACK_NAME" \
                    --region "$AWS_REGION"
                
                echo -e "${GREEN}✓ Stack deleted${NC}"
                STACK_EXISTS=false
                ;;
            3)
                echo -e "${YELLOW}Deployment cancelled${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${GREEN}Force update mode - updating existing stack${NC}"
    fi
    echo ""
fi

# Deploy CloudFormation stack
echo -e "${YELLOW}Deploying frontend CloudFormation stack...${NC}"
echo ""

if [[ "$STACK_EXISTS" == true ]]; then
    # Update existing stack
    aws cloudformation update-stack \
        --stack-name "$FRONTEND_STACK_NAME" \
        --region "$AWS_REGION" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=ApiEndpoint,ParameterValue="$API_ENDPOINT" \
            ParameterKey=S3BucketName,ParameterValue="$S3_BUCKET" \
        --capabilities CAPABILITY_IAM
    
    echo -e "${YELLOW}Waiting for stack update to complete...${NC}"
    aws cloudformation wait stack-update-complete \
        --stack-name "$FRONTEND_STACK_NAME" \
        --region "$AWS_REGION"
else
    # Create new stack
    aws cloudformation create-stack \
        --stack-name "$FRONTEND_STACK_NAME" \
        --region "$AWS_REGION" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters \
            ParameterKey=ApiEndpoint,ParameterValue="$API_ENDPOINT" \
            ParameterKey=S3BucketName,ParameterValue="$S3_BUCKET" \
        --capabilities CAPABILITY_IAM
    
    echo -e "${YELLOW}Waiting for stack creation to complete...${NC}"
    aws cloudformation wait stack-create-complete \
        --stack-name "$FRONTEND_STACK_NAME" \
        --region "$AWS_REGION"
fi

echo ""
echo -e "${GREEN}✓ CloudFormation stack deployed successfully${NC}"
echo ""

# Get stack outputs
echo -e "${YELLOW}Retrieving stack outputs...${NC}"
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "$FRONTEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
    --output text)

CLOUDFRONT_ID=$(aws cloudformation describe-stacks \
    --stack-name "$FRONTEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
    --output text)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Frontend Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}CloudFront URL:${NC} $CLOUDFRONT_URL"
echo -e "${BLUE}Distribution ID:${NC} $CLOUDFRONT_ID"
echo -e "${BLUE}S3 Bucket:${NC} $S3_BUCKET"
echo -e "${BLUE}Frontend Path:${NC} s3://$S3_BUCKET/frontend/"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Upload frontend files to S3:"
echo -e "   ${BLUE}./upload-frontend.sh${NC}"
echo ""
echo "2. Access the web application:"
echo -e "   ${BLUE}$CLOUDFRONT_URL${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} CloudFront distribution may take 10-15 minutes to fully deploy"
echo ""

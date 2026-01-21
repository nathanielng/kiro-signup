#!/bin/bash

# Upload frontend files to S3 and invalidate CloudFront cache
# This script configures the frontend with API credentials and uploads to S3

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
FRONTEND_DIR="frontend"
TEMP_DIR="frontend-build"

# Get AWS region
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Kiro Frontend Upload${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if frontend stack exists
echo -e "${YELLOW}Checking frontend stack...${NC}"
if ! aws cloudformation describe-stacks --stack-name "$FRONTEND_STACK_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${RED}Error: Frontend stack '$FRONTEND_STACK_NAME' not found${NC}"
    echo -e "${RED}Please deploy the frontend stack first using deploy-frontend.sh${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Frontend stack found${NC}"
echo ""

# Get parameters from stacks
echo -e "${YELLOW}Retrieving configuration...${NC}"

# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "$BACKEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

if [[ -z "$API_ENDPOINT" ]]; then
    echo -e "${RED}Error: Could not retrieve API endpoint${NC}"
    exit 1
fi
echo -e "${GREEN}✓ API Endpoint: $API_ENDPOINT${NC}"

# Note: API key is no longer embedded in frontend
# Users will enter their own API key in the web interface
echo -e "${GREEN}✓ API key will be entered by users${NC}"

# Get S3 bucket name
S3_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name "$FRONTEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
    --output text)

if [[ -z "$S3_BUCKET" ]]; then
    echo -e "${RED}Error: Could not retrieve S3 bucket name${NC}"
    exit 1
fi
echo -e "${GREEN}✓ S3 Bucket: $S3_BUCKET${NC}"

# Get CloudFront distribution ID
CLOUDFRONT_ID=$(aws cloudformation describe-stacks \
    --stack-name "$FRONTEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDistributionId`].OutputValue' \
    --output text)

if [[ -z "$CLOUDFRONT_ID" ]]; then
    echo -e "${RED}Error: Could not retrieve CloudFront distribution ID${NC}"
    exit 1
fi
echo -e "${GREEN}✓ CloudFront Distribution: $CLOUDFRONT_ID${NC}"
echo ""

# Create temporary build directory
echo -e "${YELLOW}Preparing frontend files...${NC}"
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Copy frontend files
cp -r "$FRONTEND_DIR"/* "$TEMP_DIR/"

# Generate config.js with actual values
cat > "$TEMP_DIR/config.js" << EOF
// API Configuration
// Auto-generated during deployment
const API_CONFIG = {
    endpoint: '$API_ENDPOINT'
    // API key is entered by users in the web interface
};
EOF

echo -e "${GREEN}✓ Frontend files prepared${NC}"
echo ""

# Upload to S3
echo -e "${YELLOW}Uploading files to S3...${NC}"

# Upload HTML
aws s3 cp "$TEMP_DIR/index.html" "s3://$S3_BUCKET/index.html" \
    --content-type "text/html" \
    --cache-control "max-age=300" \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Uploaded index.html${NC}"

# Upload CSS
aws s3 cp "$TEMP_DIR/styles.css" "s3://$S3_BUCKET/styles.css" \
    --content-type "text/css" \
    --cache-control "max-age=86400" \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Uploaded styles.css${NC}"

# Upload JS files
aws s3 cp "$TEMP_DIR/config.js" "s3://$S3_BUCKET/config.js" \
    --content-type "application/javascript" \
    --cache-control "max-age=300" \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Uploaded config.js${NC}"

aws s3 cp "$TEMP_DIR/app.js" "s3://$S3_BUCKET/app.js" \
    --content-type "application/javascript" \
    --cache-control "max-age=86400" \
    --region "$AWS_REGION"
echo -e "${GREEN}✓ Uploaded app.js${NC}"

echo ""

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Invalidate CloudFront cache
echo -e "${YELLOW}Invalidating CloudFront cache...${NC}"
INVALIDATION_ID=$(aws cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_ID" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)

echo -e "${GREEN}✓ Cache invalidation created: $INVALIDATION_ID${NC}"
echo ""

# Get CloudFront URL
CLOUDFRONT_URL=$(aws cloudformation describe-stacks \
    --stack-name "$FRONTEND_STACK_NAME" \
    --region "$AWS_REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
    --output text)

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Frontend Upload Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}CloudFront URL:${NC} $CLOUDFRONT_URL"
echo -e "${BLUE}S3 Location:${NC} s3://$S3_BUCKET/"
echo ""
echo -e "${YELLOW}Note:${NC} CloudFront cache invalidation may take a few minutes to complete"
echo -e "${YELLOW}Access your application at:${NC} ${CLOUDFRONT_URL}"
echo ""

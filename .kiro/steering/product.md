# Product Overview

## Purpose
Kiro User Management API is a serverless system that automates the upgrade of users to Kiro Pro when their free credits are depleted. The system analyzes credit usage screenshots using AI and automatically provisions access to premium features.

## Core Functionality
- **Credit Verification**: Uses AWS Bedrock (Nova Pro model) to analyze screenshots of credit usage
- **Email Verification**: Validates that the screenshot matches the user's email address
- **Automatic Provisioning**: Creates users in IAM Identity Center and adds them to the "Kiro Pro" group
- **Audit Trail**: Stores all screenshots in S3 with 90-day retention for compliance
- **Web Interface**: CloudFront-hosted frontend for easy user access

## User Flows

### Primary Flow (Check Credits)
1. User uploads screenshot showing depleted credits
2. System verifies email matches screenshot
3. System checks if credits are actually depleted
4. If verified, user is automatically added to Kiro Pro group
5. User receives confirmation and access is provisioned

### Admin Flow (Create User)
Direct user creation endpoint for administrative purposes without credit verification.

## Key Features
- API key authentication with rate limiting (1 req/sec, 5 burst, 10K/day)
- Duplicate user detection
- Automatic group creation if "Kiro Pro" group doesn't exist
- CORS support for web applications
- Global CDN distribution via CloudFront

## Important Notes
- This code was AI-generated and requires security review before production use
- Only one IAM Identity Center instance allowed per region
- Bedrock access must be enabled in us-west-2 region
- API keys are immutable and require stack recreation to rotate

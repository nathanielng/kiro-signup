# Implementation Plan: Kiro User Management API

## Overview

This implementation plan breaks down the Kiro User Management API into discrete coding tasks. The system is a serverless application using CloudFormation for infrastructure, Python 3.12 for Lambda functions, and vanilla JavaScript for the frontend. All tasks build incrementally, with testing integrated throughout to validate functionality early.

## Tasks

- [ ] 1. Create backend CloudFormation template structure
  - Create `backend-template.yaml` with basic structure (AWSTemplateFormatVersion, Description)
  - Define Parameters section (IdentityCenterInstanceArn, ApiKeyValue)
  - Define Outputs section (ApiEndpoint, CreateUserEndpoint, CheckCreditsEndpoint, parameter names, Lambda ARNs)
  - _Requirements: 7.1, 7.2, 7.5_

- [ ] 2. Implement IAM roles for Lambda functions
  - [ ] 2.1 Create UserManagementLambdaRole with Identity Center permissions
    - Define AssumeRolePolicyDocument for Lambda service
    - Add managed policy for CloudWatch Logs
    - Add inline policy for sso-admin:*, identitystore:*, sso:ListInstances
    - _Requirements: 7.4_
  
  - [ ] 2.2 Create CheckCreditsLambdaRole with comprehensive permissions
    - Define AssumeRolePolicyDocument for Lambda service
    - Add managed policy for CloudWatch Logs
    - Add inline policy for Bedrock, S3, Lambda invoke, SSM, Identity Center operations
    - _Requirements: 7.4_

- [ ] 3. Implement UserManagementFunction Lambda
  - [ ] 3.1 Create Lambda function resource with inline Python code
    - Define function properties (Runtime: python3.12, Handler: index.lambda_handler, Timeout: 30)
    - Set environment variable IDENTITY_CENTER_INSTANCE_ARN
    - Implement lambda_handler function with request parsing and error handling
    - _Requirements: 7.1, 7.6, 3.1_
  
  - [ ] 3.2 Implement get_identity_store_id function
    - Call sso_admin_client.list_instances()
    - Extract IdentityStoreId from matching instance or use first available
    - Handle case where no instances exist
    - _Requirements: 2.1_
  
  - [ ] 3.3 Implement find_user_by_email function
    - Call identitystore_client.list_users with email filter
    - Return user object if found, None otherwise
    - _Requirements: 2.1_
  
  - [ ] 3.4 Implement create_identity_center_user function
    - Check for duplicate users using find_user_by_email
    - Call identitystore_client.create_user with user details
    - Handle ConflictException for duplicates
    - Return success/error dict with user_id
    - _Requirements: 3.2, 2.1_
  
  - [ ] 3.5 Implement get_kiro_pro_group_id function
    - Check environment variable first
    - Search for group by displayName "Kiro Pro"
    - Create group if it doesn't exist
    - Return group ID
    - _Requirements: 4.1, 4.2_
  
  - [ ] 3.6 Implement add_user_to_group function
    - Call identitystore_client.create_group_membership
    - Return success/error dict
    - _Requirements: 4.4_
  
  - [ ] 3.7 Implement create_response helper function
    - Format HTTP response with status code, CORS headers, JSON body
    - _Requirements: 7.8_
  
  - [ ] 3.8 Wire together user creation flow in lambda_handler
    - Handle existing_user_id parameter to skip user creation
    - Call functions in sequence: get_identity_store_id → create_user (or skip) → get_kiro_pro_group_id → add_user_to_group
    - Return formatted response with user details
    - _Requirements: 3.3, 3.4, 2.1.4_
  
  - [ ]* 3.9 Write property test for input validation
    - **Property 1: Input Validation Completeness**
    - **Validates: Requirements 1.1, 3.1, 9.6**
  
  - [ ]* 3.10 Write property test for duplicate user check
    - **Property 6: Duplicate User Check**
    - **Validates: Requirements 2.1**
  
  - [ ]* 3.11 Write property test for admin user group membership
    - **Property 9: Admin User Group Membership**
    - **Validates: Requirements 3.3, 3.4**
  
  - [ ]* 3.12 Write unit tests for UserManagementFunction
    - Test Example 2: Existing user not in group
    - Test Example 5: Admin user creation
    - Test Example 11: Group creation
    - Test error handling for Identity Center failures
    - _Requirements: 3.2, 2.4, 4.2_

- [ ] 4. Checkpoint - Ensure UserManagementFunction tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 5. Implement CheckCreditsFunction Lambda
  - [ ] 5.1 Create Lambda function resource with inline Python code
    - Define function properties (Runtime: python3.12, Handler: index.lambda_handler, Timeout: 60)
    - Set environment variables (KIRO_S3_BUCKET, USER_MANAGEMENT_FUNCTION_NAME)
    - Implement lambda_handler function with request parsing and orchestration logic
    - _Requirements: 7.1, 7.7, 1.1_
  
  - [ ] 5.2 Implement check_user_kiro_pro_status function
    - Get Identity Store ID from SSO instances
    - Search for user by email (userName attribute)
    - If user exists, search for Kiro Pro group
    - Check if user is member of Kiro Pro group
    - Return dict with user_exists, user_id, in_kiro_pro
    - _Requirements: 2.2, 2.3_
  
  - [ ] 5.3 Implement get_s3_bucket_name function
    - Check environment variable KIRO_S3_BUCKET
    - If not set, construct default: kiro-user-management-api-screenshots-{account_id}
    - Use sts.get_caller_identity() to get account ID
    - _Requirements: 5.1_
  
  - [ ] 5.4 Implement generate_s3_key function
    - Get current timestamp in format YYYYMMDD-HHMMSS
    - Sanitize email: @ → _at_, . → _, + → _plus_
    - Remove non-alphanumeric characters except _ and -
    - Add -deny suffix if credits_used_up is False
    - Return screenshots/{timestamp}-{sanitized_email}[-deny].png
    - _Requirements: 5.2, 5.3, 5.6, 5.7_
  
  - [ ] 5.5 Implement save_image_to_s3 function
    - Decode base64 image data
    - Call s3.put_object with bucket, key, body, ContentType, Metadata
    - Return S3 URI (s3://bucket/key) or None on error
    - _Requirements: 1.7, 5.8, 5.9_
  
  - [ ] 5.6 Implement check_credits_used_up function
    - Decode base64 image data
    - Retrieve Bedrock prompt from Parameter Store (with fallback)
    - Substitute {email} placeholder in prompt
    - Construct Bedrock request with image and prompt
    - Invoke bedrock.invoke_model with us.amazon.nova-pro-v1:0
    - Parse response to extract MATCH/NOMATCH and YES/NO
    - Handle unexpected response format (default to safe values)
    - Save screenshot to S3 with appropriate suffix
    - Return dict with email_match, credits_used_up, s3_uri, timestamp
    - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5, 14.6, 14.7, 14.8, 14.9, 14.10, 14.11_
  
  - [ ] 5.7 Implement add_user_to_kiro_pro function
    - Extract names from email if not provided
    - Construct payload with name, email, firstName, lastName
    - Add existing_user_id to payload if provided
    - Invoke UserManagementFunction using lambda_client.invoke
    - Use InvocationType RequestResponse
    - Parse response payload and extract user_id
    - Return success/error dict
    - _Requirements: 2.1.1, 2.1.2, 2.1.3, 2.1.5, 2.1.6_
  
  - [ ] 5.8 Implement create_response helper function
    - Format HTTP response with status code, CORS headers, JSON body
    - _Requirements: 7.8_
  
  - [ ] 5.9 Wire together credit check flow in lambda_handler
    - Check if user already in Kiro Pro (early return if yes)
    - Call check_credits_used_up to analyze screenshot
    - If email doesn't match, return error response
    - If credits not depleted, return error response
    - If email matches and credits depleted, call add_user_to_kiro_pro
    - Return detailed response with all status fields
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 1.6_
  
  - [ ]* 5.10 Write property test for screenshot storage consistency
    - **Property 2: Screenshot Storage Consistency**
    - **Validates: Requirements 1.7, 5.1, 5.2, 5.3**
  
  - [ ]* 5.11 Write property test for screenshot metadata completeness
    - **Property 3: Screenshot Metadata Completeness**
    - **Validates: Requirements 5.8, 5.9**
  
  - [ ]* 5.12 Write property test for email sanitization
    - **Property 4: Email Sanitization Correctness**
    - **Validates: Requirements 5.6, 5.7**
  
  - [ ]* 5.13 Write property test for base64 encoding round trip
    - **Property 5: Base64 Encoding Round Trip**
    - **Validates: Requirements 5.5, 9.7**
  
  - [ ]* 5.14 Write property test for Lambda invocation pattern
    - **Property 7: Lambda Invocation Pattern**
    - **Validates: Requirements 2.1.1, 2.1.2, 2.1.3**
  
  - [ ]* 5.15 Write property test for Lambda response parsing
    - **Property 8: Lambda Response Parsing**
    - **Validates: Requirements 2.1.5, 2.1.6**
  
  - [ ]* 5.16 Write unit tests for CheckCreditsFunction
    - Test Example 1: Already in Kiro Pro
    - Test Example 3: Credits not depleted
    - Test Example 4: Email mismatch
    - Test Example 12: Credits depleted and email match
    - Test error handling for Bedrock failures
    - Test error handling for S3 failures
    - _Requirements: 2.3, 1.5, 1.4_

- [ ] 6. Checkpoint - Ensure CheckCreditsFunction tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Implement API Gateway resources
  - [ ] 7.1 Create API Gateway REST API resource
    - Define UserManagementApi with name and description
    - Set EndpointConfiguration to REGIONAL
    - _Requirements: 7.2_
  
  - [ ] 7.2 Create /create-user resource and methods
    - Define CreateUserResource with PathPart "create-user"
    - Define CreateUserMethod (POST) with ApiKeyRequired: true
    - Configure AWS_PROXY integration to UserManagementFunction
    - Define CreateUserOptionsMethod for CORS preflight
    - _Requirements: 7.2, 7.8_
  
  - [ ] 7.3 Create /check-credits resource and methods
    - Define CheckCreditsResource with PathPart "check-credits"
    - Define CheckCreditsMethod (POST) with ApiKeyRequired: true
    - Configure AWS_PROXY integration to CheckCreditsFunction
    - Define CheckCreditsOptionsMethod for CORS preflight
    - _Requirements: 7.2, 7.8_
  
  - [ ] 7.4 Create API deployment and usage plan
    - Define ApiDeployment with StageName "prod"
    - Define ApiKey resource with provided value
    - Define UsagePlan with rate limiting (RateLimit: 1, BurstLimit: 5, Quota: 10000/DAY)
    - Define UsagePlanKey to link API key to usage plan
    - _Requirements: 6.3, 6.4, 6.5_
  
  - [ ] 7.5 Create Lambda permissions for API Gateway
    - Define LambdaApiGatewayPermission for UserManagementFunction
    - Define CheckCreditsLambdaApiGatewayPermission for CheckCreditsFunction
    - _Requirements: 7.2_

- [ ] 8. Implement Parameter Store resources
  - [ ] 8.1 Create ApiKeyParameter
    - Define SSM Parameter at /kiro/${AWS::StackName}/api-key
    - Type: String, Tier: Advanced
    - Value: !Ref ApiKeyValue
    - _Requirements: 7.5_
  
  - [ ] 8.2 Create KiroProGroupParameter
    - Define SSM Parameter at /kiro/${AWS::StackName}/kiro-pro-group-id
    - Type: String, Value: PLACEHOLDER_GROUP_ID
    - _Requirements: 4.3_
  
  - [ ] 8.3 Create BedrockPromptParameter
    - Define SSM Parameter at /kiro/${AWS::StackName}/bedrock-prompt
    - Type: String
    - Value: Multi-line prompt template with {email} placeholder
    - Include instructions for email verification and credit checking
    - Include response format examples (MATCH,YES / NOMATCH,NO)
    - _Requirements: 5.1.1, 5.1.2, 5.1.3, 5.1.4, 5.1.5, 5.1.6_

- [ ] 9. Implement frontend CloudFormation template
  - [ ] 9.1 Create frontend-template.yaml structure
    - Define Parameters (ApiEndpoint, S3BucketName)
    - Define Outputs (CloudFrontURL, CloudFrontDistributionId, S3BucketName, FrontendPath)
    - _Requirements: 8.1, 8.6_
  
  - [ ] 9.2 Create CloudFront Origin Access Control
    - Define CloudFrontOAC resource
    - Set OriginAccessControlOriginType: s3, SigningBehavior: always, SigningProtocol: sigv4
    - _Requirements: 8.1_
  
  - [ ] 9.3 Create CloudFront distribution
    - Define CloudFrontDistribution with DefaultRootObject: index.html
    - Configure S3 origin with OAC
    - Set ViewerProtocolPolicy: redirect-to-https
    - Configure caching (MinTTL: 0, DefaultTTL: 86400, MaxTTL: 31536000)
    - Add custom error responses (403/404 → index.html)
    - _Requirements: 8.1, 8.3, 8.4, 8.5_
  
  - [ ] 9.4 Create S3 bucket policy
    - Define S3BucketPolicy allowing CloudFront access
    - Use condition AWS:SourceArn matching CloudFront distribution
    - _Requirements: 8.1_
  
  - [ ] 9.5 Create API endpoint parameter
    - Define ApiEndpointParameter at /kiro/${AWS::StackName}/api-endpoint
    - Type: String, Value: !Ref ApiEndpoint
    - _Requirements: 8.6_

- [ ] 10. Implement frontend HTML structure
  - [ ] 10.1 Create index.html with basic structure
    - Define HTML5 doctype, head with meta tags and title
    - Link to styles.css
    - Create container div with header
    - _Requirements: 9.1_
  
  - [ ] 10.2 Create API configuration card
    - Add card div with API key input (type: password)
    - Add toggle visibility button
    - Add hint text about session storage
    - _Requirements: 9.1, 9.2_
  
  - [ ] 10.3 Create credit check form
    - Add form with email input (required)
    - Add firstName and lastName inputs (optional)
    - Add file upload input (accept: image/png, required)
    - Add file upload label with drag-and-drop support
    - Add image preview div (hidden by default)
    - Add submit button with loading state elements
    - _Requirements: 9.1, 9.4_
  
  - [ ] 10.4 Create result display area
    - Add result div (hidden by default)
    - Will be populated dynamically by JavaScript
    - _Requirements: 9.11_
  
  - [ ] 10.5 Add footer and script tags
    - Add footer with attribution text
    - Link to config.js and app.js
    - _Requirements: 9.1_

- [ ] 11. Implement frontend CSS styles
  - [ ] 11.1 Create styles.css with CSS variables
    - Define color variables (primary, success, error, warning, backgrounds)
    - Define shadow variables
    - Reset default styles (margin, padding, box-sizing)
    - _Requirements: 9.1_
  
  - [ ] 11.2 Style container and header
    - Set max-width, margin, padding for container
    - Style header with centered text, large title
    - _Requirements: 9.1_
  
  - [ ] 11.3 Style API configuration card
    - Create card styles with border-radius, padding, shadow
    - Add gradient background for API config card
    - Style API key input with toggle button positioning
    - _Requirements: 9.1, 9.2_
  
  - [ ] 11.4 Style credit check form
    - Style form groups, labels, inputs
    - Create form-row grid for firstName/lastName
    - Style file upload with dashed border and hover effects
    - Style image preview
    - Style submit button with hover and disabled states
    - _Requirements: 9.1, 9.4_
  
  - [ ] 11.5 Style result display
    - Create result styles with color-coded backgrounds (success/error/warning)
    - Add slide-in animation
    - Style result details
    - _Requirements: 9.11_
  
  - [ ] 11.6 Add responsive design
    - Add media query for mobile (max-width: 640px)
    - Adjust container padding, header size, form layout
    - _Requirements: 9.1_

- [ ] 12. Implement frontend JavaScript functionality
  - [ ] 12.1 Create app.js with API key management
    - Implement toggleApiKeyVisibility function
    - Implement getApiKey function
    - Implement validateApiKey function with alert
    - _Requirements: 9.2, 9.3, 9.5_
  
  - [ ] 12.2 Implement file upload preview
    - Add event listener for screenshot-upload change
    - Update file name display
    - Read file and display preview image
    - _Requirements: 9.4_
  
  - [ ] 12.3 Implement fileToBase64 helper function
    - Use FileReader to read file as data URL
    - Remove data URL prefix to get base64 string
    - Return Promise resolving to base64 string
    - _Requirements: 9.7_
  
  - [ ] 12.4 Implement form submission handler
    - Add event listener for check-credits-form submit
    - Validate API key is present
    - Disable button, show loading indicator
    - Read file as base64
    - Construct payload with image, email, optional names
    - POST to API_CONFIG.endpoint/check-credits with x-api-key header
    - _Requirements: 9.6, 9.7, 9.8_
  
  - [ ] 12.5 Implement response handling
    - Handle 403 status: Display authentication failed message
    - Handle 429 status: Display rate limit exceeded message
    - Handle 200 status: Parse response and display appropriate message based on fields
    - Handle other errors: Display generic error message
    - Reset form on successful upgrade
    - Re-enable button, hide loading indicator
    - _Requirements: 9.9, 9.10, 9.11, 9.12_
  
  - [ ] 12.6 Implement network error handling
    - Catch fetch failures
    - Display connection error message with troubleshooting guidance
    - _Requirements: 9.13_
  
  - [ ] 12.7 Implement session storage persistence
    - On DOMContentLoaded, load API key from sessionStorage
    - On API key input change, save to sessionStorage
    - Check if API endpoint is configured, show warning if not
    - _Requirements: 9.2_
  
  - [ ]* 12.8 Write property tests for frontend
    - **Property 15: API Key Session Persistence**
    - **Property 16: API Key Visibility Toggle**
    - **Property 17: Image Preview Display**
    - **Property 18: Form Submission Loading State**
    - **Property 19: Response-Based Message Display**
    - **Property 20: Form Reset on Success**
    - **Validates: Requirements 9.2, 9.3, 9.4, 9.8, 9.11, 9.12**
  
  - [ ]* 12.9 Write unit tests for frontend
    - Test Example 6: Missing API key
    - Test Example 7: Authentication failure (403)
    - Test Example 8: Rate limit exceeded (429)
    - Test Example 9: Network error
    - Test form validation
    - Test base64 encoding
    - _Requirements: 9.5, 9.9, 9.10, 9.13_

- [ ] 13. Checkpoint - Ensure frontend tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 14. Implement deployment scripts
  - [ ] 14.1 Create deploy-backend.sh script
    - Add shebang and color codes for output
    - Parse command line flags (-f for force update)
    - Implement check_identity_center_instances function
    - Implement create_identity_center_instance function
    - Implement prompt_for_identity_center_creation function
    - Implement generate_api_key function (32-character alphanumeric)
    - Implement check_existing_api_key function
    - Implement check_stack_status function
    - Implement handle_failed_stack function
    - Implement handle_existing_stack function
    - Main script logic: check/create Identity Center, generate/retrieve API key, deploy stack
    - Output API endpoint and API key
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7_
  
  - [ ] 14.2 Create deploy-frontend.sh script
    - Add shebang and color codes
    - Parse -f flag for force update
    - Check if backend stack exists
    - Retrieve API endpoint from backend stack
    - Get or create S3 bucket
    - Apply lifecycle policy to S3 bucket (90-day retention for screenshots/)
    - Check if frontend stack exists, prompt for update/recreate
    - Deploy CloudFormation stack
    - Output CloudFront URL
    - _Requirements: 11.1, 11.2, 11.3, 11.4_
  
  - [ ] 14.3 Create upload-frontend.sh script
    - Add shebang and color codes
    - Check if frontend stack exists
    - Retrieve S3 bucket name and CloudFront distribution ID
    - Retrieve API endpoint from backend stack
    - Create temp directory and copy frontend files
    - Generate config.js with API endpoint
    - Upload files to S3 with appropriate content types and cache control
    - Create CloudFront cache invalidation for /*
    - Wait for invalidation to complete
    - Output CloudFront URL
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_
  
  - [ ] 14.4 Create update-bedrock-prompt.sh script
    - Add shebang and color codes
    - Accept new prompt text as input
    - Update Parameter Store entry at /kiro/kiro-user-management-api/bedrock-prompt
    - Confirm update succeeded
    - _Requirements: 13.1.1, 13.1.2, 13.1.3, 13.1.4, 13.1.5_

- [ ] 15. Implement testing scripts
  - [ ] 15.1 Create test_api.py script
    - Import required libraries (requests, boto3, json)
    - Implement function to retrieve API endpoint from CloudFormation
    - Implement function to retrieve API key from Parameter Store
    - Implement test for /create-user endpoint
    - Implement test for /check-credits endpoint with base64 screenshot
    - Output clear success/failure messages
    - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_
  
  - [ ] 15.2 Create check_stack.py script
    - Import boto3
    - Check backend stack status
    - Check frontend stack status
    - Verify all outputs are present
    - Output stack information
    - _Requirements: 13.1_
  
  - [ ] 15.3 Create test_check_credits.py script
    - Import required libraries
    - Implement function to create test screenshot
    - Implement function to call /check-credits endpoint
    - Implement --verify-s3 flag to check screenshot storage
    - Output test results
    - _Requirements: 13.4_

- [ ] 16. Implement error handling and logging
  - [ ]* 16.1 Write property test for error response format
    - **Property 12: Error Response Format**
    - **Validates: Requirements 15.2, 15.3, 15.4, 15.5**
  
  - [ ]* 16.2 Write property test for error logging
    - **Property 13: Error Logging with Context**
    - **Validates: Requirements 15.1, 15.6**
  
  - [ ]* 16.3 Write property test for successful provisioning response
    - **Property 14: Successful Provisioning Response**
    - **Validates: Requirements 1.6**
  
  - [ ]* 16.4 Write property test for group management
    - **Property 10: Group Existence Check**
    - **Property 11: Group Operation Verification**
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.4**

- [ ] 17. Final integration and testing
  - [ ] 17.1 Test complete deployment workflow
    - Run deploy-backend.sh
    - Run deploy-frontend.sh
    - Run upload-frontend.sh
    - Verify all stacks deployed successfully
    - _Requirements: 10.7, 11.4, 12.5_
  
  - [ ] 17.2 Test API endpoints
    - Run test_api.py
    - Verify /create-user works
    - Verify /check-credits works
    - _Requirements: 13.5_
  
  - [ ] 17.3 Test frontend application
    - Access CloudFront URL
    - Test API key entry and session storage
    - Test file upload and preview
    - Test form submission with valid data
    - Test error handling (invalid API key, rate limiting)
    - _Requirements: 9.1, 9.2, 9.4, 9.8, 9.9, 9.10_
  
  - [ ] 17.4 Test end-to-end user flows
    - Test Example 10: API key authentication
    - Test complete credit check flow (new user)
    - Test complete credit check flow (existing user)
    - Test admin user creation flow
    - Verify screenshots stored in S3
    - Verify users created in Identity Center
    - Verify users added to Kiro Pro group
    - _Requirements: 1.4, 2.3, 2.4, 3.2, 5.1, 6.1, 6.2_

- [ ] 18. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional property-based and unit tests that can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation throughout implementation
- Property tests validate universal correctness properties with minimum 100 iterations
- Unit tests validate specific examples and edge cases
- All Lambda code is inline in CloudFormation templates (no separate files)
- Frontend uses vanilla JavaScript (no build process or frameworks)
- Deployment scripts handle all infrastructure setup and updates

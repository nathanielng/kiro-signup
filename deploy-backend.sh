#!/bin/bash

# Pure CloudFormation deployment script for IAM Identity Center User Management API

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default region
DEFAULT_REGION="us-east-1"

# Force update flag
FORCE_UPDATE=false

# Parse command line flags
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--force-update)
            FORCE_UPDATE=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

echo -e "${GREEN}Starting CloudFormation deployment of IAM Identity Center User Management API${NC}"
if [ "$FORCE_UPDATE" = true ]; then
    echo -e "${YELLOW}Force update mode enabled - skipping all prompts${NC}"
fi

# Function to check for existing IAM Identity Center instances
check_identity_center_instances() {
    local region=${1:-$DEFAULT_REGION}
    echo -e "${BLUE}Checking for existing IAM Identity Center instances in region: $region${NC}" >&2
    
    # List existing instances and get just the ARN
    local instance_arn=$(aws sso-admin list-instances --region $region --query 'Instances[0].InstanceArn' --output text 2>/dev/null || echo "")
    
    if [ -n "$instance_arn" ] && [ "$instance_arn" != "None" ] && [ "$instance_arn" != "null" ]; then
        echo -e "${GREEN}Found existing IAM Identity Center instance: $instance_arn${NC}" >&2
        echo "$instance_arn"  # This goes to stdout for capture
    else
        echo "No IAM Identity Center instance found in $region"  # Return empty string if no instances found
    fi
}

# Function to create IAM Identity Center instance
create_identity_center_instance() {
    local region=${1:-$DEFAULT_REGION}
    echo -e "${YELLOW}Creating IAM Identity Center instance in region: $region${NC}" >&2
    
    # Create the instance
    result=$(aws sso-admin create-instance --region $region --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        instance_arn=$(echo "$result" | jq -r '.InstanceArn')
        echo -e "${GREEN}Successfully created IAM Identity Center instance: $instance_arn${NC}" >&2
        echo -e "${YELLOW}Note: It may take a few minutes for the instance to be fully available.${NC}" >&2
        echo "$instance_arn"  # This goes to stdout for capture
    else
        echo -e "${RED}Failed to create IAM Identity Center instance${NC}" >&2
        echo -e "${YELLOW}This might be because:${NC}" >&2
        echo "1. An instance already exists in this region (only one per region is allowed)" >&2
        echo "2. You don't have sufficient permissions" >&2
        echo "3. The service is not available in this region" >&2
        return 1
    fi
}

# Function to prompt user for IAM Identity Center instance creation
prompt_for_identity_center_creation() {
    local region=${1:-$DEFAULT_REGION}
    
    echo -e "${YELLOW}No IAM Identity Center instance found in region: $region${NC}"
    echo -e "${BLUE}Would you like to create an IAM Identity Center instance? (yes/no) [default: no]:${NC}"
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            create_identity_center_instance "$region"
            return $?
            ;;
        *)
            echo -e "${RED}IAM Identity Center instance is required for this deployment.${NC}"
            echo "Please create an instance manually or run this script again and choose 'yes'."
            return 1
            ;;
    esac
}

# Function to generate a secure API key
generate_api_key() {
    # Generate a 32-character alphanumeric API key (sufficient for security)
    # Using /dev/urandom for cryptographically secure randomness
    local api_key=$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    echo "$api_key"
}

# Function to check for existing API key in Parameter Store
check_existing_api_key() {
    local stack_name=$1
    local region=$2
    local param_name="/kiro/$stack_name/api-key"
    
    echo -e "${BLUE}Checking for existing API key in Parameter Store: $param_name${NC}" >&2
    
    local existing_key=$(aws ssm get-parameter --name "$param_name" --with-decryption --query 'Parameter.Value' --output text --region "$region" 2>/dev/null || echo "")
    
    if [ -n "$existing_key" ] && [ "$existing_key" != "None" ]; then
        echo -e "${GREEN}Found existing API key in Parameter Store${NC}" >&2
        echo "$existing_key"  # This goes to stdout for capture
    else
        echo ""  # Return empty string if no key found
    fi
}

# Function to check CloudFormation stack status
check_stack_status() {
    local stack_name=$1
    local region=$2
    
    echo -e "${BLUE}Checking CloudFormation stack status: $stack_name${NC}" >&2
    
    local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST")
    
    echo "$stack_status"
}

# Function to handle failed stack deletion
handle_failed_stack() {
    local stack_name=$1
    local region=$2
    local stack_status=$3
    
    echo -e "${YELLOW}CloudFormation stack '$stack_name' is in a failed state: $stack_status${NC}"
    echo -e "${BLUE}Would you like to delete the failed stack and create a new one? (yes/no) [default: no]:${NC}"
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            echo -e "${YELLOW}Deleting failed stack: $stack_name${NC}"
            aws cloudformation delete-stack --stack-name "$stack_name" --region "$region"
            
            echo -e "${BLUE}Waiting for stack deletion to complete...${NC}"
            aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$region"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Stack deleted successfully${NC}"
                return 0
            else
                echo -e "${RED}Failed to delete stack${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}Cannot proceed with failed stack in place. Please resolve manually.${NC}"
            return 1
            ;;
    esac
}

# Function to handle existing successful stack
handle_existing_stack() {
    local stack_name=$1
    local region=$2
    
    echo -e "${GREEN}CloudFormation stack '$stack_name' already exists and is in a successful state${NC}"
    
    # If force update is enabled, skip prompt
    if [ "$FORCE_UPDATE" = true ]; then
        echo -e "${YELLOW}Force update enabled - proceeding with stack update...${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Would you like to update the existing stack? (yes/no) [default: yes]:${NC}"
    read -r response
    
    case "$response" in
        [nN]|[nN][oO])
            echo -e "${YELLOW}Skipping stack update. Showing current stack outputs...${NC}"
            return 2  # Special return code to skip deployment but show outputs
            ;;
        "")
            echo -e "${YELLOW}Proceeding with stack update (default)...${NC}"
            return 0
            ;;
        *)
            echo -e "${YELLOW}Proceeding with stack update...${NC}"
            return 0
            ;;
    esac
}

# Check if required parameters are provided
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: $0 [-f|--force-update] [identity-center-instance-arn] [api-key-value] [region]${NC}"
    echo ""
    echo "Options:"
    echo "  -f, --force-update    Skip all prompts and force stack update"
    echo ""
    echo "Parameters:"
    echo "  identity-center-instance-arn  ARN of IAM Identity Center instance (optional)"
    echo "  api-key-value                 Custom API key (optional, auto-generated if not provided)"
    echo "  region                        AWS region (optional, defaults to us-east-1)"
    echo ""
    echo "If identity-center-instance-arn is not provided, the script will check for existing instances"
    echo "If no instances are found, you'll be prompted to create one"
    echo "If api-key-value is not provided, a secure 32-character key will be auto-generated"
    echo ""
    echo "Examples:"
    echo "  $0  # Interactive mode"
    echo "  $0 -f  # Force update mode (no prompts)"
    echo "  $0 arn:aws:sso:::instance/ssoins-xxxxx  # With specific instance"
    echo "  $0 -f arn:aws:sso:::instance/ssoins-xxxxx  # Force update with specific instance"
fi

# Set region (parameter 1, 2, or 3 depending on whether flag was used, or default)
REGION=${3:-$DEFAULT_REGION}
echo -e "${BLUE}Using region: $REGION${NC}"

# Handle Identity Center Instance ARN (parameter 1 or 2 depending on flag)
if [ -z "$1" ]; then
    # No instance ARN provided, check for existing instances
    IDENTITY_CENTER_INSTANCE_ARN=$(check_identity_center_instances "$REGION")
    
    if [ -z "$IDENTITY_CENTER_INSTANCE_ARN" ]; then
        # No instances found, prompt to create one
        IDENTITY_CENTER_INSTANCE_ARN=$(prompt_for_identity_center_creation "$REGION")
        if [ $? -ne 0 ] || [ -z "$IDENTITY_CENTER_INSTANCE_ARN" ]; then
            exit 1
        fi
    else
        echo -e "${GREEN}Using existing Identity Center instance: $IDENTITY_CENTER_INSTANCE_ARN${NC}"
    fi
else
    IDENTITY_CENTER_INSTANCE_ARN=$1
    echo -e "${GREEN}Using provided Identity Center instance: $IDENTITY_CENTER_INSTANCE_ARN${NC}"
fi

STACK_NAME="kiro-user-management-api"

# Check CloudFormation stack status
STACK_STATUS=$(check_stack_status "$STACK_NAME" "$REGION")
SKIP_DEPLOYMENT=false

case "$STACK_STATUS" in
    "DOES_NOT_EXIST")
        echo -e "${BLUE}No existing CloudFormation stack found. Will create new stack.${NC}"
        ;;
    "CREATE_COMPLETE"|"UPDATE_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
        set +e  # Temporarily disable exit on error for function call
        handle_existing_stack "$STACK_NAME" "$REGION"
        HANDLE_RESULT=$?
        set -e  # Re-enable exit on error
        case $HANDLE_RESULT in
            0)
                echo -e "${YELLOW}Will proceed with stack update${NC}"
                ;;
            2)
                SKIP_DEPLOYMENT=true
                ;;
        esac
        ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_FAILED"|"DELETE_FAILED")
        handle_failed_stack "$STACK_NAME" "$REGION" "$STACK_STATUS"
        if [ $? -ne 0 ]; then
            exit 1
        fi
        ;;
    *)
        echo -e "${RED}Stack is in an unexpected state: $STACK_STATUS${NC}"
        echo -e "${YELLOW}Please check the stack manually in the AWS Console${NC}"
        exit 1
        ;;
esac

# Handle API Key - check Parameter Store first if no key provided
if [ -z "$2" ]; then
    # Check if API key already exists in Parameter Store
    EXISTING_API_KEY=$(check_existing_api_key "$STACK_NAME" "$REGION")
    
    if [ -n "$EXISTING_API_KEY" ]; then
        API_KEY_VALUE="$EXISTING_API_KEY"
        echo -e "${GREEN}Using existing API key from Parameter Store${NC}"
    else
        # Only generate new key if we're not skipping deployment
        if [ "$SKIP_DEPLOYMENT" != true ]; then
            echo -e "${BLUE}No existing API key found. Generating a secure API key...${NC}"
            API_KEY_VALUE=$(generate_api_key)
            echo -e "${GREEN}Generated secure API key: ${YELLOW}$API_KEY_VALUE${NC}"
            echo -e "${BLUE}This API key will be stored securely in AWS Parameter Store.${NC}"
            echo -e "${YELLOW}Please save this API key - you'll need it to access the API!${NC}"
            echo ""
        else
            # For skip deployment, we still need the existing key for display
            API_KEY_VALUE="$EXISTING_API_KEY"
        fi
    fi
else
    API_KEY_VALUE=$2
    echo -e "${GREEN}Using provided API key${NC}"
fi

# Validate API key length (minimum 20 characters for security) - only if we have a key
if [ -n "$API_KEY_VALUE" ] && [ ${#API_KEY_VALUE} -lt 20 ]; then
    echo -e "${RED}API key must be at least 20 characters long (current: ${#API_KEY_VALUE} characters)${NC}"
    exit 1
fi

# Deploy or skip based on stack status
if [ "$SKIP_DEPLOYMENT" = true ]; then
    echo -e "${YELLOW}Skipping deployment as requested. Showing current stack information...${NC}"
    DEPLOYMENT_SUCCESS=true
else
    echo -e "${YELLOW}Deploying CloudFormation stack: $STACK_NAME${NC}"
    echo -e "${BLUE}API key will be stored in Parameter Store as: /kiro/$STACK_NAME/api-key${NC}"

    # Deploy the stack using pure CloudFormation
    aws cloudformation deploy \
        --template-file template.yaml \
        --stack-name $STACK_NAME \
        --parameter-overrides \
            IdentityCenterInstanceArn=$IDENTITY_CENTER_INSTANCE_ARN \
            ApiKeyValue=$API_KEY_VALUE \
        --capabilities CAPABILITY_IAM \
        --region $REGION

    if [ $? -ne 0 ]; then
        echo -e "${RED}Deployment failed!${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Deployment successful!${NC}"
    DEPLOYMENT_SUCCESS=true
fi

# Show outputs if deployment was successful or skipped
if [ "$DEPLOYMENT_SUCCESS" = true ]; then
    
# Get outputs
echo -e "${YELLOW}Getting stack outputs...${NC}"
aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo -e "${GREEN}Setup complete!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Copy the API endpoint URL from the 'ApiEndpoint' output above"
echo "2. Your API key is stored securely in Parameter Store and shown below"
echo "3. Test the API using: python3 test_api.py <api-endpoint> <api-key>"
echo "4. The Lambda function will automatically create the 'Kiro Pro' group if it doesn't exist"
echo ""
echo -e "${GREEN}=== API CREDENTIALS ===${NC}"
echo -e "${YELLOW}API Key: ${GREEN}$API_KEY_VALUE${NC}"
echo -e "${BLUE}Parameter Store Location: /kiro/$STACK_NAME/api-key${NC}"
echo ""
echo -e "${YELLOW}To retrieve your API key later:${NC}"
echo "aws ssm get-parameter --name /kiro/$STACK_NAME/api-key --with-decryption --query 'Parameter.Value' --output text --region $REGION"
fi

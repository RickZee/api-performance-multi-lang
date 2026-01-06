#!/bin/bash
# Load environment variables from Terraform outputs
# Supports both DSQL and Aurora PostgreSQL

set -e

TERRAFORM_DIR="${1:-../../terraform}"
DATABASE_TYPE="${DATABASE_TYPE:-dsql}"  # Default to dsql for backward compatibility

if [ ! -d "$TERRAFORM_DIR" ]; then
    echo "Error: Terraform directory not found: $TERRAFORM_DIR"
    exit 1
fi

echo "Loading environment variables from Terraform outputs..."
echo "Terraform directory: $TERRAFORM_DIR"
echo "Database type: $DATABASE_TYPE"
echo ""

cd "$TERRAFORM_DIR"

# Get common Terraform outputs
TEST_RUNNER_INSTANCE_ID=$(terraform output -raw dsql_test_runner_instance_id 2>/dev/null || echo "")
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Determine which database to use
# Check if DATABASE_TYPE is explicitly set, otherwise auto-detect
if [ "$DATABASE_TYPE" = "auto" ] || [ -z "$DATABASE_TYPE" ]; then
    # Auto-detect: check which database is enabled
    AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
    
    if [ -n "$AURORA_ENDPOINT" ] && [ -z "$DSQL_HOST" ]; then
        DATABASE_TYPE="aurora"
    elif [ -n "$DSQL_HOST" ]; then
        DATABASE_TYPE="dsql"
    else
        echo "Warning: Could not auto-detect database type. Defaulting to dsql."
        DATABASE_TYPE="dsql"
    fi
fi

# Load database-specific variables
if [ "$DATABASE_TYPE" = "aurora" ]; then
    # Aurora configuration
    AURORA_HOST=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
    AURORA_PORT=$(terraform output -raw aurora_port 2>/dev/null || echo "5432")
    DATABASE_NAME=$(terraform output -raw aurora_database_name 2>/dev/null || terraform output -raw database_name 2>/dev/null || echo "car_entities")
    
    # Note: Password must come from terraform variables, not outputs (sensitive)
    # Check if password is already set in environment
    if [ -z "$AURORA_PASSWORD" ]; then
        echo "Warning: AURORA_PASSWORD not set. You may need to set it manually:"
        echo "  export AURORA_PASSWORD=\$(terraform output -raw aurora_connection_string | grep -oP '://[^:]+:\K[^@]+' || echo '')"
        echo "  Or set it from terraform variables:"
        echo "  export AURORA_PASSWORD=\$(terraform output -raw database_password 2>/dev/null || echo '')"
        echo ""
    fi
    
    # Username from terraform (may be sensitive)
    if [ -z "$AURORA_USERNAME" ]; then
        AURORA_USERNAME=$(terraform output -raw aurora_master_username 2>/dev/null || terraform output -raw database_user 2>/dev/null || echo "postgres")
    fi
    
    # Check required values
    if [ -z "$AURORA_HOST" ] || [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$S3_BUCKET" ]; then
        echo "Error: Could not get all required values from Terraform for Aurora"
        echo ""
        echo "Got:"
        echo "  AURORA_HOST: ${AURORA_HOST:-NOT FOUND}"
        echo "  TEST_RUNNER_INSTANCE_ID: ${TEST_RUNNER_INSTANCE_ID:-NOT FOUND}"
        echo "  S3_BUCKET: ${S3_BUCKET:-NOT FOUND}"
        echo ""
        echo "Make sure Terraform is initialized and Aurora is enabled:"
        echo "  cd $TERRAFORM_DIR"
        echo "  terraform output"
        exit 1
    fi
    
    # Export Aurora variables
    export DATABASE_TYPE="aurora"
    export AURORA_HOST
    export AURORA_ENDPOINT="$AURORA_HOST"  # Support both names
    export AURORA_PORT
    export DATABASE_NAME
    if [ -n "$AURORA_USERNAME" ]; then
        export AURORA_USERNAME
    fi
    
    echo "✓ Environment variables loaded (Aurora):"
    echo "  DATABASE_TYPE=aurora"
    echo "  AURORA_HOST=$AURORA_HOST"
    echo "  AURORA_PORT=$AURORA_PORT"
    echo "  DATABASE_NAME=$DATABASE_NAME"
    if [ -n "$AURORA_USERNAME" ]; then
        echo "  AURORA_USERNAME=$AURORA_USERNAME"
    fi
    if [ -n "$AURORA_PASSWORD" ]; then
        echo "  AURORA_PASSWORD=*** (set)"
    else
        echo "  AURORA_PASSWORD=*** (NOT SET - please set manually)"
    fi
else
    # DSQL configuration (default)
    DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")
    
    # Check required values
    if [ -z "$DSQL_HOST" ] || [ -z "$TEST_RUNNER_INSTANCE_ID" ] || [ -z "$S3_BUCKET" ]; then
        echo "Error: Could not get all required values from Terraform for DSQL"
        echo ""
        echo "Got:"
        echo "  DSQL_HOST: ${DSQL_HOST:-NOT FOUND}"
        echo "  TEST_RUNNER_INSTANCE_ID: ${TEST_RUNNER_INSTANCE_ID:-NOT FOUND}"
        echo "  S3_BUCKET: ${S3_BUCKET:-NOT FOUND}"
        echo ""
        echo "Make sure Terraform is initialized and outputs are available:"
        echo "  cd $TERRAFORM_DIR"
        echo "  terraform output"
        exit 1
    fi
    
    # Export DSQL variables
    export DATABASE_TYPE="dsql"
    export DSQL_HOST
    export IAM_USERNAME="lambda_dsql_user"  # Default IAM username
    export DATABASE_NAME="postgres"  # Default DSQL database name
    
    echo "✓ Environment variables loaded (DSQL):"
    echo "  DATABASE_TYPE=dsql"
    echo "  DSQL_HOST=$DSQL_HOST"
    echo "  IAM_USERNAME=$IAM_USERNAME"
    echo "  DATABASE_NAME=$DATABASE_NAME"
fi

# Export common variables
export TEST_RUNNER_INSTANCE_ID
export S3_BUCKET
export AWS_REGION

echo "  TEST_RUNNER_INSTANCE_ID=$TEST_RUNNER_INSTANCE_ID"
echo "  S3_BUCKET=$S3_BUCKET"
echo "  AWS_REGION=$AWS_REGION"
echo ""

# Return to original directory
cd - > /dev/null

# If script was sourced, variables are already exported
# If script was executed, we need to pass them to the parent
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # Script was executed (not sourced)
    echo "To use these variables, source this script:"
    echo "  source scripts/load_env_from_terraform.sh"
    echo ""
    echo "Or run with eval:"
    echo "  eval \$(scripts/load_env_from_terraform.sh)"
else
    # Script was sourced, variables are already exported
    echo "✓ Variables exported to current shell"
fi


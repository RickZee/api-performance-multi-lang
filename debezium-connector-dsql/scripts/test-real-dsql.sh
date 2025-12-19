#!/bin/bash
# Script to run real DSQL integration tests
# Sources .env.dsql file and runs tests tagged with "real-dsql"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=========================================="
echo "Real DSQL Integration Tests"
echo "=========================================="
echo ""

# Source .env.dsql if it exists
ENV_FILE=".env.dsql"
if [ -f "$ENV_FILE" ]; then
    echo "✓ Found $ENV_FILE, sourcing..."
    set -a  # Automatically export all variables
    source "$ENV_FILE"
    set +a
    echo ""
else
    echo "⚠ Warning: $ENV_FILE not found"
    echo "  Tests will use environment variables already set in your shell"
    echo "  To create the file: cp .env.dsql.example .env.dsql"
    echo "  Then edit .env.dsql with your DSQL configuration"
    echo ""
fi

# Validate required environment variables
REQUIRED_VARS=(
    "DSQL_ENDPOINT_PRIMARY"
    "DSQL_DATABASE_NAME"
    "DSQL_REGION"
    "DSQL_IAM_USERNAME"
    "DSQL_TABLES"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "✗ Error: Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "    - $var"
    done
    echo ""
    echo "Please set these variables or create .env.dsql file"
    exit 1
fi

echo "✓ Required environment variables are set"
echo ""

# Validate AWS credentials
echo "Checking AWS credentials..."
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "✓ AWS credentials found in environment variables"
elif [ -f "$HOME/.aws/credentials" ]; then
    echo "✓ AWS credentials file found at ~/.aws/credentials"
    if [ -n "$AWS_PROFILE" ]; then
        echo "  Using profile: $AWS_PROFILE"
    else
        echo "  Using default profile"
    fi
else
    echo "⚠ Warning: AWS credentials not found"
    echo "  The connector will try to use IAM role if running on EC2/ECS/EKS"
    echo "  For local testing, set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    echo "  or configure ~/.aws/credentials"
fi
echo ""

# Run connection validation first (optional, but recommended)
if [ -f "scripts/validate-dsql-connection.sh" ]; then
    echo "Running connection validation..."
    if ./scripts/validate-dsql-connection.sh; then
        echo "✓ Connection validation passed"
        echo ""
    else
        echo "⚠ Connection validation failed, but continuing with tests..."
        echo ""
    fi
fi

# Run tests
echo "Running real DSQL integration tests..."
echo ""

./gradlew testRealDsql "$@"

EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo ""
    echo "=========================================="
    echo "✓ All tests passed!"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "✗ Some tests failed"
    echo "=========================================="
fi

exit $EXIT_CODE

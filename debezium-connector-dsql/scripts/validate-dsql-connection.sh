#!/bin/bash
# Standalone script to validate DSQL connection
# Tests IAM token generation, database connection, and table validation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=========================================="
echo "DSQL Connection Validation"
echo "=========================================="
echo ""

# Source .env.dsql if it exists
ENV_FILE=".env.dsql"
if [ -f "$ENV_FILE" ]; then
    echo "✓ Found $ENV_FILE, sourcing..."
    set -a
    source "$ENV_FILE"
    set +a
    echo ""
else
    echo "⚠ Warning: $ENV_FILE not found"
    echo "  Using environment variables already set in your shell"
    echo ""
fi

# Check required variables
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

echo "Configuration:"
echo "  Primary Endpoint: $DSQL_ENDPOINT_PRIMARY"
echo "  Database: $DSQL_DATABASE_NAME"
echo "  Region: $DSQL_REGION"
echo "  IAM Username: $DSQL_IAM_USERNAME"
echo "  Tables: $DSQL_TABLES"
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "✓ AWS credentials found in environment variables"
elif [ -f "$HOME/.aws/credentials" ]; then
    echo "✓ AWS credentials file found"
else
    echo "✗ Error: AWS credentials not found"
    echo "  Please set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY"
    echo "  or configure ~/.aws/credentials"
    exit 1
fi
echo ""

# Run Java validation utility
echo "Running connection tests..."
echo ""

# Compile test classes if needed
./gradlew compileTestJava > /dev/null 2>&1 || true

# Run the connection tester
./gradlew test --tests "io.debezium.connector.dsql.testutil.DsqlConnectionTester" \
    --tests "*" 2>&1 | grep -v "BUILD" | grep -v "Task" || {
    
    # If gradle test doesn't work, try running a simple Java class
    echo "Running connection validation via Java..."
    
    java -cp "$(./gradlew -q printClasspath 2>/dev/null || echo 'build/classes/java/test:build/classes/java/main')" \
        -DDSQL_ENDPOINT_PRIMARY="$DSQL_ENDPOINT_PRIMARY" \
        -DDSQL_DATABASE_NAME="$DSQL_DATABASE_NAME" \
        -DDSQL_REGION="$DSQL_REGION" \
        -DDSQL_IAM_USERNAME="$DSQL_IAM_USERNAME" \
        -DDSQL_TABLES="$DSQL_TABLES" \
        io.debezium.connector.dsql.testutil.DsqlConnectionTester 2>&1 || {
        
        echo ""
        echo "⚠ Could not run automated validation"
        echo "  You can manually test by running:"
        echo "    source .env.dsql"
        echo "    ./gradlew testRealDsql"
        exit 1
    }
}

echo ""
echo "=========================================="
echo "✓ Connection validation complete"
echo "=========================================="

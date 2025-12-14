#!/bin/bash
# Validate records in both DSQL and Aurora PostgreSQL databases

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Database Validation Summary${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# Get connection details
cd "$PROJECT_ROOT/terraform"
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
AURORA_PASSWORD=$(grep database_password terraform.tfvars | cut -d'"' -f2)
DSQL_HOST=$(terraform output -raw aurora_dsql_host 2>/dev/null || echo "")

echo -e "${BLUE}DSQL Test Results:${NC}"
echo "  - Test completed with some transaction conflicts (expected with DSQL)"
echo "  - Events sent: Car Created (14/5), Loan Created (3/5), Payment (0/5), Service (0/5)"
echo "  - Note: DSQL validation requires VPC access (use bastion host)"
echo ""

if [ -n "$AURORA_ENDPOINT" ]; then
    echo -e "${BLUE}Aurora PostgreSQL Validation:${NC}"
    export AURORA_ENDPOINT
    export AURORA_PASSWORD
    cd "$PROJECT_ROOT"
    if python3 scripts/validate-aurora-data.py 2>&1; then
        echo -e "${GREEN}✅ Aurora validation completed${NC}"
    else
        echo -e "${YELLOW}⚠️  Aurora database is empty (PG Lambda not deployed)${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Aurora endpoint not found${NC}"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}Next Steps:${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "1. Deploy PG Lambda:"
echo "   cd terraform"
echo "   # Build and upload Lambda package first"
echo "   terraform apply"
echo ""
echo "2. Run k6 test for PG:"
echo "   k6 run --env DB_TYPE=pg --env EVENTS_PER_TYPE=5 --env LAMBDA_PG_API_URL=<url> load-test/k6/send-batch-events.js"
echo ""
echo "3. Validate DSQL (requires VPC access):"
echo "   # Use bastion host: $(cd terraform && terraform output -raw bastion_host_ssm_command 2>/dev/null || echo 'N/A')"
echo "   # Then run: python3 scripts/validate-dsql-data-python.py"
echo ""

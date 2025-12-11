#!/bin/bash
# Validate database connection helper script
# Tests PostgreSQL connectivity with provided credentials

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print usage
usage() {
    echo "Usage: $0 --endpoint <endpoint> --user <user> --password <password> [--database <database>]"
    echo ""
    echo "Options:"
    echo "  --endpoint    Aurora/Postgres endpoint (hostname:port or just hostname)"
    echo "  --user        Database username"
    echo "  --password    Database password"
    echo "  --database    Database name (default: car_entities)"
    echo "  --timeout     Connection timeout in seconds (default: 10)"
    exit 1
}

# Parse arguments
ENDPOINT=""
USER=""
PASSWORD=""
DATABASE="car_entities"
TIMEOUT=10

while [[ $# -gt 0 ]]; do
    case $1 in
        --endpoint)
            ENDPOINT="$2"
            shift 2
            ;;
        --user)
            USER="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$ENDPOINT" ] || [ -z "$USER" ] || [ -z "$PASSWORD" ]; then
    echo -e "${RED}✗ Missing required arguments${NC}"
    usage
fi

# Extract host and port from endpoint
if [[ "$ENDPOINT" == *:* ]]; then
    HOST=$(echo "$ENDPOINT" | cut -d: -f1)
    PORT=$(echo "$ENDPOINT" | cut -d: -f2)
else
    HOST="$ENDPOINT"
    PORT="5432"
fi

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo -e "${YELLOW}⚠ psql not found, trying alternative connection test...${NC}"
    
    # Try using Python if available
    if command -v python3 &> /dev/null; then
        python3 << EOF
import sys
import psycopg2
from psycopg2 import OperationalError
import time

try:
    conn = psycopg2.connect(
        host="${HOST}",
        port=${PORT},
        database="${DATABASE}",
        user="${USER}",
        password="${PASSWORD}",
        connect_timeout=${TIMEOUT}
    )
    conn.close()
    print("Connection successful")
    sys.exit(0)
except OperationalError as e:
    print(f"Connection failed: {e}")
    sys.exit(1)
EOF
        exit $?
    else
        # Try using nc (netcat) for basic port connectivity
        echo -e "${BLUE}Testing port connectivity...${NC}"
        if timeout "$TIMEOUT" nc -z "$HOST" "$PORT" 2>/dev/null; then
            echo -e "${GREEN}✓ Port $PORT is reachable${NC}"
            echo -e "${YELLOW}⚠ Cannot test authentication without psql or python3${NC}"
            exit 0
        else
            echo -e "${RED}✗ Cannot reach $HOST:$PORT${NC}"
            exit 1
        fi
    fi
else
    # Use psql for full connection test
    echo -e "${BLUE}Testing database connection to $HOST:$PORT/$DATABASE as $USER...${NC}"
    
    export PGPASSWORD="$PASSWORD"
    
    if psql -h "$HOST" -p "$PORT" -U "$USER" -d "$DATABASE" -c "SELECT 1;" -t -q -w --connect-timeout="$TIMEOUT" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Database connection successful${NC}"
        unset PGPASSWORD
        exit 0
    else
        echo -e "${RED}✗ Database connection failed${NC}"
        unset PGPASSWORD
        exit 1
    fi
fi

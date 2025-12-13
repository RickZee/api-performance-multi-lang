#!/bin/bash
# Start FastAPI with dockerized PostgreSQL

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Starting FastAPI with PostgreSQL${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running${NC}"
    exit 1
fi

# Start PostgreSQL
echo -e "${BLUE}Step 1: Starting PostgreSQL database...${NC}"
cd "$PROJECT_ROOT/producer-api-python-rest-lambda"
docker-compose up -d postgres

# Wait for PostgreSQL to be ready
echo -e "${BLUE}Waiting for PostgreSQL to be ready...${NC}"
timeout=30
counter=0
while ! docker exec car_dealership_db pg_isready -U postgres &> /dev/null; do
    sleep 1
    counter=$((counter + 1))
    if [ $counter -ge $timeout ]; then
        echo -e "${RED}✗ PostgreSQL failed to start${NC}"
        exit 1
    fi
done
echo -e "${GREEN}✓ PostgreSQL is ready${NC}"
echo ""

# Setup Python virtual environment if needed
echo -e "${BLUE}Step 2: Setting up Python environment...${NC}"
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

# Activate virtual environment and install dependencies
source venv/bin/activate
if ! python -c "import uvicorn" &> /dev/null; then
    echo -e "${BLUE}Installing dependencies...${NC}"
    pip install -q -r requirements.txt
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${GREEN}✓ Dependencies already installed${NC}"
fi
echo ""

# Start FastAPI
echo -e "${BLUE}Step 3: Starting FastAPI...${NC}"
echo -e "${BLUE}API will be available at: http://localhost:3000${NC}"
echo -e "${BLUE}Press Ctrl+C to stop${NC}"
echo ""

# Export environment variables
export DATABASE_URL="postgresql://postgres:postgres@localhost:5432/car_dealership"
export LOG_LEVEL="info"

# Start FastAPI with Uvicorn
echo -e "${BLUE}Starting FastAPI on port 3000...${NC}"
python -m uvicorn app:app --host 0.0.0.0 --port 3000


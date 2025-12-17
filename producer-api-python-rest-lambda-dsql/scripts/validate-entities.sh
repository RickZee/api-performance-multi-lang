#!/bin/bash
# Validate entities in the database

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Validating Entities in Database${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if PostgreSQL container is running
if ! docker ps | grep -q car_dealership_db; then
    echo -e "${RED}✗ PostgreSQL container is not running${NC}"
    echo "  Start it with: docker-compose up -d postgres"
    exit 1
fi

echo -e "${BLUE}Querying database...${NC}"
echo ""

# Query business_events
BUSINESS_EVENTS_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM business_events;" | tr -d ' ')

# Query event_headers
EVENT_HEADERS_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM event_headers;" | tr -d ' ')

# Query entity tables
CAR_ENTITIES_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM car_entities;" | tr -d ' ')
LOAN_ENTITIES_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM loan_entities;" | tr -d ' ')
LOAN_PAYMENT_ENTITIES_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM loan_payment_entities;" | tr -d ' ')
SERVICE_RECORD_ENTITIES_COUNT=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM service_record_entities;" | tr -d ' ')

# Display results
echo -e "${CYAN}Database: car_dealership${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "Business Events:     ${GREEN}${BUSINESS_EVENTS_COUNT}${NC}"
echo -e "Event Headers:      ${GREEN}${EVENT_HEADERS_COUNT}${NC}"
echo -e "Car Entities:       ${GREEN}${CAR_ENTITIES_COUNT}${NC}"
echo -e "Loan Entities:      ${GREEN}${LOAN_ENTITIES_COUNT}${NC}"
echo -e "Loan Payment Entities: ${GREEN}${LOAN_PAYMENT_ENTITIES_COUNT}${NC}"
echo -e "Service Record Entities: ${GREEN}${SERVICE_RECORD_ENTITIES_COUNT}${NC}"
echo ""

# Show sample entities
if [ "$CAR_ENTITIES_COUNT" -gt 0 ]; then
    echo -e "${CYAN}Sample Car Entity:${NC}"
    docker exec car_dealership_db psql -U postgres -d car_dealership -c "SELECT entity_id, entity_type, created_at FROM car_entities LIMIT 1;" 2>/dev/null | head -5
    echo ""
fi

if [ "$LOAN_ENTITIES_COUNT" -gt 0 ]; then
    echo -e "${CYAN}Sample Loan Entity:${NC}"
    docker exec car_dealership_db psql -U postgres -d car_dealership -c "SELECT entity_id, entity_type, created_at FROM loan_entities LIMIT 1;" 2>/dev/null | head -5
    echo ""
fi

# Validate foreign key relationships
echo -e "${CYAN}Validating Foreign Key Relationships:${NC}"
EVENT_HEADERS_WITH_FK=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM event_headers e WHERE EXISTS (SELECT 1 FROM business_events b WHERE b.id = e.id);" | tr -d ' ')
ENTITIES_WITH_FK=$(docker exec car_dealership_db psql -U postgres -d car_dealership -t -c "SELECT COUNT(*) FROM (SELECT event_id FROM car_entities UNION SELECT event_id FROM loan_entities UNION SELECT event_id FROM loan_payment_entities UNION SELECT event_id FROM service_record_entities) e WHERE e.event_id IS NOT NULL AND EXISTS (SELECT 1 FROM event_headers h WHERE h.id = e.event_id);" | tr -d ' ')

if [ "$EVENT_HEADERS_COUNT" -gt 0 ]; then
    if [ "$EVENT_HEADERS_WITH_FK" -eq "$EVENT_HEADERS_COUNT" ]; then
        echo -e "${GREEN}✓ All event_headers have valid foreign keys to business_events${NC}"
    else
        echo -e "${YELLOW}⚠ Some event_headers are missing foreign key relationships${NC}"
    fi
fi

if [ "$ENTITIES_WITH_FK" -gt 0 ]; then
    echo -e "${GREEN}✓ Entity foreign key relationships validated${NC}"
fi

echo ""
echo -e "${GREEN}✓ Validation complete${NC}"

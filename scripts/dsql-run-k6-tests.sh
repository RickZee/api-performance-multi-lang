#!/bin/bash
# Run k6 tests against DSQL Lambda API from EC2
# Usage: ./dsql-run-k6-tests.sh [EVENTS_PER_TYPE] [VUS_PER_EVENT_TYPE]

set -e

# Configuration
DSQL_API_URL="https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"
DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
AWS_REGION="us-east-1"

# Test parameters (configurable via arguments)
EVENTS_PER_TYPE=${1:-10}
VUS_PER_EVENT_TYPE=${2:-1}

echo "=== DSQL Lambda API Load Test ==="
echo "API URL: $DSQL_API_URL"
echo "Events per type: $EVENTS_PER_TYPE"
echo "VUs per event type: $VUS_PER_EVENT_TYPE"
echo ""

# Clone repo if not present
if [ ! -d "api-performance-multi-lang" ]; then
    echo "Cloning repository..."
    git clone --depth 1 https://github.com/yourusername/api-performance-multi-lang.git 2>/dev/null || {
        echo "Repository not found. Creating k6 test script locally..."
        mkdir -p api-performance-multi-lang/load-test/k6
    }
fi

# Create k6 test script if not present
if [ ! -f "api-performance-multi-lang/load-test/k6/send-batch-events.js" ]; then
    echo "Creating k6 test script..."
    cat > api-performance-multi-lang/load-test/k6/send-batch-events.js << 'K6EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

// Configuration
const EVENTS_PER_TYPE = parseInt(__ENV.EVENTS_PER_TYPE || '5', 10);
const VUS_PER_EVENT_TYPE = parseInt(__ENV.VUS_PER_EVENT_TYPE || '1', 10);
const NUM_EVENT_TYPES = 4;
const TOTAL_VUS = VUS_PER_EVENT_TYPE * NUM_EVENT_TYPES;
const EVENTS_PER_VU = Math.ceil(EVENTS_PER_TYPE / VUS_PER_EVENT_TYPE);

// Get API URL
const apiUrl = (__ENV.API_URL || 'https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com').replace(/\/$/, '') + '/api/v1/events';

export const options = {
    vus: TOTAL_VUS,
    iterations: EVENTS_PER_VU * TOTAL_VUS,
    thresholds: {
        'http_req_failed': ['rate<0.5'],
    },
};

// Metrics
const successCounter = new Counter('events_success');
const failCounter = new Counter('events_failed');
const successRate = new Rate('success_rate');

// Event types
const eventTypes = ['Car Created', 'Loan Created', 'Loan Payment Submitted', 'Car Service Done'];

function generateUUID() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        const r = Math.random() * 16 | 0;
        const v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

function generateEvent(eventType) {
    const now = new Date().toISOString();
    const uuid = generateUUID();
    
    const baseEvent = {
        eventHeader: {
            uuid: uuid,
            eventName: eventType,
            eventType: eventType.replace(/ /g, '_').toUpperCase(),
            createdDate: now,
            savedDate: now,
        },
        entities: []
    };
    
    switch(eventType) {
        case 'Car Created':
            baseEvent.entities.push({
                entityHeader: {
                    entityId: generateUUID(),
                    entityType: 'CAR',
                    createdAt: now,
                    updatedAt: now,
                },
                make: 'Toyota',
                model: 'Camry',
                year: 2024,
                vin: `VIN${Date.now()}`,
            });
            break;
        case 'Loan Created':
            baseEvent.entities.push({
                entityHeader: {
                    entityId: generateUUID(),
                    entityType: 'LOAN',
                    createdAt: now,
                    updatedAt: now,
                },
                loanAmount: 25000,
                interestRate: 5.5,
                termMonths: 60,
            });
            break;
        case 'Loan Payment Submitted':
            baseEvent.entities.push({
                entityHeader: {
                    entityId: generateUUID(),
                    entityType: 'LOAN_PAYMENT',
                    createdAt: now,
                    updatedAt: now,
                },
                paymentAmount: 500,
                paymentDate: now,
            });
            break;
        case 'Car Service Done':
            baseEvent.entities.push({
                entityHeader: {
                    entityId: generateUUID(),
                    entityType: 'SERVICE_RECORD',
                    createdAt: now,
                    updatedAt: now,
                },
                serviceType: 'Oil Change',
                mileage: 15000,
                cost: 75.00,
            });
            break;
    }
    
    return baseEvent;
}

export default function() {
    const vuId = __VU - 1;
    const eventTypeIndex = vuId % NUM_EVENT_TYPES;
    const eventType = eventTypes[eventTypeIndex];
    
    const event = generateEvent(eventType);
    
    const res = http.post(apiUrl, JSON.stringify(event), {
        headers: { 'Content-Type': 'application/json' },
    });
    
    const success = check(res, {
        'status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    });
    
    if (success) {
        successCounter.add(1);
        successRate.add(1);
    } else {
        failCounter.add(1);
        successRate.add(0);
        console.log(`Failed: ${eventType} - Status: ${res.status} - Body: ${res.body.substring(0, 200)}`);
    }
}

export function handleSummary(data) {
    const successCount = data.metrics.events_success ? data.metrics.events_success.values.count : 0;
    const failCount = data.metrics.events_failed ? data.metrics.events_failed.values.count : 0;
    const total = successCount + failCount;
    
    return {
        'stdout': `
=== DSQL Lambda API Test Results ===
Total Events: ${total}
Successful: ${successCount}
Failed: ${failCount}
Success Rate: ${total > 0 ? ((successCount / total) * 100).toFixed(2) : 0}%
`,
    };
}
K6EOF
fi

# Run k6 test
echo "Running k6 test..."
cd api-performance-multi-lang
k6 run \
    --env API_URL=$DSQL_API_URL \
    --env EVENTS_PER_TYPE=$EVENTS_PER_TYPE \
    --env VUS_PER_EVENT_TYPE=$VUS_PER_EVENT_TYPE \
    load-test/k6/send-batch-events.js

# Verify data in DSQL
echo ""
echo "=== Verifying data in DSQL ==="
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
psql -h $DSQL_HOST -U admin -d car_entities -p 5432 << 'EOF'
SELECT 'business_events' as table_name, COUNT(*) as count FROM business_events
UNION ALL
SELECT 'event_headers', COUNT(*) FROM event_headers
UNION ALL
SELECT 'car_entities', COUNT(*) FROM car_entities
UNION ALL
SELECT 'loan_entities', COUNT(*) FROM loan_entities
UNION ALL
SELECT 'loan_payment_entities', COUNT(*) FROM loan_payment_entities
UNION ALL
SELECT 'service_record_entities', COUNT(*) FROM service_record_entities
ORDER BY table_name;
EOF


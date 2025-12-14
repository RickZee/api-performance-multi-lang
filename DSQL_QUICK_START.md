# DSQL Quick Start - Connect and Test

## Step 1: Connect to EC2

```bash
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1
```

## Step 2: Setup DSQL (Run on EC2)

Once connected, copy and paste this entire block:

```bash
# Set environment variables
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Create IAM database user
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'SQL'
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lambda_dsql_user') THEN
        CREATE ROLE lambda_dsql_user WITH LOGIN;
    END IF;
END $$;
GRANT rds_iam TO lambda_dsql_user;
\du
SQL

# Create database
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "CREATE DATABASE car_entities;" 2>/dev/null || echo "Database exists"

# Create tables
psql -h $DSQL_HOST -U admin -d car_entities -p 5432 << 'SQL'
CREATE TABLE IF NOT EXISTS business_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    event_data JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS event_headers (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    header_data JSONB NOT NULL,
    CONSTRAINT fk_event_headers_business_events 
        FOREIGN KEY (id) REFERENCES business_events(id) 
        ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS car_entities (
    entity_id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    entity_data JSONB NOT NULL,
    event_id VARCHAR(255),
    CONSTRAINT fk_car_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS loan_entities (
    entity_id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    entity_data JSONB NOT NULL,
    event_id VARCHAR(255),
    CONSTRAINT fk_loan_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS loan_payment_entities (
    entity_id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    entity_data JSONB NOT NULL,
    event_id VARCHAR(255),
    CONSTRAINT fk_loan_payment_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS service_record_entities (
    entity_id VARCHAR(255) PRIMARY KEY,
    entity_type VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE,
    entity_data JSONB NOT NULL,
    event_id VARCHAR(255),
    CONSTRAINT fk_service_record_entities_event_headers 
        FOREIGN KEY (event_id) REFERENCES event_headers(id) 
        ON DELETE SET NULL
);

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO lambda_dsql_user;
\dt
SQL

echo "✅ DSQL setup complete!"
```

## Step 3: Test Lambda API (From Your Local Machine)

```bash
# Test the Lambda API
curl -X POST https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{
    "eventHeader": {
      "uuid": "test-'$(date +%s)'",
      "eventName": "Car Created",
      "eventType": "CAR_CREATED",
      "createdDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
      "savedDate": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    },
    "entities": [{
      "entityHeader": {
        "entityId": "entity-test-'$(date +%s)'",
        "entityType": "CAR",
        "createdAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "updatedAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
      },
      "make": "Toyota",
      "model": "Camry",
      "year": 2024
    }]
  }'
```

## Step 4: Run k6 Tests (On EC2)

Back on the EC2 instance, create and run k6 test:

```bash
cat > /tmp/test-dsql.js << 'K6EOF'
import http from 'k6/http';
import { check } from 'k6';

const API_URL = 'https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com/api/v1/events';

export const options = {
    vus: 4,
    iterations: 10,
};

function generateEvent(eventType) {
    const now = new Date().toISOString();
    const uuid = `test-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    return {
        eventHeader: {
            uuid: uuid,
            eventName: eventType,
            eventType: eventType.replace(/ /g, '_').toUpperCase(),
            createdDate: now,
            savedDate: now,
        },
        entities: [{
            entityHeader: {
                entityId: `entity-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
                entityType: eventType.toUpperCase().substr(0, 4),
                createdAt: now,
                updatedAt: now,
            },
            testData: 'test'
        }]
    };
}

export default function() {
    const eventTypes = ['Car Created', 'Loan Created', 'Loan Payment Submitted', 'Car Service Done'];
    const eventType = eventTypes[__VU % 4];
    const event = generateEvent(eventType);
    
    const res = http.post(API_URL, JSON.stringify(event), {
        headers: { 'Content-Type': 'application/json' },
    });
    
    check(res, {
        'status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    });
}
K6EOF

# Run the test
k6 run /tmp/test-dsql.js
```

## Step 5: Verify Data in DSQL (On EC2)

```bash
# Regenerate token (expires after 15 minutes)
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Check table counts
psql -h $DSQL_HOST -U admin -d car_entities -p 5432 << 'SQL'
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

-- Check recent events
SELECT id, event_name, event_type, created_date 
FROM business_events 
ORDER BY created_date DESC 
LIMIT 10;
SQL
```

## Summary

✅ **Packages installed**: k6 and psql are ready  
✅ **S3 VPC endpoint**: Configured for S3 access  
✅ **SSM VPC endpoints**: Configured for SSM access  
⏳ **Next**: Run the setup commands above to create DSQL schema and test

## Quick Reference

- **EC2**: `i-058cb2a0dc3fdcf3b`
- **DSQL Host**: `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws`
- **Lambda API**: `https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com`
- **IAM User**: `lambda_dsql_user`
- **Database**: `car_entities`


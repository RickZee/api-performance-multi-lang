# DSQL Connect and Test Guide

## Quick Start: Connect to EC2

```bash
# Connect via SSM Session Manager
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1
```

## Step 1: Verify Setup Status

Once connected to the EC2 instance, check if setup completed:

```bash
# Check if packages are installed
which psql
which k6
k6 version

# Check if DSQL setup log exists
cat /tmp/dsql-setup.log 2>/dev/null || echo "Setup not run yet"
```

## Step 2: Run DSQL Setup (if not done)

If setup hasn't completed, run it manually:

```bash
# Set environment variables
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Test connection
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "SELECT version();"
```

### Create IAM Database User

```bash
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'EOF'
-- Create user if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lambda_dsql_user') THEN
        CREATE ROLE lambda_dsql_user WITH LOGIN;
        RAISE NOTICE 'Created user lambda_dsql_user';
    END IF;
END $$;

-- Grant IAM authentication
GRANT rds_iam TO lambda_dsql_user;
\du
EOF
```

### Create Database and Schema

```bash
# Create database
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "CREATE DATABASE car_entities;"

# Create tables (run the full schema from data/schema.sql)
psql -h $DSQL_HOST -U admin -d car_entities -p 5432 -f /tmp/schema.sql
```

Or create tables manually:

```bash
psql -h $DSQL_HOST -U admin -d car_entities -p 5432 << 'EOF'
-- Business Events Table
CREATE TABLE IF NOT EXISTS business_events (
    id VARCHAR(255) PRIMARY KEY,
    event_name VARCHAR(255) NOT NULL,
    event_type VARCHAR(255),
    created_date TIMESTAMP WITH TIME ZONE,
    saved_date TIMESTAMP WITH TIME ZONE,
    event_data JSONB NOT NULL
);

-- Event Headers Table
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

-- Car Entities Table
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

-- Loan Entities Table
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

-- Loan Payment Entities Table
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

-- Service Record Entities Table
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

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO lambda_dsql_user;

\dt
EOF
```

## Step 3: Download and Run k6 Tests

```bash
# Download k6 test script from S3
cd /tmp
aws s3 cp s3://producer-api-lambda-deployments-978300727880/scripts/send-batch-events.js .

# Or create a simple test script
cat > test-dsql-api.js << 'K6EOF'
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

# Run k6 test
k6 run --env EVENTS_PER_TYPE=10 test-dsql-api.js
```

## Step 4: Verify Data in DSQL

```bash
# Regenerate token (expires after 15 minutes)
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Check table counts
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

-- Check recent events
SELECT id, event_name, event_type, created_date 
FROM business_events 
ORDER BY created_date DESC 
LIMIT 10;
EOF
```

## Step 5: Test Lambda Connection

Verify the Lambda can now connect (it should work after creating the IAM user):

```bash
# From your local machine, test the Lambda API
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

## Troubleshooting

### Lambda Still Getting "Access Denied"

1. **Verify IAM user exists:**
   ```bash
   psql -h $DSQL_HOST -U admin -d postgres -c "SELECT usename FROM pg_user WHERE usename = 'lambda_dsql_user';"
   ```

2. **Check Lambda IAM permissions:**
   ```bash
   aws iam get-role-policy \
     --role-name producer-api-python-rest-lambda-dsql-execution-role \
     --policy-name producer-api-python-rest-lambda-dsql-dsql-auth-policy
   ```

3. **Check Lambda environment variables:**
   ```bash
   aws lambda get-function-configuration \
     --function-name producer-api-python-rest-lambda-dsql \
     --query 'Environment.Variables' | jq
   ```

### Connection Issues

- **"invalid sni"** - Fixed! Using DSQL_HOST environment variable
- **"access denied"** - IAM user doesn't exist or permissions wrong
- **"timeout"** - Security group or VPC endpoint issue

## Quick Reference

| Item | Value |
|------|-------|
| EC2 Instance ID | `i-058cb2a0dc3fdcf3b` |
| DSQL Host | `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws` |
| Lambda API URL | `https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com` |
| IAM Database User | `lambda_dsql_user` |
| Database Name | `car_entities` |


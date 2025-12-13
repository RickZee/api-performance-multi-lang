# DSQL EC2 Setup Guide

## Connect to EC2 via SSM

```bash
aws ssm start-session --target i-058cb2a0dc3fdcf3b --region us-east-1
```

## Step 1: Install PostgreSQL Client

```bash
# For Amazon Linux 2023
sudo dnf install -y postgresql15

# OR for Amazon Linux 2
sudo amazon-linux-extras install postgresql14 -y
```

## Step 2: Install k6

```bash
# Install k6 from releases
curl -L https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz | tar xz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
k6 version
```

## Step 3: Setup DSQL

```bash
# Set environment variables
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)

# Test connection
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "SELECT version();"
```

## Step 4: Create IAM Database User

```bash
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'EOF'
-- Create user if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lambda_dsql_user') THEN
        CREATE ROLE lambda_dsql_user WITH LOGIN;
        RAISE NOTICE 'Created user lambda_dsql_user';
    ELSE
        RAISE NOTICE 'User lambda_dsql_user already exists';
    END IF;
END $$;

-- Grant IAM authentication
GRANT rds_iam TO lambda_dsql_user;
\du
EOF
```

## Step 5: Create Database and Schema

```bash
# Create database
psql -h $DSQL_HOST -U admin -d postgres -p 5432 -c "CREATE DATABASE car_entities;"

# Create tables
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

-- Grant permissions to lambda user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO lambda_dsql_user;

\dt
EOF
```

## Step 6: Download k6 Test Script

```bash
aws s3 cp s3://producer-api-lambda-deployments-978300727880/scripts/send-batch-events.js .
```

## Step 7: Run k6 Tests

```bash
# Run with 10 events per type
k6 run --env API_URL=https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com --env EVENTS_PER_TYPE=10 send-batch-events.js

# Run with more events
k6 run --env API_URL=https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com --env EVENTS_PER_TYPE=100 --env VUS_PER_EVENT_TYPE=5 send-batch-events.js
```

## Step 8: Verify Data in DSQL

```bash
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
```

## Quick Reference

| Variable | Value |
|----------|-------|
| DSQL Host | `vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws` |
| Region | `us-east-1` |
| Lambda API URL | `https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com` |
| IAM Database User | `lambda_dsql_user` |
| EC2 Instance ID | `i-058cb2a0dc3fdcf3b` |


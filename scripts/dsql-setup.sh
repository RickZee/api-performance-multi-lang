#!/bin/bash
# DSQL Setup Script for EC2 Test Runner
# Run this on the EC2 instance after connecting via SSM

set -e

# Configuration
export DSQL_HOST="vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
export AWS_REGION="us-east-1"
export IAM_DATABASE_USER="lambda_dsql_user"
export DSQL_API_URL="https://4b8qtfeq21.execute-api.us-east-1.amazonaws.com"

echo "=== DSQL Setup Script ==="
echo "DSQL Host: $DSQL_HOST"
echo "AWS Region: $AWS_REGION"
echo ""

# Step 1: Install required tools
echo "=== Step 1: Installing required tools ==="
sudo dnf install -y postgresql15 git jq || sudo yum install -y postgresql15 git jq

# Install k6
echo "=== Installing k6 ==="
if ! command -v k6 &> /dev/null; then
    sudo dnf install -y https://dl.k6.io/rpm/repo.rpm 2>/dev/null || \
    curl -sSL https://dl.k6.io/rpm/repo.rpm | sudo tee /etc/yum.repos.d/k6.repo > /dev/null
    sudo dnf install -y k6 || sudo yum install -y k6
fi
k6 version

# Step 2: Generate admin token and connect to DSQL
echo ""
echo "=== Step 2: Generating DSQL admin auth token ==="
export PGPASSWORD=$(aws dsql generate-db-connect-admin-auth-token --region $AWS_REGION --hostname $DSQL_HOST)
echo "Token generated (length: ${#PGPASSWORD} characters)"

# Step 3: Create IAM database user
echo ""
echo "=== Step 3: Creating IAM database user '$IAM_DATABASE_USER' ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'EOF'
-- Check if user exists
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

-- List users
\du
EOF

# Step 4: Create database (if doesn't exist)
echo ""
echo "=== Step 4: Creating database 'car_entities' ==="
psql -h $DSQL_HOST -U admin -d postgres -p 5432 << 'EOF'
-- Create database if not exists
SELECT 'CREATE DATABASE car_entities' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'car_entities')\gexec
EOF

# Step 5: Create schema in car_entities database
echo ""
echo "=== Step 5: Creating schema in car_entities database ==="
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

CREATE INDEX IF NOT EXISTS idx_business_events_event_type ON business_events(event_type);
CREATE INDEX IF NOT EXISTS idx_business_events_created_date ON business_events(created_date);

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

CREATE INDEX IF NOT EXISTS idx_event_headers_event_type ON event_headers(event_type);
CREATE INDEX IF NOT EXISTS idx_event_headers_created_date ON event_headers(created_date);

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

CREATE INDEX IF NOT EXISTS idx_car_entities_entity_type ON car_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_car_entities_created_at ON car_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_updated_at ON car_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_car_entities_event_id ON car_entities(event_id);

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

CREATE INDEX IF NOT EXISTS idx_loan_entities_entity_type ON loan_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_entities_created_at ON loan_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_entities_updated_at ON loan_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_loan_entities_event_id ON loan_entities(event_id);

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

CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_entity_type ON loan_payment_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_created_at ON loan_payment_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_updated_at ON loan_payment_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_loan_payment_entities_event_id ON loan_payment_entities(event_id);

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

CREATE INDEX IF NOT EXISTS idx_service_record_entities_entity_type ON service_record_entities(entity_type);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_created_at ON service_record_entities(created_at);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_updated_at ON service_record_entities(updated_at);
CREATE INDEX IF NOT EXISTS idx_service_record_entities_event_id ON service_record_entities(event_id);

-- Grant permissions to lambda user
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO lambda_dsql_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO lambda_dsql_user;

-- List tables
\dt
EOF

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Next steps:"
echo "1. Clone the repo: git clone https://github.com/your-repo/api-performance-multi-lang.git"
echo "2. Run k6 tests: k6 run --env API_URL=$DSQL_API_URL --env EVENTS_PER_TYPE=10 load-test/k6/send-batch-events.js"
echo ""
echo "To verify connection, run:"
echo "  psql -h $DSQL_HOST -U admin -d car_entities -c 'SELECT COUNT(*) FROM business_events;'"

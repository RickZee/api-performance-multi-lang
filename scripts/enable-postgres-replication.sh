#!/bin/bash

# Enable logical replication for Debezium CDC
# This script configures PostgreSQL for Change Data Capture

set -e

echo "======================================"
echo "Enabling PostgreSQL Logical Replication"
echo "======================================"

CONTAINER_NAME="car_entities_postgres_large"
DB_NAME="car_entities"
DB_USER="postgres"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: PostgreSQL container '$CONTAINER_NAME' is not running"
    echo "Please start the database with: docker-compose up -d postgres-large"
    exit 1
fi

echo ""
echo "Step 1: Checking current replication settings..."
docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SHOW wal_level;"

echo ""
echo "Step 2: Updating PostgreSQL configuration for logical replication..."
docker exec -it "$CONTAINER_NAME" bash -c "cat >> /var/lib/postgresql/data/postgresql.conf << EOF

# Logical Replication Settings for Debezium CDC
wal_level = logical
max_replication_slots = 4
max_wal_senders = 4
EOF"

echo ""
echo "Step 3: Restarting PostgreSQL container to apply changes..."
docker restart "$CONTAINER_NAME"

echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 10

# Wait for Postgres to be healthy
until docker exec "$CONTAINER_NAME" pg_isready -U "$DB_USER" > /dev/null 2>&1; do
    echo "Waiting for PostgreSQL..."
    sleep 2
done

echo ""
echo "Step 4: Verifying replication settings..."
docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SHOW wal_level;"
docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SHOW max_replication_slots;"
docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c "SHOW max_wal_senders;"

echo ""
echo "Step 5: Creating replication user (if not exists)..."
docker exec -it "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" << 'EOSQL'
-- Create replication user with proper permissions
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'replicator') THEN
        CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'replicator_password';
    END IF;
END
$$;

-- Grant necessary permissions
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
GRANT USAGE ON SCHEMA public TO replicator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replicator;
EOSQL

echo ""
echo "✓ PostgreSQL is now configured for logical replication!"
echo ""
echo "Next steps:"
echo "  1. Start Kafka Connect: docker-compose up -d kafka-connect"
echo "  2. Deploy connector: ./scripts/deploy-debezium-connector.sh"
echo ""

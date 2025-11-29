#!/bin/bash
# Prepare Flink SQL for Confluent Cloud deployment
# This script generates SQL and injects Confluent Cloud endpoints and credentials

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required environment variables or prompt
if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ]; then
    print_warn "KAFKA_BOOTSTRAP_SERVERS not set"
    read -p "Enter Kafka bootstrap servers (e.g., pkc-xxxxx.us-east-1.aws.confluent.cloud:9092): " KAFKA_BOOTSTRAP_SERVERS
fi

if [ -z "$SCHEMA_REGISTRY_URL" ]; then
    print_warn "SCHEMA_REGISTRY_URL not set"
    read -p "Enter Schema Registry URL (e.g., https://psrc-xxxxx.us-east-1.aws.confluent.cloud): " SCHEMA_REGISTRY_URL
fi

if [ -z "$KAFKA_API_KEY" ]; then
    print_warn "KAFKA_API_KEY not set"
    read -p "Enter Kafka API key: " KAFKA_API_KEY
fi

if [ -z "$KAFKA_API_SECRET" ]; then
    print_warn "KAFKA_API_SECRET not set"
    read -sp "Enter Kafka API secret: " KAFKA_API_SECRET
    echo
fi

if [ -z "$SCHEMA_REGISTRY_API_KEY" ]; then
    print_warn "SCHEMA_REGISTRY_API_KEY not set"
    read -p "Enter Schema Registry API key: " SCHEMA_REGISTRY_API_KEY
fi

if [ -z "$SCHEMA_REGISTRY_API_SECRET" ]; then
    print_warn "SCHEMA_REGISTRY_API_SECRET not set"
    read -sp "Enter Schema Registry API secret: " SCHEMA_REGISTRY_API_SECRET
    echo
fi

# Generate base SQL
print_info "Generating SQL from filters.yaml..."
cd "$PROJECT_ROOT"

python scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-confluent-cloud-temp.sql \
  --kafka-bootstrap "$KAFKA_BOOTSTRAP_SERVERS" \
  --schema-registry "$SCHEMA_REGISTRY_URL" \
  --no-validate 2>/dev/null || python3 scripts/generate-flink-sql.py \
  --config flink-jobs/filters.yaml \
  --output flink-jobs/routing-confluent-cloud-temp.sql \
  --kafka-bootstrap "$KAFKA_BOOTSTRAP_SERVERS" \
  --schema-registry "$SCHEMA_REGISTRY_URL" \
  --no-validate

# Add authentication to source table
print_info "Adding Confluent Cloud authentication to SQL..."

# Create output file with authentication
cat > flink-jobs/routing-confluent-cloud.sql << EOF
-- Flink SQL Job for Event Filtering and Routing (Confluent Cloud)
-- This file is AUTO-GENERATED and configured for Confluent Cloud
-- DO NOT EDIT MANUALLY - Regenerate using prepare-sql-for-confluent-cloud.sh

EOF

# Process the generated SQL and add authentication
awk -v kafka_bootstrap="$KAFKA_BOOTSTRAP_SERVERS" \
    -v schema_registry="$SCHEMA_REGISTRY_URL" \
    -v kafka_key="$KAFKA_API_KEY" \
    -v kafka_secret="$KAFKA_API_SECRET" \
    -v sr_key="$SCHEMA_REGISTRY_API_KEY" \
    -v sr_secret="$SCHEMA_REGISTRY_API_SECRET" '
{
    # Replace bootstrap servers
    gsub(/kafka:29092/, kafka_bootstrap)
    gsub(/localhost:9092/, kafka_bootstrap)
    
    # Replace schema registry URL
    gsub(/http:\/\/schema-registry:8081/, schema_registry)
    gsub(/http:\/\/localhost:8081/, schema_registry)
    
    # Add authentication to WITH clauses
    if (/WITH \(/) {
        print $0
        in_with = 1
        next
    }
    
    if (in_with && /'\''connector'\'' = '\''kafka'\''/) {
        print $0
        print "    '\''properties.security.protocol'\'' = '\''SASL_SSL'\'',"
        print "    '\''properties.sasl.mechanism'\'' = '\''PLAIN'\'',"
        print "    '\''properties.sasl.jaas.config'\'' = '\''org.apache.kafka.common.security.plain.PlainLoginModule required username=\"" kafka_key "\" password=\"" kafka_secret "\";'\'',"
        next
    }
    
    if (in_with && /'\''avro.schema-registry.url'\''/) {
        print $0
        print "    '\''avro.schema-registry.basic-auth.credentials-source'\'' = '\''USER_INFO'\'',"
        print "    '\''avro.schema-registry.basic-auth.user-info'\'' = '\''" sr_key ":" sr_secret "'\'',"
        next
    }
    
    if (in_with && /\)/) {
        in_with = 0
    }
    
    print $0
}' flink-jobs/routing-confluent-cloud-temp.sql >> flink-jobs/routing-confluent-cloud.sql

# Clean up temp file
rm -f flink-jobs/routing-confluent-cloud-temp.sql

print_info "SQL file prepared: flink-jobs/routing-confluent-cloud.sql"
print_info "Review the file before deploying to ensure credentials are correct"

# Validate SQL
print_info "Validating generated SQL..."
if command -v python3 &> /dev/null; then
    python3 scripts/validate-sql.py --sql flink-jobs/routing-confluent-cloud.sql || print_warn "SQL validation completed with warnings"
else
    print_warn "Python not found, skipping SQL validation"
fi

print_info "Done! Next steps:"
echo "  1. Review flink-jobs/routing-confluent-cloud.sql"
echo "  2. Deploy using: confluent flink statement create --compute-pool <pool-id> --statement-file flink-jobs/routing-confluent-cloud.sql"

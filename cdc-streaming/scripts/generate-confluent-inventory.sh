#!/usr/bin/env bash
# Generate Confluent Cloud Resource Inventory Documentation
# Calls inventory script and formats output as markdown
#
# Usage:
#   ./generate-confluent-inventory.sh [OUTPUT_FILE]
#
# Output:
#   Creates CONFLUENT_CLOUD_RESOURCE_INVENTORY.md with comprehensive resource documentation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

OUTPUT_FILE="${1:-$PROJECT_ROOT/cdc-streaming/docs/CONFLUENT_CLOUD_RESOURCE_INVENTORY.md}"
INVENTORY_DIR="/tmp/confluent-inventory-$(date +%s)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${BLUE}ℹ${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }

# Step 1: Run inventory script
info "Running resource inventory..."
"$SCRIPT_DIR/inventory-confluent-resources.sh" "$INVENTORY_DIR"

if [ ! -f "$INVENTORY_DIR/metadata.json" ]; then
    error "Inventory script failed or produced no output"
    exit 1
fi

# Step 2: Generate markdown documentation
info "Generating markdown documentation..."

# Read metadata
INVENTORY_DATE=$(jq -r '.inventory_date' "$INVENTORY_DIR/metadata.json")
CURRENT_ENV=$(jq -r '.current_environment' "$INVENTORY_DIR/metadata.json")

# Start markdown document
cat > "$OUTPUT_FILE" << 'EOF'
# Confluent Cloud Resource Inventory

> **Generated**: INVENTORY_DATE_PLACEHOLDER  
> **Environment**: ENV_ID_PLACEHOLDER  
> **Purpose**: This document provides a complete inventory of all Confluent Cloud resources for reproduction and disaster recovery.

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Environments](#environments)
3. [Kafka Clusters](#kafka-clusters)
4. [Topics](#topics)
5. [Connectors](#connectors)
6. [Flink Compute Pools](#flink-compute-pools)
7. [Flink SQL Statements](#flink-sql-statements)
8. [Schema Registry](#schema-registry)
9. [API Keys](#api-keys)
10. [Service Accounts](#service-accounts)
11. [Consumer Groups](#consumer-groups)
12. [Reproduction Instructions](#reproduction-instructions)
13. [Dependencies and Relationships](#dependencies-and-relationships)

---

## Executive Summary

EOF

# Add summary statistics
ENV_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/environments.json" 2>/dev/null | tr -d '\n' || echo "0")
CLUSTER_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/kafka-clusters.json" 2>/dev/null | tr -d '\n' || echo "0")
TOPIC_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/topics.json" 2>/dev/null | tr -d '\n' || echo "0")
CONNECTOR_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/connectors-list.json" 2>/dev/null | tr -d '\n' || echo "0")
COMPUTE_POOL_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/flink-compute-pools.json" 2>/dev/null | tr -d '\n' || echo "0")
STATEMENT_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/flink-statements.json" 2>/dev/null | tr -d '\n' || echo "0")
SUBJECT_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/schema-registry-subjects.json" 2>/dev/null | tr -d '\n' || echo "0")
API_KEY_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/api-keys.json" 2>/dev/null | tr -d '\n' || echo "0")
SERVICE_ACCOUNT_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/service-accounts.json" 2>/dev/null | tr -d '\n' || echo "0")
CONSUMER_GROUP_COUNT=$(jq -r 'if type == "array" then length else 0 end' "$INVENTORY_DIR/consumer-groups.json" 2>/dev/null | tr -d '\n' || echo "0")

cat >> "$OUTPUT_FILE" << EOF
| Resource Type | Count |
|--------------|-------|
| Environments | $ENV_COUNT |
| Kafka Clusters | $CLUSTER_COUNT |
| Topics | $TOPIC_COUNT |
| Connectors | $CONNECTOR_COUNT |
| Flink Compute Pools | $COMPUTE_POOL_COUNT |
| Flink SQL Statements | $STATEMENT_COUNT |
| Schema Registry Subjects | $SUBJECT_COUNT |
| API Keys | $API_KEY_COUNT |
| Service Accounts | $SERVICE_ACCOUNT_COUNT |
| Consumer Groups | $CONSUMER_GROUP_COUNT |

---

## Environments

EOF

# Add environments section
if [ "${ENV_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| ID | Name | Stream Governance | Current |
|----|------|-------------------|---------|
EOF
    jq -r '.[] | "| \(.id) | \(.name // "N/A") | \(.stream_governance // "N/A") | \(if .is_current then "✓" else "" end) |"' \
        "$INVENTORY_DIR/environments.json" >> "$OUTPUT_FILE"
else
    echo "No environments found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Kafka Clusters

EOF

# Add Kafka clusters section
if [ "${CLUSTER_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| ID | Name | Type | Region | Cloud | Status | Bootstrap Servers |
|----|------|------|--------|-------|--------|-------------------|
EOF
    jq -r '.[] | "| \(.id) | \(.name // .display_name // "N/A") | \(.type // .spec.config.kind // .spec.kind // "N/A") | \(.region // .spec.region // "N/A") | \(.cloud // .spec.cloud // "N/A") | \(.status // .status.phase // "N/A") | \(.endpoint // .spec.http_endpoint // .spec.kafka_bootstrap_endpoint // "N/A") |"' \
        "$INVENTORY_DIR/kafka-clusters.json" >> "$OUTPUT_FILE"
    
    # Add detailed cluster information
    cat >> "$OUTPUT_FILE" << 'EOF'

### Cluster Details

EOF
    jq -r '.[] | "#### \(.name // .display_name // .id)\n\n- **ID**: `\(.id)`\n- **Type**: \(.type // .spec.config.kind // .spec.kind // "N/A")\n- **Region**: \(.region // .spec.region // "N/A")\n- **Cloud**: \(.cloud // .spec.cloud // "N/A")\n- **Status**: \(.status // .status.phase // "N/A")\n- **Bootstrap Servers**: `\(.endpoint // .spec.http_endpoint // .spec.kafka_bootstrap_endpoint // "N/A")`\n- **Availability**: \(.availability // "N/A")\n"' \
        "$INVENTORY_DIR/kafka-clusters.json" >> "$OUTPUT_FILE"
else
    echo "No Kafka clusters found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Topics

EOF

# Add topics section
if [ "${TOPIC_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| Topic Name | Cluster ID | Partitions | Replication Factor |
|------------|------------|------------|-------------------|
EOF
    # Try topic-details first, fallback to topics
    if [ -f "$INVENTORY_DIR/topic-details.json" ] && [ "$(jq 'length' "$INVENTORY_DIR/topic-details.json" 2>/dev/null || echo "0")" -gt 0 ]; then
        jq -r '.[] | "| \(.name) | \(.cluster_id // "N/A") | \(.partition_count // .partitions_count // .partitions // "N/A") | \(.replication_factor // "N/A") |"' \
            "$INVENTORY_DIR/topic-details.json" >> "$OUTPUT_FILE"
    elif [ -f "$INVENTORY_DIR/topics.json" ] && [ "$(jq 'length' "$INVENTORY_DIR/topics.json" 2>/dev/null || echo "0")" -gt 0 ]; then
        jq -r '.[] | "| \(.name) | \(.cluster_id // "N/A") | N/A | N/A |"' \
            "$INVENTORY_DIR/topics.json" >> "$OUTPUT_FILE"
    fi
    
    # Add topic configurations
    cat >> "$OUTPUT_FILE" << 'EOF'

### Topic Configurations

EOF
    jq -r '.[] | "#### \(.name)\n\n- **Cluster**: `\(.cluster_id // "N/A")`\n- **Partitions**: \(.partition_count // .partitions_count // .partitions // "N/A")\n- **Replication Factor**: \(.replication_factor // "N/A")\n- **Config**:\n```json\n\(.config // {} | tostring)\n```\n"' \
        "$INVENTORY_DIR/topic-details.json" 2>/dev/null >> "$OUTPUT_FILE" || true
else
    echo "No topics found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Connectors

EOF

# Add connectors section
if [ "${CONNECTOR_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| ID | Name | Type | Status |
|----|------|------|--------|
EOF
    # Try to use details first, fallback to list
    if [ -f "$INVENTORY_DIR/connectors-details.json" ] && [ "$(jq 'length' "$INVENTORY_DIR/connectors-details.json" 2>/dev/null || echo "0")" -gt 0 ]; then
        jq -r '.[] | "| \(.id) | \(.name // "N/A") | \(.connector_type_id // .connector.class // .type // "N/A") | \(.status.connector.state // .status // "N/A") |"' \
            "$INVENTORY_DIR/connectors-details.json" >> "$OUTPUT_FILE"
    else
        jq -r '.[] | "| \(.id) | \(.name // "N/A") | N/A | N/A |"' \
            "$INVENTORY_DIR/connectors-list.json" >> "$OUTPUT_FILE"
    fi
    
    # Add connector details
    cat >> "$OUTPUT_FILE" << 'EOF'

### Connector Details

EOF
    if [ -f "$INVENTORY_DIR/connectors-details.json" ] && [ "$(jq 'length' "$INVENTORY_DIR/connectors-details.json" 2>/dev/null || echo "0")" -gt 0 ]; then
        jq -r '.[] | "#### \(.name // .id)\n\n- **ID**: `\(.id)`\n- **Type**: \(.connector_type_id // .connector.class // .type // "N/A")\n- **Status**: \(.status.connector.state // .status // "N/A")\n- **Configuration** (sanitized):\n```json\n\(.config // {} | tostring)\n```\n"' \
            "$INVENTORY_DIR/connectors-details.json" >> "$OUTPUT_FILE"
    else
        # Use list data if details not available
        jq -r '.[] | "#### \(.name // .id)\n\n- **ID**: `\(.id)`\n- **Status**: N/A\n- **Note**: Detailed configuration not available. Check Confluent Cloud Console for full details.\n"' \
            "$INVENTORY_DIR/connectors-list.json" >> "$OUTPUT_FILE"
    fi
else
    echo "No connectors found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Flink Compute Pools

EOF

# Add Flink compute pools section
if [ "${COMPUTE_POOL_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| ID | Name | Region | Cloud | Max CFU | Status |
|----|------|--------|-------|---------|--------|
EOF
    jq -r '.[] | "| \(.id) | \(.display_name // .name // "N/A") | \(.region // "N/A") | \(.cloud // "N/A") | \(.max_cfu // "N/A") | \(.status // .status.phase // "N/A") |"' \
        "$INVENTORY_DIR/flink-compute-pools.json" >> "$OUTPUT_FILE"
else
    echo "No Flink compute pools found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Flink SQL Statements

EOF

# Add Flink statements section
if [ "${STATEMENT_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| Name | Compute Pool | Status | Phase |
|------|--------------|--------|-------|
EOF
    jq -r '.[] | "| \(.name) | \(.compute_pool_id // .compute_pool // "N/A") | \(.status // "N/A") | \(.phase // "N/A") |"' \
        "$INVENTORY_DIR/flink-statements.json" >> "$OUTPUT_FILE"
    
    # Add statement details
    cat >> "$OUTPUT_FILE" << 'EOF'

### Statement Details

EOF
    jq -r '.[] | "#### \(.name)\n\n- **Compute Pool**: `\(.compute_pool_id // .compute_pool // "N/A")`\n- **Status**: \(.status // "N/A")\n- **Phase**: \(.phase // "N/A")\n- **Status Detail**: \(.status_detail // "N/A")\n- **SQL** (first 500 chars):\n```sql\n\(.statement // "" | .[0:500])\n```\n"' \
        "$INVENTORY_DIR/flink-statements-details.json" 2>/dev/null >> "$OUTPUT_FILE" || true
else
    echo "No Flink SQL statements found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Schema Registry

EOF

# Add Schema Registry section
SR_ENDPOINT=$(jq -r '.endpoint_url // "N/A"' "$INVENTORY_DIR/schema-registry-cluster.json" 2>/dev/null || echo "N/A")
SR_CLUSTER_ID=$(jq -r '.cluster_id // "N/A"' "$INVENTORY_DIR/schema-registry-cluster.json" 2>/dev/null || echo "N/A")

cat >> "$OUTPUT_FILE" << EOF
- **Cluster ID**: \`$SR_CLUSTER_ID\`
- **Endpoint**: \`$SR_ENDPOINT\`

### Schema Subjects

EOF

if [ "${SUBJECT_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| Subject Name | Compatibility | Versions |
|--------------|--------------|----------|
EOF
    jq -r '.[] | "| \(.name // .subject // "N/A") | \(.compatibility // "N/A") | \(.versions // [] | length) |"' \
        "$INVENTORY_DIR/schema-registry-subjects-details.json" 2>/dev/null || \
    jq -r '.[] | "| \(.) | N/A | N/A |"' \
        "$INVENTORY_DIR/schema-registry-subjects.json" >> "$OUTPUT_FILE"
else
    echo "No Schema Registry subjects found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## API Keys

> **Security Note**: Only API key IDs are shown. Secrets are never stored or displayed.

EOF

# Add API keys section
if [ "${API_KEY_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| Key ID | Resource Type | Resource ID | Description | Owner |
|--------|--------------|-------------|-------------|-------|
EOF
    jq -r '.[] | "| \(.key // .id) | \(.resource_type // "N/A") | \(.resource // .resource_id // "N/A") | \(.description // "N/A") | \(.owner // "N/A") |"' \
        "$INVENTORY_DIR/api-keys.json" >> "$OUTPUT_FILE"
else
    echo "No API keys found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Service Accounts

EOF

# Add service accounts section
if [ "${SERVICE_ACCOUNT_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| ID | Name | Description |
|----|------|-------------|
EOF
    jq -r '.[] | "| \(.id) | \(.display_name // .name // "N/A") | \(.description // "N/A") |"' \
        "$INVENTORY_DIR/service-accounts.json" >> "$OUTPUT_FILE"
else
    echo "No service accounts found." >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Consumer Groups

EOF

# Add consumer groups section
if [ "${CONSUMER_GROUP_COUNT:-0}" -gt 0 ]; then
    cat >> "$OUTPUT_FILE" << 'EOF'
| Group Name | Cluster ID | State |
|------------|------------|-------|
EOF
    jq -r '.[] | "| \(.consumer_group_id // .name // "N/A") | \(.cluster_id // "N/A") | \(.state // "N/A") |"' \
        "$INVENTORY_DIR/consumer-groups.json" >> "$OUTPUT_FILE"
else
    echo "No consumer groups found." >> "$OUTPUT_FILE"
fi

# Add reproduction instructions
cat >> "$OUTPUT_FILE" << 'EOF'

---

## Reproduction Instructions

This section provides step-by-step instructions to recreate all resources documented above.

### Prerequisites

1. **Confluent Cloud Account**: Ensure you have access to Confluent Cloud
2. **Confluent CLI**: Install and authenticate
   ```bash
   brew install confluentinc/tap/cli
   confluent login
   ```
3. **Required Tools**: `jq` for JSON processing
   ```bash
   brew install jq
   ```

### Step 1: Create Environment

EOF

# Add environment creation commands
jq -r '.[] | "```bash\n# Create environment: \(.name // .id)\nconfluent environment create \(.name // .id) \\\n  --stream-governance \(.stream_governance // "ESSENTIALS")\n\n# Set as current\nconfluent environment use \(.id)\n```\n"' \
    "$INVENTORY_DIR/environments.json" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

### Step 2: Create Kafka Clusters

EOF

# Add cluster creation commands
    jq -r '.[] | "```bash\n# Create cluster: \(.name // .display_name // .id)\nconfluent kafka cluster create \(.name // .display_name // .id) \\\n  --cloud \(.cloud // .spec.cloud // "aws") \\\n  --region \(.region // .spec.region // "us-east-1") \\\n  --type \(.type // .spec.config.kind // .spec.kind // "basic")\n\n# Set as current\nconfluent kafka cluster use \(.id)\n```\n"' \
        "$INVENTORY_DIR/kafka-clusters.json" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

### Step 3: Create Topics

> **Note**: Only `raw-event-headers` needs manual creation. Filtered topics are automatically created by Flink.

EOF

# Add topic creation commands
    jq -r '.[] | select(.name == "raw-event-headers" or (.name | test("^raw-"; "i"))) | "```bash\n# Create topic: \(.name)\nconfluent kafka topic create \(.name) \\\n  --partitions \(.partition_count // .partitions_count // .partitions // 6) \\\n  --config retention.ms=\(.config."retention.ms" // "604800000")\n```\n"' \
        "$INVENTORY_DIR/topic-details.json" 2>/dev/null >> "$OUTPUT_FILE" || true

cat >> "$OUTPUT_FILE" << 'EOF'

### Step 4: Setup Schema Registry

Schema Registry is automatically enabled with Stream Governance. Get the endpoint:

```bash
confluent schema-registry cluster describe --output json | jq -r '.endpoint_url'
```

### Step 5: Create Flink Compute Pools

EOF

# Add compute pool creation commands
jq -r '.[] | "```bash\n# Create compute pool: \(.display_name // .name // .id)\nconfluent flink compute-pool create \(.display_name // .name // .id) \\\n  --cloud \(.cloud // "aws") \\\n  --region \(.region // "us-east-1") \\\n  --max-cfu \(.max_cfu // 5)\n```\n"' \
    "$INVENTORY_DIR/flink-compute-pools.json" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'

### Step 6: Deploy Flink SQL Statements

Use the deployment script:

```bash
cd cdc-streaming
export FLINK_COMPUTE_POOL_ID="<compute-pool-id>"
export KAFKA_CLUSTER_ID="<cluster-id>"
./scripts/deploy-business-events-flink.sh
```

Or deploy manually via Web Console (recommended for first-time setup):
1. Navigate to: https://confluent.cloud/environments/<env-id>/flink
2. Click "Open SQL Workspace"
3. Copy SQL from: `cdc-streaming/flink-jobs/business-events-routing-confluent-cloud.sql`
4. Deploy statements in order (source table → sink tables → INSERT statements)

### Step 7: Deploy Connectors

Use the deployment script:

```bash
cd cdc-streaming/scripts
export KAFKA_API_KEY="<your-kafka-api-key>"
export KAFKA_API_SECRET="<your-kafka-api-secret>"
export DB_HOSTNAME="<postgres-hostname>"
export DB_PASSWORD="<password>"
export DB_NAME="car_entities"
./deploy-event-headers-connector.sh
```

Or deploy via Confluent Cloud Console:
1. Navigate to: https://confluent.cloud/environments/<env-id>/connectors
2. Click "Add connector"
3. Select "PostgreSQL CDC Source V2 (Debezium)"
4. Configure using settings from connector configuration files in `cdc-streaming/connectors/`

### Step 8: Create API Keys

> **Note**: API key secrets cannot be retrieved after creation. You'll need to create new keys.

```bash
# Kafka Cluster API Key
confluent api-key create --resource <cluster-id> --description "Kafka cluster API key"

# Schema Registry API Key
SR_CLUSTER_ID=$(confluent schema-registry cluster describe --output json | jq -r '.cluster_id')
confluent api-key create --resource $SR_CLUSTER_ID --description "Schema Registry API key"

# Flink API Key
confluent api-key create --resource flink --cloud aws --region us-east-1 --description "Flink API key"
```

### Step 9: Create Service Accounts (if needed)

```bash
confluent iam service-account create <name> --description "<description>"
```

---

## Dependencies and Relationships

### Resource Dependency Graph

```
Environment
  ├── Kafka Cluster
  │     ├── Topics
  │     ├── Connectors
  │     └── Consumer Groups
  ├── Schema Registry
  │     └── Schema Subjects
  └── Flink Compute Pool
        └── Flink SQL Statements
              └── Topics (sink)
```

### Creation Order

1. **Environment** (foundation)
2. **Kafka Cluster** (requires environment)
3. **Topics** (requires cluster) - Only `raw-event-headers` needs manual creation
4. **Schema Registry** (auto-enabled with Stream Governance)
5. **Flink Compute Pool** (requires environment)
6. **Flink SQL Statements** (requires compute pool and cluster)
7. **Connectors** (requires cluster and topics)
8. **API Keys** (requires resources to be created)
9. **Service Accounts** (optional, for automation)

### Important Notes

- **Topics**: Filtered topics (`filtered-*-events-flink`) are automatically created by Flink when statements write to them. Only `raw-event-headers` needs manual creation.
- **API Keys**: Secrets cannot be retrieved. Store them securely when creating new keys.
- **Connectors**: Require database connectivity and proper network configuration.
- **Flink Statements**: Source table must be created before INSERT statements.
- **Schema Registry**: Automatically enabled with Stream Governance package.

---

## Related Documentation

- [CONFLUENT_CLOUD_SETUP_GUIDE.md](../CONFLUENT_CLOUD_SETUP_GUIDE.md): Complete setup guide
- [ARCHITECTURE.md](../ARCHITECTURE.md): System architecture
- [README.md](../README.md): Main documentation

---

## Maintenance

**To Update This Inventory:**

```bash
cd cdc-streaming/scripts
./generate-confluent-inventory.sh
```

This will regenerate the inventory with current resource state.

**Last Updated**: INVENTORY_DATE_PLACEHOLDER
EOF

# Replace placeholders
sed -i.bak "s/INVENTORY_DATE_PLACEHOLDER/$INVENTORY_DATE/g" "$OUTPUT_FILE"
sed -i.bak "s/ENV_ID_PLACEHOLDER/$CURRENT_ENV/g" "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.bak"

success "Documentation generated: $OUTPUT_FILE"
info "Inventory data saved to: $INVENTORY_DIR"
info "You can review the JSON files for detailed resource information."

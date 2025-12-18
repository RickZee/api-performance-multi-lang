#!/usr/bin/env bash
# Inventory Confluent Cloud Resources
# Queries all resources and outputs structured JSON for documentation
#
# Usage:
#   ./inventory-confluent-resources.sh [OUTPUT_DIR]
#
# Output:
#   Creates JSON files in OUTPUT_DIR (default: /tmp/confluent-inventory) with all resource data

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="${1:-/tmp/confluent-inventory}"

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

# Check prerequisites
if ! command -v confluent &> /dev/null; then
    error "Confluent CLI not found. Install with: brew install confluentinc/tap/cli"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    error "jq not found. Install with: brew install jq"
    exit 1
fi

# Check if logged in
if ! confluent environment list &> /dev/null; then
    error "Not logged in to Confluent Cloud. Run: confluent login"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
info "Output directory: $OUTPUT_DIR"

# Function to sanitize sensitive data
sanitize_config() {
    local config_json="$1"
    echo "$config_json" | jq '
        if type == "object" then
            with_entries(
                if .key | test("password|secret|key|token|credential"; "i") then
                    .value = "***REDACTED***"
                else
                    .
                end
            )
        else
            .
        end
    '
}

# Function to query with error handling
safe_query() {
    local cmd="$1"
    local output_file="$2"
    local description="$3"
    
    info "Querying $description..."
    if eval "$cmd" > "$output_file" 2>&1; then
        # Check if output is valid JSON
        if jq empty "$output_file" 2>/dev/null; then
            success "  Retrieved $description"
            return 0
        else
            warn "  Invalid JSON for $description, may be empty"
            echo "[]" > "$output_file"
            return 1
        fi
    else
        warn "  Failed to query $description (may not exist)"
        echo "[]" > "$output_file"
        return 1
    fi
}

# Get current environment
CURRENT_ENV=$(confluent environment list --output json 2>/dev/null | jq -r '.[] | select(.is_current==true) | .id' | head -1 || echo "")
if [ -z "$CURRENT_ENV" ]; then
    CURRENT_ENV=$(confluent environment list --output json 2>/dev/null | jq -r '.[0].id' | head -1 || echo "")
fi

info "Current environment: $CURRENT_ENV"

# 1. Environments
safe_query "confluent environment list --output json" \
    "$OUTPUT_DIR/environments.json" \
    "environments"

# 2. Kafka Clusters
safe_query "confluent kafka cluster list --output json" \
    "$OUTPUT_DIR/kafka-clusters.json" \
    "Kafka clusters"

# Get cluster IDs for topic queries
CLUSTER_IDS=$(jq -r '.[].id' "$OUTPUT_DIR/kafka-clusters.json" 2>/dev/null || echo "")

# 3. Topics (for each cluster)
if [ -n "$CLUSTER_IDS" ]; then
    echo "[]" > "$OUTPUT_DIR/topics.json"
    echo "[]" > "$OUTPUT_DIR/topic-details.json"
    
    for CLUSTER_ID in $CLUSTER_IDS; do
        info "Querying topics for cluster: $CLUSTER_ID"
        confluent kafka cluster use "$CLUSTER_ID" &> /dev/null || true
        
        # List topics
        TOPICS_JSON=$(confluent kafka topic list --output json 2>/dev/null || echo "[]")
        
        # Merge into main topics array
        if [ "$TOPICS_JSON" != "[]" ] && [ -n "$TOPICS_JSON" ]; then
            jq --arg cluster "$CLUSTER_ID" '. + [.[] | .cluster_id = $cluster]' \
                <(echo "$TOPICS_JSON") \
                <(cat "$OUTPUT_DIR/topics.json") \
                > "$OUTPUT_DIR/topics-tmp.json" 2>/dev/null || echo "$TOPICS_JSON" > "$OUTPUT_DIR/topics-tmp.json"
            mv "$OUTPUT_DIR/topics-tmp.json" "$OUTPUT_DIR/topics.json"
        fi
        
        # Get details for each topic
        TOPIC_NAMES=$(echo "$TOPICS_JSON" | jq -r '.[].name' 2>/dev/null || echo "")
        for TOPIC_NAME in $TOPIC_NAMES; do
            if [ -n "$TOPIC_NAME" ] && [ "$TOPIC_NAME" != "null" ]; then
                TOPIC_DETAIL=$(confluent kafka topic describe "$TOPIC_NAME" --output json 2>/dev/null || echo "{}")
                if [ "$TOPIC_DETAIL" != "{}" ] && [ -n "$TOPIC_DETAIL" ]; then
                    TOPIC_WITH_CLUSTER=$(echo "$TOPIC_DETAIL" | jq --arg cluster "$CLUSTER_ID" '. + {cluster_id: $cluster}')
                    jq ". + [$TOPIC_WITH_CLUSTER]" \
                        "$OUTPUT_DIR/topic-details.json" \
                        > "$OUTPUT_DIR/topic-details-tmp.json" 2>/dev/null
                    mv "$OUTPUT_DIR/topic-details-tmp.json" "$OUTPUT_DIR/topic-details.json"
                fi
            fi
        done
    done
    
    success "  Retrieved topics"
else
    echo "[]" > "$OUTPUT_DIR/topics.json"
    echo "[]" > "$OUTPUT_DIR/topic-details.json"
    warn "  No clusters found, skipping topics"
fi

# 4. Connectors
safe_query "confluent connect cluster list --output json" \
    "$OUTPUT_DIR/connectors-list.json" \
    "connectors"

# Get connector details
CONNECTOR_IDS=$(jq -r '.[].id' "$OUTPUT_DIR/connectors-list.json" 2>/dev/null || echo "")
echo "[]" > "$OUTPUT_DIR/connectors-details.json"

if [ -n "$CONNECTOR_IDS" ]; then
    for CONNECTOR_ID in $CONNECTOR_IDS; do
        if [ -n "$CONNECTOR_ID" ] && [ "$CONNECTOR_ID" != "null" ]; then
            info "  Getting details for connector: $CONNECTOR_ID"
            CONNECTOR_DETAIL=$(confluent connect cluster describe "$CONNECTOR_ID" --output json 2>/dev/null || echo "{}")
            if [ "$CONNECTOR_DETAIL" != "{}" ] && [ -n "$CONNECTOR_DETAIL" ]; then
                # Sanitize connector config
                SANITIZED=$(echo "$CONNECTOR_DETAIL" | sanitize_config)
                jq ". + [$SANITIZED]" \
                    "$OUTPUT_DIR/connectors-details.json" \
                    > "$OUTPUT_DIR/connectors-details-tmp.json" 2>/dev/null
                mv "$OUTPUT_DIR/connectors-details-tmp.json" "$OUTPUT_DIR/connectors-details.json"
            fi
        fi
    done
    success "  Retrieved connector details"
fi

# 5. Flink Compute Pools
safe_query "confluent flink compute-pool list --output json" \
    "$OUTPUT_DIR/flink-compute-pools.json" \
    "Flink compute pools"

# 6. Flink Statements (for each compute pool)
COMPUTE_POOL_IDS=$(jq -r '.[].id' "$OUTPUT_DIR/flink-compute-pools.json" 2>/dev/null || echo "")
echo "[]" > "$OUTPUT_DIR/flink-statements.json"
echo "[]" > "$OUTPUT_DIR/flink-statements-details.json"

if [ -n "$COMPUTE_POOL_IDS" ]; then
    for POOL_ID in $COMPUTE_POOL_IDS; do
        if [ -n "$POOL_ID" ] && [ "$POOL_ID" != "null" ]; then
            info "  Querying Flink statements for compute pool: $POOL_ID"
            STATEMENTS_JSON=$(confluent flink statement list --compute-pool "$POOL_ID" --output json 2>/dev/null || echo "[]")
            
            if [ "$STATEMENTS_JSON" != "[]" ] && [ -n "$STATEMENTS_JSON" ]; then
                # Add compute pool ID to each statement
                STATEMENTS_WITH_POOL=$(echo "$STATEMENTS_JSON" | jq --arg pool "$POOL_ID" '.[] | .compute_pool_id = $pool')
                jq ". + [$STATEMENTS_WITH_POOL]" \
                    <(echo "$STATEMENTS_WITH_POOL" | jq -s '.') \
                    "$OUTPUT_DIR/flink-statements.json" \
                    > "$OUTPUT_DIR/flink-statements-tmp.json" 2>/dev/null || echo "$STATEMENTS_JSON" > "$OUTPUT_DIR/flink-statements-tmp.json"
                mv "$OUTPUT_DIR/flink-statements-tmp.json" "$OUTPUT_DIR/flink-statements.json"
                
                # Get details for each statement
                STATEMENT_NAMES=$(echo "$STATEMENTS_JSON" | jq -r '.[].name' 2>/dev/null || echo "")
                for STMT_NAME in $STATEMENT_NAMES; do
                    if [ -n "$STMT_NAME" ] && [ "$STMT_NAME" != "null" ]; then
                        STMT_DETAIL=$(confluent flink statement describe "$STMT_NAME" --compute-pool "$POOL_ID" --output json 2>/dev/null || echo "{}")
                        if [ "$STMT_DETAIL" != "{}" ] && [ -n "$STMT_DETAIL" ]; then
                            STMT_WITH_POOL=$(echo "$STMT_DETAIL" | jq --arg pool "$POOL_ID" '. + {compute_pool_id: $pool}')
                            jq ". + [$STMT_WITH_POOL]" \
                                "$OUTPUT_DIR/flink-statements-details.json" \
                                > "$OUTPUT_DIR/flink-statements-details-tmp.json" 2>/dev/null
                            mv "$OUTPUT_DIR/flink-statements-details-tmp.json" "$OUTPUT_DIR/flink-statements-details.json"
                        fi
                    fi
                done
            fi
        fi
    done
    success "  Retrieved Flink statements"
else
    warn "  No compute pools found, skipping Flink statements"
fi

# 7. Schema Registry
# Get Schema Registry cluster info
SR_CLUSTER=$(confluent schema-registry cluster describe --output json 2>/dev/null || echo "{}")
echo "$SR_CLUSTER" > "$OUTPUT_DIR/schema-registry-cluster.json"

# Get Schema Registry subjects
safe_query "confluent schema-registry subject list --output json" \
    "$OUTPUT_DIR/schema-registry-subjects.json" \
    "Schema Registry subjects"

# Get details for each subject
SUBJECT_NAMES=$(jq -r '.[]' "$OUTPUT_DIR/schema-registry-subjects.json" 2>/dev/null || echo "")
echo "[]" > "$OUTPUT_DIR/schema-registry-subjects-details.json"

if [ -n "$SUBJECT_NAMES" ]; then
    for SUBJECT in $SUBJECT_NAMES; do
        if [ -n "$SUBJECT" ] && [ "$SUBJECT" != "null" ]; then
            SUBJECT_DETAIL=$(confluent schema-registry subject describe "$SUBJECT" --output json 2>/dev/null || echo "{}")
            if [ "$SUBJECT_DETAIL" != "{}" ] && [ -n "$SUBJECT_DETAIL" ]; then
                jq ". + [$SUBJECT_DETAIL]" \
                    "$OUTPUT_DIR/schema-registry-subjects-details.json" \
                    > "$OUTPUT_DIR/schema-registry-subjects-details-tmp.json" 2>/dev/null
                mv "$OUTPUT_DIR/schema-registry-subjects-details-tmp.json" "$OUTPUT_DIR/schema-registry-subjects-details.json"
            fi
        fi
    done
    success "  Retrieved Schema Registry subject details"
fi

# 8. API Keys
safe_query "confluent api-key list --output json" \
    "$OUTPUT_DIR/api-keys.json" \
    "API keys"

# 9. Service Accounts
safe_query "confluent iam service-account list --output json" \
    "$OUTPUT_DIR/service-accounts.json" \
    "service accounts"

# 10. Consumer Groups (for each cluster)
if [ -n "$CLUSTER_IDS" ]; then
    echo "[]" > "$OUTPUT_DIR/consumer-groups.json"
    
    for CLUSTER_ID in $CLUSTER_IDS; do
        info "  Querying consumer groups for cluster: $CLUSTER_ID"
        confluent kafka cluster use "$CLUSTER_ID" &> /dev/null || true
        
        CONSUMER_GROUPS_JSON=$(confluent kafka consumer-group list --output json 2>/dev/null || echo "[]")
        
        if [ "$CONSUMER_GROUPS_JSON" != "[]" ] && [ -n "$CONSUMER_GROUPS_JSON" ]; then
            CONSUMER_GROUPS_WITH_CLUSTER=$(echo "$CONSUMER_GROUPS_JSON" | jq --arg cluster "$CLUSTER_ID" '.[] | .cluster_id = $cluster')
            jq ". + [$CONSUMER_GROUPS_WITH_CLUSTER]" \
                <(echo "$CONSUMER_GROUPS_WITH_CLUSTER" | jq -s '.') \
                "$OUTPUT_DIR/consumer-groups.json" \
                > "$OUTPUT_DIR/consumer-groups-tmp.json" 2>/dev/null || echo "$CONSUMER_GROUPS_JSON" > "$OUTPUT_DIR/consumer-groups-tmp.json"
            mv "$OUTPUT_DIR/consumer-groups-tmp.json" "$OUTPUT_DIR/consumer-groups.json"
        fi
    done
    
    success "  Retrieved consumer groups"
else
    echo "[]" > "$OUTPUT_DIR/consumer-groups.json"
    warn "  No clusters found, skipping consumer groups"
fi

# Create metadata file
cat > "$OUTPUT_DIR/metadata.json" << EOF
{
  "inventory_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "inventory_version": "1.0",
  "confluent_cli_version": "$(confluent version 2>/dev/null | head -1 || echo "unknown")",
  "current_environment": "$CURRENT_ENV",
  "output_directory": "$OUTPUT_DIR"
}
EOF

success "Inventory complete! JSON files saved to: $OUTPUT_DIR"
info "Files created:"
ls -1 "$OUTPUT_DIR"/*.json | sed 's|.*/||' | sed 's/^/  - /'

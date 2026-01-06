#!/usr/bin/env bash
# Seed V1 filters into Metadata Service database
# This script reads filters.json and creates them via Metadata Service API

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CDC_STREAMING_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$CDC_STREAMING_DIR"

METADATA_SERVICE_URL="${METADATA_SERVICE_URL:-http://localhost:8080}"
FILTERS_FILE="${FILTERS_FILE:-./config/filters.json}"
SCHEMA_VERSION="${SCHEMA_VERSION:-v1}"

if [ ! -f "$FILTERS_FILE" ]; then
    echo "Error: Filters file not found: $FILTERS_FILE"
    exit 1
fi

echo "Seeding V1 filters from $FILTERS_FILE to Metadata Service at $METADATA_SERVICE_URL"

# Check if Metadata Service is available
if ! curl -sf "$METADATA_SERVICE_URL/api/v1/health" > /dev/null; then
    echo "Error: Metadata Service is not available at $METADATA_SERVICE_URL"
    exit 1
fi

# Parse filters.json and create each filter
# Using jq to parse JSON and create filters
if command -v jq &> /dev/null; then
    filter_count=$(jq '.filters | length' "$FILTERS_FILE")
    echo "Found $filter_count filters to create"
    
    for i in $(seq 0 $((filter_count - 1))); do
        filter_json=$(jq -c ".filters[$i]" "$FILTERS_FILE")
        
        # Extract filter ID for logging
        filter_id=$(echo "$filter_json" | jq -r '.id')
        echo "Creating filter: $filter_id"
        
        # Create filter via API
        response=$(curl -s -w "\n%{http_code}" -X POST \
            "$METADATA_SERVICE_URL/api/v1/filters?version=$SCHEMA_VERSION" \
            -H "Content-Type: application/json" \
            -d "$filter_json")
        
        http_code=$(echo "$response" | tail -n1)
        body=$(echo "$response" | sed '$d')
        
        if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 200 ]; then
            echo "  ✓ Created filter: $filter_id"
            
            # Approve the filter if it was created
            if [ "$http_code" -eq 201 ]; then
                created_id=$(echo "$body" | jq -r '.id')
                echo "  → Approving filter: $created_id"
                approve_body=$(echo '{"approvedBy":"system"}' | jq -c .)
                approve_response=$(curl -s -w "\n%{http_code}" -X POST \
                    "$METADATA_SERVICE_URL/api/v1/filters/$created_id/approve?version=$SCHEMA_VERSION" \
                    -H "Content-Type: application/json" \
                    -d "$approve_body")
                
                approve_code=$(echo "$approve_response" | tail -n1)
                if [ "$approve_code" -eq 200 ]; then
                    echo "  ✓ Approved filter: $created_id"
                else
                    echo "  ⚠ Failed to approve filter: $created_id (HTTP $approve_code)"
                    echo "    Response: $(echo "$approve_response" | sed '$d')"
                fi
            fi
        elif [ "$http_code" -eq 409 ]; then
            echo "  ⚠ Filter already exists: $filter_id"
        else
            echo "  ✗ Failed to create filter: $filter_id (HTTP $http_code)"
            echo "    Response: $body"
        fi
    done
    
    echo ""
    echo "V1 filter seeding complete!"
    echo "Verify filters: curl $METADATA_SERVICE_URL/api/v1/filters/active?version=$SCHEMA_VERSION"
else
    echo "Error: jq is required to parse JSON. Install it: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

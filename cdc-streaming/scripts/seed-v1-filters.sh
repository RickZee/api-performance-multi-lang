#!/bin/bash

# Script to seed V1 filters into the Metadata Service
# This is used for integration tests to ensure V1 filters are available in the database

METADATA_SERVICE_URL="http://localhost:8080"
SCHEMA_VERSION="v1"
FILTERS_FILE="../config/filters.json"

echo "Seeding V1 filters from $FILTERS_FILE into Metadata Service ($METADATA_SERVICE_URL) for schema version $SCHEMA_VERSION"

# Check if Metadata Service is available
echo "Waiting for Metadata Service to be available..."
until curl -s "$METADATA_SERVICE_URL/api/v1/health" | grep -q "UP"; do
  echo -n "."
  sleep 2
done
echo "Metadata Service is up!"

# Read filters from JSON file
FILTERS=$(jq '.filters' "$FILTERS_FILE")

if [ -z "$FILTERS" ] || [ "$FILTERS" == "null" ]; then
  echo "No filters found in $FILTERS_FILE"
  exit 0
fi

echo "Found $(echo "$FILTERS" | jq 'length') filters to create"

# Iterate over each filter and create/approve it
echo "$FILTERS" | jq -c '.[]' | while read -r filter_json; do
  filter_id=$(echo "$filter_json" | jq -r '.id')
  filter_name=$(echo "$filter_json" | jq -r '.name')

  echo "Creating filter: $filter_id"
  # Attempt to create the filter
  create_response=$(curl -s -w "\n%{http_code}" -X POST \
      "$METADATA_SERVICE_URL/api/v1/filters?version=$SCHEMA_VERSION" \
      -H "Content-Type: application/json" \
      -d "$filter_json")

  http_code=$(echo "$create_response" | tail -n1)
  body=$(echo "$create_response" | sed '$d') # Remove the last line (HTTP code)

  if [ "$http_code" -eq 201 ] || [ "$http_code" -eq 409 ]; then # 201 Created, 409 Conflict (already exists)
      if [ "$http_code" -eq 201 ]; then
          echo "  ✓ Created filter: $filter_id"
      else
          echo "  ⚠ Filter already exists: $filter_id"
      fi

      # Approve the filter if it's not already approved/deployed
      current_status=$(echo "$body" | jq -r '.status // "pending_approval"')
      if [ "$current_status" != "approved" ] && [ "$current_status" != "deployed" ]; then
          echo "  → Approving filter: $filter_id"
          approve_response=$(curl -s -w "\n%{http_code}" -X POST \
              "$METADATA_SERVICE_URL/api/v1/filters/$filter_id/approve?version=$SCHEMA_VERSION" \
              -H "Content-Type: application/json" \
              -d '{"approvedBy": "system"}')

          approve_code=$(echo "$approve_response" | tail -n1)
          approve_body=$(echo "$approve_response" | sed '$d')

          if [ "$approve_code" -eq 200 ]; then
              echo "  ✓ Approved filter: $filter_id"
          else
              echo "  ⚠ Failed to approve filter: $filter_id (HTTP $approve_code)"
              echo "    Response: $approve_body"
          fi
      else
          echo "  ✓ Filter already approved/deployed: $filter_id"
      fi
  else
      echo "  ❌ Failed to create filter: $filter_id (HTTP $http_code)"
      echo "    Response: $body"
      exit 1 # Exit on critical failure
  fi
done

echo "V1 filter seeding complete!"
echo "Verify filters: curl $METADATA_SERVICE_URL/api/v1/filters/active?version=$SCHEMA_VERSION"


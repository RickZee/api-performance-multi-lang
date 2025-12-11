#!/bin/bash
# Create Kafka Topics
# NOTE: This script is deprecated - Confluent topics and Flink SQL statements have been removed.
# Events are now stored directly in PostgreSQL (business_events and entity tables).
# This script is kept for reference only.

set -e

echo "WARNING: This script is deprecated."
echo "Confluent topics and Flink SQL statements have been removed from the system."
echo "Events are now stored directly in PostgreSQL database (business_events and entity tables)."
echo ""
echo "See data/schema.sql for the new database schema."
echo ""
exit 0


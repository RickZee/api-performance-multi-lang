#!/usr/bin/env python3
"""
Filter Generator Script
Generates Flink SQL and Spring Boot YAML configurations from filters.json
"""

import json
import os
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Any
from datetime import datetime

# Get project root directory
SCRIPT_DIR = Path(__file__).parent
# Script is in cdc-streaming/scripts/filters/, so go up 3 levels to get to project root
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent
CDC_STREAMING_DIR = PROJECT_ROOT / "cdc-streaming"

# Paths
FILTERS_CONFIG = CDC_STREAMING_DIR / "config" / "filters.json"
FILTER_SCHEMA = CDC_STREAMING_DIR / "schemas" / "filter-schema.json"
FLINK_OUTPUT_DIR = CDC_STREAMING_DIR / "flink-jobs" / "generated"
SPRING_OUTPUT_FILE = CDC_STREAMING_DIR / "stream-processor-spring" / "src" / "main" / "resources" / "filters.yml"


def escape_sql_string(value: Any) -> str:
    """Escape a value for use in SQL."""
    if isinstance(value, str):
        return f"'{value.replace(chr(39), chr(39) + chr(39))}'"
    return str(value)


def escape_sql_identifier(identifier: str) -> str:
    """Escape SQL identifier with backticks."""
    return f"`{identifier}`"


def generate_sql_condition(condition: Dict[str, Any], table_alias: str = "") -> str:
    """Generate SQL WHERE condition from filter condition."""
    field = condition["field"]
    operator = condition["operator"]
    field_ref = f"{table_alias}.{escape_sql_identifier(field)}" if table_alias else escape_sql_identifier(field)
    
    if operator == "equals":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} = {value}"
    elif operator == "in":
        values = [escape_sql_string(v) for v in condition["values"]]
        return f"{field_ref} IN ({', '.join(values)})"
    elif operator == "notIn":
        values = [escape_sql_string(v) for v in condition["values"]]
        return f"{field_ref} NOT IN ({', '.join(values)})"
    elif operator == "greaterThan":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} > {value}"
    elif operator == "lessThan":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} < {value}"
    elif operator == "greaterThanOrEqual":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} >= {value}"
    elif operator == "lessThanOrEqual":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} <= {value}"
    elif operator == "between":
        min_val = escape_sql_string(condition["min"])
        max_val = escape_sql_string(condition["max"])
        return f"{field_ref} BETWEEN {min_val} AND {max_val}"
    elif operator == "matches":
        value = escape_sql_string(condition["value"])
        return f"{field_ref} LIKE {value}"
    elif operator == "isNull":
        return f"{field_ref} IS NULL"
    elif operator == "isNotNull":
        return f"{field_ref} IS NOT NULL"
    else:
        raise ValueError(f"Unsupported operator: {operator}")


def generate_flink_sql(filters: List[Dict[str, Any]]) -> str:
    """Generate Flink SQL from filter configurations."""
    lines = []
    
    # Header
    lines.append("-- Generated Flink SQL Statements for Event Headers Filtering and Routing")
    lines.append(f"-- Generated at: {datetime.now().isoformat()}")
    lines.append("-- Source: config/filters.json")
    lines.append("-- DO NOT EDIT MANUALLY - This file is auto-generated")
    lines.append("")
    lines.append("-- Source: event_headers table from Aurora PostgreSQL")
    lines.append("-- Target: Filtered Kafka topics for each event type (with -flink suffix)")
    lines.append("")
    lines.append("-- NOTE: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor.")
    lines.append("-- Consumers should subscribe to the appropriate topic based on which processor is active.")
    lines.append("")
    lines.append("-- DEPLOYMENT NOTE: Deploy statements in order:")
    lines.append("-- 1. Source table (raw-event-headers)")
    lines.append("-- 2. Sink tables (filtered-*-events-flink)")
    lines.append("-- 3. INSERT statements (one per filter)")
    lines.append("")
    
    # Source table
    lines.append("-- ============================================================================")
    lines.append("-- Step 1: Create Source Table")
    lines.append("-- ============================================================================")
    lines.append("CREATE TABLE `raw-event-headers` (")
    lines.append("    `id` STRING,")
    lines.append("    `event_name` STRING,")
    lines.append("    `event_type` STRING,")
    lines.append("    `created_date` STRING,")
    lines.append("    `saved_date` STRING,")
    lines.append("    `header_data` STRING,")
    lines.append("    `__op` STRING,")
    lines.append("    `__table` STRING,")
    lines.append("    `__ts_ms` BIGINT")
    lines.append(") WITH (")
    lines.append("    'connector' = 'confluent',")
    lines.append("    'value.format' = 'json',")
    lines.append("    'scan.startup.mode' = 'earliest-offset'")
    lines.append(");")
    lines.append("")
    
    # Sink tables
    lines.append("-- ============================================================================")
    lines.append("-- Step 2: Create Sink Tables")
    lines.append("-- ============================================================================")
    lines.append("")
    
    # Filter out disabled, deleted, or pending_deletion filters
    enabled_filters = []
    deprecated_filters = []
    for f in filters:
        status = f.get("status", "pending_approval")
        enabled = f.get("enabled", True)
        
        # Skip deleted or disabled filters
        if status == "deleted" or not enabled:
            continue
        
        # Track deprecated filters for warnings
        if status == "deprecated":
            deprecated_filters.append(f.get("id", "unknown"))
        
        enabled_filters.append(f)
    
    # Add warnings for deprecated filters
    if deprecated_filters:
        lines.append("-- WARNING: The following filters are deprecated and may be removed soon:")
        for filter_id in deprecated_filters:
            lines.append(f"--   - {filter_id}")
        lines.append("")
    
    for filter_config in enabled_filters:
        filter_id = filter_config["id"]
        output_topic = filter_config["outputTopic"]
        flink_topic = f"{output_topic}-flink"
        name = filter_config.get("name", filter_id)
        
        lines.append(f"-- Sink Table: {name} Filter (Flink)")
        lines.append(f"-- Note: Flink writes to -flink suffixed topics to distinguish from Spring Boot processor")
        lines.append(f"CREATE TABLE `{flink_topic}` (")
        lines.append("    `key` BYTES,")
        lines.append("    `id` STRING,")
        lines.append("    `event_name` STRING,")
        lines.append("    `event_type` STRING,")
        lines.append("    `created_date` STRING,")
        lines.append("    `saved_date` STRING,")
        lines.append("    `header_data` STRING,")
        lines.append("    `__op` STRING,")
        lines.append("    `__table` STRING")
        lines.append(") WITH (")
        lines.append("    'connector' = 'confluent',")
        lines.append("    'value.format' = 'json-registry'")
        lines.append(");")
        lines.append("")
    
    # INSERT statements
    lines.append("-- ============================================================================")
    lines.append("-- Step 3: Deploy INSERT Statements (one per filter)")
    lines.append("-- ============================================================================")
    lines.append("")
    
    for filter_config in enabled_filters:
        filter_id = filter_config["id"]
        output_topic = filter_config["outputTopic"]
        flink_topic = f"{output_topic}-flink"
        name = filter_config.get("name", filter_id)
        description = filter_config.get("description", "")
        conditions = filter_config.get("conditions", [])
        condition_logic = filter_config.get("conditionLogic", "AND")
        
        lines.append(f"-- INSERT Statement: {name}")
        if description:
            lines.append(f"-- {description}")
        lines.append(f"-- Writes to {flink_topic} topic")
        lines.append(f"INSERT INTO `{flink_topic}`")
        lines.append("SELECT ")
        lines.append("    CAST(`id` AS BYTES) AS `key`,")
        lines.append("    `id`,")
        lines.append("    `event_name`,")
        lines.append("    `event_type`,")
        lines.append("    `created_date`,")
        lines.append("    `saved_date`,")
        lines.append("    `header_data`,")
        lines.append("    `__op`,")
        lines.append("    `__table`")
        lines.append("FROM `raw-event-headers`")
        
        # Build WHERE clause
        if conditions:
            where_parts = []
            for i, condition in enumerate(conditions):
                if i == 0:
                    # First condition doesn't need logical operator
                    where_parts.append(generate_sql_condition(condition))
                else:
                    # Subsequent conditions use filter-level conditionLogic
                    sql_condition = generate_sql_condition(condition)
                    where_parts.append(f"{condition_logic} {sql_condition}")
            
            lines.append(f"WHERE {' '.join(where_parts)};")
        else:
            lines.append(";")
        
        lines.append("")
    
    return "\n".join(lines)


def generate_spring_yaml(filters: List[Dict[str, Any]]) -> str:
    """Generate Spring Boot YAML configuration from filter configurations."""
    lines = []
    
    lines.append("# Generated Spring Boot Filter Configuration")
    lines.append(f"# Generated at: {datetime.now().isoformat()}")
    lines.append("# Source: config/filters.json")
    lines.append("# DO NOT EDIT MANUALLY - This file is auto-generated")
    lines.append("")
    
    # Filter out disabled, deleted, or pending_deletion filters
    enabled_filters = []
    deprecated_filters = []
    for f in filters:
        status = f.get("status", "pending_approval")
        enabled = f.get("enabled", True)
        
        # Skip deleted or disabled filters
        if status == "deleted" or not enabled:
            continue
        
        # Track deprecated filters for warnings
        if status == "deprecated":
            deprecated_filters.append(f.get("id", "unknown"))
        
        enabled_filters.append(f)
    
    # Add warnings for deprecated filters
    if deprecated_filters:
        lines.append("# WARNING: The following filters are deprecated and may be removed soon:")
        for filter_id in deprecated_filters:
            lines.append(f"#   - {filter_id}")
        lines.append("")
    
    lines.append("filters:")
    
    for filter_config in enabled_filters:
        filter_id = filter_config["id"]
        output_topic = filter_config["outputTopic"]
        spring_topic = f"{output_topic}-spring"
        conditions = filter_config.get("conditions", [])
        condition_logic = filter_config.get("conditionLogic", "AND")
        
        lines.append(f"  - id: {filter_id}")
        lines.append(f"    name: {filter_config.get('name', filter_id)}")
        if filter_config.get("description"):
            lines.append(f"    description: {filter_config.get('description')}")
        lines.append(f"    outputTopic: {spring_topic}")
        lines.append(f"    conditionLogic: {condition_logic}")
        lines.append("    conditions:")
        
        for condition in conditions:
            lines.append("      - field: " + condition["field"])
            lines.append("        operator: " + condition["operator"])
            if "value" in condition:
                value = condition["value"]
                if isinstance(value, str):
                    lines.append(f"        value: \"{value}\"")
                else:
                    lines.append(f"        value: {value}")
            if "values" in condition:
                lines.append("        values:")
                for val in condition["values"]:
                    if isinstance(val, str):
                        lines.append(f"          - \"{val}\"")
                    else:
                        lines.append(f"          - {val}")
            if "min" in condition:
                min_val = condition["min"]
                if isinstance(min_val, str):
                    lines.append(f"        min: \"{min_val}\"")
                else:
                    lines.append(f"        min: {min_val}")
            if "max" in condition:
                max_val = condition["max"]
                if isinstance(max_val, str):
                    lines.append(f"        max: \"{max_val}\"")
                else:
                    lines.append(f"        max: {max_val}")
            if "valueType" in condition:
                lines.append(f"        valueType: {condition['valueType']}")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Generate Flink SQL and Spring Boot YAML from filters.json")
    parser.add_argument("--dry-run", action="store_true", help="Generate output without writing files")
    parser.add_argument("--flink-only", action="store_true", help="Generate only Flink SQL")
    parser.add_argument("--spring-only", action="store_true", help="Generate only Spring YAML")
    args = parser.parse_args()
    
    # Load filters configuration
    if not FILTERS_CONFIG.exists():
        print(f"Error: Filters config not found: {FILTERS_CONFIG}", file=sys.stderr)
        sys.exit(1)
    
    with open(FILTERS_CONFIG, "r") as f:
        config = json.load(f)
    
    filters = config.get("filters", [])
    
    if not filters:
        print("Warning: No filters found in configuration", file=sys.stderr)
        sys.exit(0)
    
    # Generate Flink SQL
    if not args.spring_only:
        flink_sql = generate_flink_sql(filters)
        
        if args.dry_run:
            print("=== Flink SQL (dry-run) ===")
            print(flink_sql)
        else:
            FLINK_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
            output_file = FLINK_OUTPUT_DIR / "business-events-routing-confluent-cloud-generated.sql"
            with open(output_file, "w") as f:
                f.write(flink_sql)
            print(f"Generated Flink SQL: {output_file}")
    
    # Generate Spring YAML
    if not args.flink_only:
        spring_yaml = generate_spring_yaml(filters)
        
        if args.dry_run:
            print("\n=== Spring YAML (dry-run) ===")
            print(spring_yaml)
        else:
            SPRING_OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(SPRING_OUTPUT_FILE, "w") as f:
                f.write(spring_yaml)
            print(f"Generated Spring YAML: {SPRING_OUTPUT_FILE}")


if __name__ == "__main__":
    main()


#!/usr/bin/env python3
"""
Flink SQL Code Generator
Generates Flink SQL queries from YAML filter configurations.
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional

import yaml
import jsonschema
from jinja2 import Environment, FileSystemLoader, select_autoescape


class FilterConfigError(Exception):
    """Custom exception for filter configuration errors."""
    pass


# Import regex at module level
import re


class SQLGenerator:
    """Generates Flink SQL from YAML filter configurations."""
    
    def __init__(self, template_dir: str, schema_path: Optional[str] = None):
        """Initialize the SQL generator.
        
        Args:
            template_dir: Directory containing Jinja2 templates
            schema_path: Optional path to JSON schema for validation
        """
        self.template_dir = Path(template_dir)
        self.schema_path = Path(schema_path) if schema_path else None
        
        # Setup Jinja2 environment
        self.env = Environment(
            loader=FileSystemLoader(str(self.template_dir)),
            autoescape=select_autoescape(['html', 'xml']),
            trim_blocks=True,
            lstrip_blocks=True
        )
        
        # Load schema if provided
        self.schema = None
        if self.schema_path and self.schema_path.exists():
            with open(self.schema_path, 'r') as f:
                self.schema = json.load(f)
    
    def validate_yaml(self, config: Dict[str, Any]) -> None:
        """Validate YAML configuration against JSON schema.
        
        Args:
            config: Parsed YAML configuration
            
        Raises:
            FilterConfigError: If validation fails
        """
        if not self.schema:
            return
        
        try:
            jsonschema.validate(instance=config, schema=self.schema)
        except jsonschema.ValidationError as e:
            raise FilterConfigError(f"YAML validation failed: {e.message}") from e
        except jsonschema.SchemaError as e:
            raise FilterConfigError(f"Schema error: {e.message}") from e
    
    def translate_field_path(self, field: str) -> str:
        """Translate YAML field path to Flink SQL field path.
        
        Maps event structure fields to Debezium CDC format fields:
        - eventHeader.eventName -> derived from entity_type + __op
        - eventBody.entities[0].entityType -> entity_type
        - eventBody.entities[0].updatedAttributes.* -> data (JSON)
        - sourceMetadata.table -> __table
        - sourceMetadata.operation -> __op
        - sourceMetadata.timestamp -> __ts_ms
        
        Args:
            field: Field path from YAML (e.g., eventHeader.eventName)
            
        Returns:
            Flink SQL field path with backticks mapped to Debezium fields
        """
        # Map event structure to Debezium fields
        if field.startswith('eventHeader.eventName'):
            # eventName is derived from entity_type + __op, so we need special handling
            # For WHERE clauses, we'll check entity_type and __op separately
            return "`entity_type`"  # Will be combined with __op in condition generation
        elif field.startswith('eventBody.entities[') and '.entityType' in field:
            # eventBody.entities[0].entityType -> entity_type
            return "`entity_type`"
        elif field.startswith('eventBody.entities[') and '.updatedAttributes' in field:
            # eventBody.entities[0].updatedAttributes.* -> data (JSON field)
            # Extract the attribute path
            attr_match = re.search(r'updatedAttributes\.(.+)$', field)
            if attr_match:
                attr_path = attr_match.group(1)
                # For JSON access, we'll use JSON_VALUE or CAST
                return f"CAST(`data` AS MAP<STRING, STRING>)"
            return "`data`"
        elif field.startswith('sourceMetadata.table'):
            return "`__table`"
        elif field.startswith('sourceMetadata.operation'):
            return "`__op`"
        elif field.startswith('sourceMetadata.timestamp'):
            return "`__ts_ms`"
        elif field.startswith('eventHeader.'):
            # Other eventHeader fields - map to appropriate Debezium fields
            if 'createdDate' in field or 'savedDate' in field:
                return "`__ts_ms`"
            elif 'eventType' in field:
                return "`entity_type`"
            elif 'uuid' in field:
                return "`id`"
        
        # Handle array indices: entities[0] -> entities[1] (Flink uses 1-based indexing)
        # Pattern to match array indices like [0], [1], etc.
        def replace_index(match):
            idx = int(match.group(1))
            return f"[{idx + 1}]"  # Convert to 1-based
        
        # Replace array indices
        field = re.sub(r'\[(\d+)\]', replace_index, field)
        
        # Split by dots, but preserve array indices
        # Use regex to split on dots that are NOT inside brackets
        parts = []
        current_part = ""
        bracket_depth = 0
        
        for char in field:
            if char == '[':
                bracket_depth += 1
                current_part += char
            elif char == ']':
                bracket_depth -= 1
                current_part += char
            elif char == '.' and bracket_depth == 0:
                if current_part:
                    parts.append(current_part)
                current_part = ""
            else:
                current_part += char
        
        if current_part:
            parts.append(current_part)
        
        # Build SQL path
        sql_parts = []
        for part in parts:
            if not part:
                continue
            # If part contains brackets, keep them together
            if '[' in part:
                # Extract base name and bracket
                bracket_idx = part.index('[')
                base = part[:bracket_idx]
                bracket_part = part[bracket_idx:]
                if base:
                    sql_parts.append(f"`{base}`{bracket_part}")
                else:
                    sql_parts.append(bracket_part)
            else:
                sql_parts.append(f"`{part}`")
        
        return ".".join(sql_parts)
    
    def translate_map_access(self, field: str) -> str:
        """Translate field path that includes map access (updatedAttributes.key).
        
        Args:
            field: Field path that may include map keys
            
        Returns:
            SQL expression for map access
        """
        # Check if this is a map access pattern (e.g., eventBody.entities[0].updatedAttributes.loan.loanAmount)
        if 'updatedAttributes' in field:
            # Find where updatedAttributes starts
            idx = field.find('updatedAttributes')
            base_path = field[:idx].rstrip('.')
            map_key_path = field[idx + len('updatedAttributes'):].lstrip('.')
            
            # Translate base path (everything before updatedAttributes)
            if base_path:
                base_sql = self.translate_field_path(base_path)
                # Build map access: base.`updatedAttributes`['key']
                # Map keys use dot notation in YAML but need to be single key in SQL
                map_key = map_key_path.replace('.', '.')
                return f"{base_sql}.`updatedAttributes`['{map_key}']"
            else:
                # No base path, just map access
                map_key = map_key_path.replace('.', '.')
                return f"`updatedAttributes`['{map_key}']"
        
        return self.translate_field_path(field)
    
    def generate_condition(self, condition: Dict[str, Any], is_first: bool = False) -> str:
        """Generate SQL WHERE condition from YAML condition.
        
        Args:
            condition: Condition dictionary from YAML
            is_first: Whether this is the first condition (no logical operator prefix)
            
        Returns:
            SQL condition string
        """
        field = condition['field']
        operator = condition['operator']
        logical_op = condition.get('logicalOperator', 'AND')
        value_type = condition.get('valueType', 'string')
        
        # Translate field path
        field_sql = self.translate_map_access(field)
        
        # Generate condition based on operator
        if operator == 'equals':
            value = condition['value']
            # Special handling for eventName: map to entity_type + __op
            if 'eventHeader.eventName' in condition.get('field', ''):
                # Map event names like "CarCreated" to entity_type + __op
                if value.endswith('Created'):
                    entity_type = value[:-7]  # Remove "Created"
                    sql = f"(`entity_type` = '{entity_type}' AND `__op` = 'c')"
                elif value.endswith('Updated'):
                    entity_type = value[:-7]  # Remove "Updated"
                    sql = f"(`entity_type` = '{entity_type}' AND `__op` = 'u')"
                elif value.endswith('Deleted'):
                    entity_type = value[:-7]  # Remove "Deleted"
                    sql = f"(`entity_type` = '{entity_type}' AND `__op` = 'd')"
                elif value.endswith('Submitted'):
                    entity_type = value[:-9]  # Remove "Submitted"
                    sql = f"(`entity_type` = '{entity_type}' AND `__op` = 'c')"
                else:
                    # Fallback: just check entity_type
                    sql = f"`entity_type` = '{value}'"
            elif value_type == 'string':
                sql = f"{field_sql} = '{value}'"
            else:
                sql = f"{field_sql} = {value}"
        
        elif operator == 'in':
            values = condition['values']
            # Special handling for eventName: map to entity_type + __op combinations
            if 'eventHeader.eventName' in condition.get('field', ''):
                # Map event names like ["LoanCreated", "LoanPaymentSubmitted"] 
                # to (entity_type = 'Loan' AND __op = 'c') OR (entity_type = 'LoanPayment' AND __op = 'c')
                conditions = []
                for val in values:
                    if val.endswith('Created'):
                        entity_type = val[:-7]
                        conditions.append(f"(`entity_type` = '{entity_type}' AND `__op` = 'c')")
                    elif val.endswith('Updated'):
                        entity_type = val[:-7]
                        conditions.append(f"(`entity_type` = '{entity_type}' AND `__op` = 'u')")
                    elif val.endswith('Deleted'):
                        entity_type = val[:-7]
                        conditions.append(f"(`entity_type` = '{entity_type}' AND `__op` = 'd')")
                    elif val.endswith('Submitted'):
                        # Handle "LoanPaymentSubmitted" -> LoanPayment entity with op='c'
                        entity_type = val[:-9]  # Remove "Submitted"
                        conditions.append(f"(`entity_type` = '{entity_type}' AND `__op` = 'c')")
                    else:
                        # Fallback: just check entity_type
                        conditions.append(f"`entity_type` = '{val}'")
                sql = "(" + " OR ".join(conditions) + ")"
            elif value_type == 'string':
                values_str = ", ".join(f"'{v}'" for v in values)
                sql = f"{field_sql} IN ({values_str})"
            else:
                values_str = ", ".join(str(v) for v in values)
                sql = f"{field_sql} IN ({values_str})"
        
        elif operator == 'notIn':
            values = condition['values']
            if value_type == 'string':
                values_str = ", ".join(f"'{v}'" for v in values)
            else:
                values_str = ", ".join(str(v) for v in values)
            sql = f"{field_sql} NOT IN ({values_str})"
        
        elif operator == 'greaterThan':
            value = condition['value']
            if value_type == 'string':
                sql = f"CAST({field_sql} AS DOUBLE) > {value}"
            else:
                sql = f"{field_sql} > {value}"
        
        elif operator == 'lessThan':
            value = condition['value']
            if value_type == 'string':
                sql = f"CAST({field_sql} AS DOUBLE) < {value}"
            else:
                sql = f"{field_sql} < {value}"
        
        elif operator == 'greaterThanOrEqual':
            value = condition['value']
            if value_type == 'string':
                sql = f"CAST({field_sql} AS DOUBLE) >= {value}"
            else:
                sql = f"{field_sql} >= {value}"
        
        elif operator == 'lessThanOrEqual':
            value = condition['value']
            if value_type == 'string':
                sql = f"CAST({field_sql} AS DOUBLE) <= {value}"
            else:
                sql = f"{field_sql} <= {value}"
        
        elif operator == 'between':
            min_val = condition['min']
            max_val = condition['max']
            if value_type == 'string':
                sql = f"CAST({field_sql} AS DOUBLE) BETWEEN {min_val} AND {max_val}"
            else:
                sql = f"{field_sql} BETWEEN {min_val} AND {max_val}"
        
        elif operator == 'matches':
            pattern = condition['value']
            sql = f"REGEXP({field_sql}, '{pattern}')"
        
        elif operator == 'isNull':
            sql = f"{field_sql} IS NULL"
        
        elif operator == 'isNotNull':
            sql = f"{field_sql} IS NOT NULL"
        
        else:
            raise FilterConfigError(f"Unsupported operator: {operator}")
        
        return sql
    
    def generate_where_clause(self, filter_config: Dict[str, Any]) -> str:
        """Generate WHERE clause from filter conditions.
        
        Args:
            filter_config: Filter configuration dictionary
            
        Returns:
            SQL WHERE clause string
        """
        conditions = filter_config.get('conditions', [])
        if not conditions:
            return ""
        
        condition_logic = filter_config.get('conditionLogic', 'AND')
        
        # Generate individual conditions (without logical operators)
        condition_parts = []
        seen_entity_types = set()  # Track entity_type conditions to avoid redundancy
        
        for condition in conditions:
            cond_sql = self.generate_condition(condition, is_first=False)
            
            # Smart deduplication: if condition is "entity_type = 'X' AND __op = 'Y'"
            # and we already have a simpler "entity_type = 'X'" condition, skip the simpler one
            # OR if we have "entity_type = 'X' AND __op = 'Y'" and a new "entity_type = 'X'", skip the new one
            import re
            # Check if this is a simple entity_type condition
            simple_match = re.match(r"^`entity_type` = '([^']+)'$", cond_sql.strip())
            # Check if this is a compound condition with entity_type and __op
            compound_match = re.match(r"^\(`entity_type` = '([^']+)' AND `__op` = '([^']+)'\)$", cond_sql.strip())
            
            if simple_match:
                entity_type = simple_match.group(1)
                # If we already have a compound condition for this entity_type, skip the simple one
                if entity_type in seen_entity_types:
                    continue
                seen_entity_types.add(entity_type)
            elif compound_match:
                entity_type = compound_match.group(1)
                # If we have a compound condition, it implies the simple one, so track it
                seen_entity_types.add(entity_type)
                # Remove any simple conditions for this entity_type that we already added
                condition_parts = [c for c in condition_parts if not re.match(r"^`entity_type` = '{}'$".format(re.escape(entity_type)), c.strip())]
            
            condition_parts.append(cond_sql)
        
        # Combine with logic operator
        if condition_logic == 'OR':
            return " OR ".join(condition_parts)
        else:
            return " AND ".join(condition_parts)
    
    def generate_sql(self, config_path: str, output_path: str, 
                    kafka_bootstrap: str = "kafka:29092",
                    schema_registry_url: str = "http://schema-registry:8081",
                    confluent_cloud: bool = False,
                    schema_registry_api_key: str = None,
                    schema_registry_api_secret: str = None) -> None:
        """Generate Flink SQL from YAML configuration.
        
        Args:
            config_path: Path to YAML filter configuration
            output_path: Path to output SQL file
            kafka_bootstrap: Kafka bootstrap servers
            schema_registry_url: Schema Registry URL
            confluent_cloud: If True, generate Confluent Cloud-compatible SQL
            schema_registry_api_key: Schema Registry API key (required for Confluent Cloud)
            schema_registry_api_secret: Schema Registry API secret (required for Confluent Cloud)
        """
        # Load YAML configuration
        config_file = Path(config_path)
        if not config_file.exists():
            raise FileNotFoundError(f"Configuration file not found: {config_path}")
        
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
        
        # Validate configuration
        self.validate_yaml(config)
        
        # Filter only enabled filters
        enabled_filters = [f for f in config.get('filters', []) if f.get('enabled', True)]
        
        if not enabled_filters:
            print("Warning: No enabled filters found in configuration")
            return
        
        # Select template based on target platform
        if confluent_cloud:
            if not schema_registry_api_key or not schema_registry_api_secret:
                raise ValueError("schema_registry_api_key and schema_registry_api_secret are required for Confluent Cloud")
            # Use separate statements template for Confluent Cloud (CLI doesn't support STATEMENT SET well)
            template_name = 'routing-confluent-cloud-separate.sql.j2'
        else:
            template_name = 'routing.sql.j2'
        
        # Load template
        template = self.env.get_template(template_name)
        
        # Prepare template context
        context = {
            'filters': enabled_filters,
            'kafka_bootstrap': kafka_bootstrap,
            'schema_registry_url': schema_registry_url,
            'generator': self  # Pass generator for template functions
        }
        
        # Add Confluent Cloud specific context
        if confluent_cloud:
            context['schema_registry_api_key'] = schema_registry_api_key
            context['schema_registry_api_secret'] = schema_registry_api_secret
        
        # Generate SQL
        sql_content = template.render(**context)
        
        # Write output
        output_file = Path(output_path)
        output_file.parent.mkdir(parents=True, exist_ok=True)
        with open(output_file, 'w') as f:
            f.write(sql_content)
        
        print(f"Generated SQL file: {output_path}")
        print(f"Generated {len(enabled_filters)} filter queries")
        if confluent_cloud:
            print("Target: Confluent Cloud Flink")
        else:
            print("Target: Apache Flink")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Generate Flink SQL from YAML filter configurations'
    )
    parser.add_argument(
        '--config',
        type=str,
        default='flink-jobs/filters.yaml',
        help='Path to YAML filter configuration file (default: flink-jobs/filters.yaml)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default='flink-jobs/routing-generated.sql',
        help='Path to output SQL file (default: flink-jobs/routing-generated.sql)'
    )
    parser.add_argument(
        '--template-dir',
        type=str,
        default='scripts/templates',
        help='Directory containing Jinja2 templates (default: scripts/templates)'
    )
    parser.add_argument(
        '--schema',
        type=str,
        default='schemas/filter-schema.json',
        help='Path to JSON schema for validation (default: schemas/filter-schema.json)'
    )
    parser.add_argument(
        '--kafka-bootstrap',
        type=str,
        default='kafka:29092',
        help='Kafka bootstrap servers (default: kafka:29092)'
    )
    parser.add_argument(
        '--schema-registry',
        type=str,
        default='http://schema-registry:8081',
        help='Schema Registry URL (default: http://schema-registry:8081)'
    )
    parser.add_argument(
        '--no-validate',
        action='store_true',
        help='Skip YAML schema validation'
    )
    parser.add_argument(
        '--confluent-cloud',
        action='store_true',
        help='Generate SQL for Confluent Cloud Flink (uses confluent connector, removes PROCTIME, etc.)'
    )
    parser.add_argument(
        '--schema-registry-api-key',
        type=str,
        help='Schema Registry API key (required for Confluent Cloud)'
    )
    parser.add_argument(
        '--schema-registry-api-secret',
        type=str,
        help='Schema Registry API secret (required for Confluent Cloud)'
    )
    
    args = parser.parse_args()
    
    # Validate Confluent Cloud requirements
    if args.confluent_cloud:
        if not args.schema_registry_api_key or not args.schema_registry_api_secret:
            print("Error: --schema-registry-api-key and --schema-registry-api-secret are required for --confluent-cloud", file=sys.stderr)
            sys.exit(1)
    
    # Change to script directory for relative paths
    script_dir = Path(__file__).parent.parent
    os.chdir(script_dir)
    
    try:
        generator = SQLGenerator(
            template_dir=args.template_dir,
            schema_path=None if args.no_validate else args.schema
        )
        
        generator.generate_sql(
            config_path=args.config,
            output_path=args.output,
            kafka_bootstrap=args.kafka_bootstrap,
            schema_registry_url=args.schema_registry,
            confluent_cloud=args.confluent_cloud,
            schema_registry_api_key=args.schema_registry_api_key,
            schema_registry_api_secret=args.schema_registry_api_secret
        )
        
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()


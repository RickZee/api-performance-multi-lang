#!/usr/bin/env python3
"""
Filter Configuration Validator
Validates YAML filter configurations against JSON schema.
"""

import argparse
import json
import sys
from pathlib import Path

import yaml
import jsonschema


def validate_yaml_file(config_path: str, schema_path: str) -> bool:
    """Validate YAML configuration file against JSON schema.
    
    Args:
        config_path: Path to YAML configuration file
        schema_path: Path to JSON schema file
        
    Returns:
        True if valid, False otherwise
    """
    config_file = Path(config_path)
    schema_file = Path(schema_path)
    
    if not config_file.exists():
        print(f"Error: Configuration file not found: {config_path}", file=sys.stderr)
        return False
    
    if not schema_file.exists():
        print(f"Error: Schema file not found: {schema_path}", file=sys.stderr)
        return False
    
    # Load schema
    try:
        with open(schema_file, 'r') as f:
            schema = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON schema: {e}", file=sys.stderr)
        return False
    
    # Load and parse YAML
    try:
        with open(config_file, 'r') as f:
            config = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"Error: Invalid YAML: {e}", file=sys.stderr)
        return False
    
    # Validate
    try:
        jsonschema.validate(instance=config, schema=schema)
        print(f"✓ Configuration file is valid: {config_path}")
        return True
    except jsonschema.ValidationError as e:
        print(f"✗ Validation failed: {e.message}", file=sys.stderr)
        if e.path:
            print(f"  Path: {' -> '.join(str(p) for p in e.path)}", file=sys.stderr)
        return False
    except jsonschema.SchemaError as e:
        print(f"Error: Schema error: {e.message}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Validate YAML filter configurations against JSON schema'
    )
    parser.add_argument(
        '--config',
        type=str,
        default='flink-jobs/filters.yaml',
        help='Path to YAML filter configuration file (default: flink-jobs/filters.yaml)'
    )
    parser.add_argument(
        '--schema',
        type=str,
        default='schemas/filter-schema.json',
        help='Path to JSON schema file (default: schemas/filter-schema.json)'
    )
    
    args = parser.parse_args()
    
    success = validate_yaml_file(args.config, args.schema)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

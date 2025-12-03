#!/usr/bin/env python3
"""
SQL Syntax Validator
Basic validation of generated Flink SQL syntax.
"""

import argparse
import re
import sys
from pathlib import Path


def validate_sql_file(sql_path: str) -> bool:
    """Perform basic validation on Flink SQL file.
    
    Args:
        sql_path: Path to SQL file
        
    Returns:
        True if valid, False otherwise
    """
    sql_file = Path(sql_path)
    
    if not sql_file.exists():
        print(f"Error: SQL file not found: {sql_path}", file=sys.stderr)
        return False
    
    with open(sql_file, 'r') as f:
        content = f.read()
    
    errors = []
    warnings = []
    
    # Check for CREATE TABLE statements
    create_table_count = len(re.findall(r'CREATE TABLE', content, re.IGNORECASE))
    if create_table_count == 0:
        errors.append("No CREATE TABLE statements found")
    
    # Check for INSERT INTO statements
    insert_count = len(re.findall(r'INSERT INTO', content, re.IGNORECASE))
    if insert_count == 0:
        warnings.append("No INSERT INTO statements found")
    
    # Check for balanced parentheses in WHERE clauses
    where_clauses = re.findall(r'WHERE\s+(.+?)(?:;|$)', content, re.IGNORECASE | re.DOTALL)
    for where_clause in where_clauses:
        open_parens = where_clause.count('(')
        close_parens = where_clause.count(')')
        if open_parens != close_parens:
            errors.append(f"Unbalanced parentheses in WHERE clause: {where_clause[:50]}...")
    
    # Check for basic SQL syntax issues
    # Check for unclosed quotes
    single_quotes = content.count("'")
    if single_quotes % 2 != 0:
        warnings.append("Possible unclosed single quotes")
    
    # Check for backticks (should be balanced)
    backticks = content.count('`')
    if backticks % 2 != 0:
        warnings.append("Possible unclosed backticks")
    
    # Print results
    if errors:
        print("✗ Validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  Error: {error}", file=sys.stderr)
        return False
    
    if warnings:
        print("⚠ Warnings:")
        for warning in warnings:
            print(f"  {warning}")
    
    print(f"✓ SQL file passed basic validation: {sql_path}")
    print(f"  Found {create_table_count} CREATE TABLE statements")
    print(f"  Found {insert_count} INSERT INTO statements")
    return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Validate Flink SQL syntax'
    )
    parser.add_argument(
        '--sql',
        type=str,
        default='flink-jobs/routing-generated.sql',
        help='Path to SQL file (default: flink-jobs/routing-generated.sql)'
    )
    
    args = parser.parse_args()
    
    success = validate_sql_file(args.sql)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()





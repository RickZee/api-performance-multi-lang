#!/usr/bin/env python3
"""
Validate DSQL database from EC2 instance.
This script should be run on the EC2 instance via SSM.
"""

import subprocess
import sys
import os

DSQL_HOST = os.getenv("DSQL_HOST", "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

def run_query(query):
    """Run a SQL query against DSQL."""
    # Generate auth token
    token_cmd = [
        "aws", "dsql", "generate-db-connect-admin-auth-token",
        "--region", AWS_REGION,
        "--hostname", DSQL_HOST
    ]
    
    try:
        result = subprocess.run(token_cmd, capture_output=True, text=True, check=True)
        token = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error generating token: {e.stderr}", file=sys.stderr)
        return None
    
    # Run psql query
    env = os.environ.copy()
    env["PGPASSWORD"] = token
    
    psql_cmd = [
        "psql", "-h", DSQL_HOST, "-U", "admin", "-d", "postgres", "-p", "5432", "-t", "-c", query
    ]
    
    try:
        result = subprocess.run(psql_cmd, env=env, capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running query: {e.stderr}", file=sys.stderr)
        return None

def main():
    print("=== DSQL Database Validation ===\n")
    
    # Table counts
    print("Table Counts:")
    print("-" * 50)
    
    tables = [
        ("business_events", "SELECT COUNT(*) FROM business_events"),
        ("event_headers", "SELECT COUNT(*) FROM event_headers"),
        ("car_entities", "SELECT COUNT(*) FROM car_entities"),
        ("loan_entities", "SELECT COUNT(*) FROM loan_entities"),
        ("loan_payment_entities", "SELECT COUNT(*) FROM loan_payment_entities"),
        ("service_record_entities", "SELECT COUNT(*) FROM service_record_entities"),
    ]
    
    for table_name, query in tables:
        count = run_query(query)
        if count is not None:
            print(f"  {table_name:30s}: {count}")
        else:
            print(f"  {table_name:30s}: ERROR")
    
    print("\n" + "-" * 50)
    
    # Events by name
    print("\nEvents by Event Name:")
    print("-" * 50)
    event_query = """
        SELECT event_name, COUNT(*) as count 
        FROM business_events 
        GROUP BY event_name 
        ORDER BY event_name
    """
    result = run_query(event_query)
    if result:
        for line in result.split('\n'):
            if line.strip() and '|' in line:
                parts = line.strip().split('|')
                if len(parts) >= 2:
                    print(f"  {parts[0].strip():30s}: {parts[1].strip()}")
    
    print("\n" + "-" * 50)
    print("\nValidation complete!")

if __name__ == "__main__":
    main()

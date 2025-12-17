#!/usr/bin/env python3
"""Validate data in DSQL database after k6 batch test."""

import boto3
import subprocess
import sys
import os

DSQL_HOST = os.getenv("DSQL_HOST", "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

def generate_auth_token():
    """Generate DSQL admin auth token."""
    try:
        result = subprocess.run(
            ["aws", "dsql", "generate-db-connect-admin-auth-token", 
             "--region", AWS_REGION, "--hostname", DSQL_HOST],
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error generating auth token: {e.stderr}", file=sys.stderr)
        sys.exit(1)

def run_query(query):
    """Run a SQL query against DSQL."""
    token = generate_auth_token()
    env = os.environ.copy()
    env["PGPASSWORD"] = token
    
    try:
        result = subprocess.run(
            ["psql", "-h", DSQL_HOST, "-U", "admin", "-d", "postgres", "-p", "5432", "-t", "-c", query],
            env=env,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running query: {e.stderr}", file=sys.stderr)
        return None
    except FileNotFoundError:
        print("Error: psql not found. Please install PostgreSQL client.", file=sys.stderr)
        sys.exit(1)

def main():
    print("=== Validating DSQL Database Data ===\n")
    
    # Count all tables
    print("Table Counts:")
    print("-" * 40)
    
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
    
    print("\n" + "-" * 40)
    
    # Count by event name
    print("\nEvents by Event Name:")
    print("-" * 40)
    event_counts = run_query("SELECT event_name, COUNT(*) as count FROM business_events GROUP BY event_name ORDER BY event_name;")
    if event_counts:
        for line in event_counts.split('\n'):
            if line.strip():
                parts = line.strip().split('|')
                if len(parts) == 2:
                    print(f"  {parts[0].strip():30s}: {parts[1].strip()}")
    
    print("\n" + "-" * 40)
    print("\nValidation complete!")

if __name__ == "__main__":
    main()

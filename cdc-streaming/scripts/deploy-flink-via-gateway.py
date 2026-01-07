#!/usr/bin/env python3
"""
Deploy Flink SQL statements via SQL Gateway REST API
Properly handles JSON escaping and creates persistent streaming jobs
"""

import json
import sys
import time
import requests
from pathlib import Path

GATEWAY_URL = "http://localhost:28083/v1"
SQL_FILE = Path(__file__).parent.parent / "flink-jobs" / "business-events-routing-local-docker.sql"

def create_session():
    """Create a new SQL Gateway session"""
    response = requests.post(f"{GATEWAY_URL}/sessions")
    response.raise_for_status()
    return response.json()["sessionHandle"]

def execute_statement(session_handle, statement):
    """Execute a SQL statement via SQL Gateway"""
    payload = {"statement": statement}
    response = requests.post(
        f"{GATEWAY_URL}/sessions/{session_handle}/statements",
        json=payload,
        headers={"Content-Type": "application/json"}
    )
    
    if response.status_code != 200:
        error_msg = response.json().get("errors", ["Unknown error"])
        raise Exception(f"Failed to execute statement: {error_msg}")
    
    result = response.json()
    operation_handle = result.get("operationHandle")
    
    # For INSERT statements, check operation status after a delay
    if "INSERT" in statement.upper():
        time.sleep(3)
        status_response = requests.get(
            f"{GATEWAY_URL}/sessions/{session_handle}/operations/{operation_handle}/status"
        )
        if status_response.status_code == 200:
            status = status_response.json().get("status")
            if status == "ERROR":
                # Try to get error details
                try:
                    error_response = requests.get(
                        f"{GATEWAY_URL}/sessions/{session_handle}/operations/{operation_handle}/result/0"
                    )
                    if error_response.status_code == 200:
                        errors = error_response.json().get("errors", [])
                        if errors:
                            print(f"    ⚠ Warning: Operation status is ERROR")
                            print(f"    Error: {errors[0][:200]}...")
                except:
                    pass
    
    return operation_handle

def parse_sql_file(sql_file):
    """Parse SQL file into CREATE TABLE and INSERT statements"""
    with open(sql_file, 'r') as f:
        content = f.read()
    
    # Split by semicolons and filter out comments
    statements = []
    current_statement = ""
    in_comment = False
    
    for line in content.split('\n'):
        # Skip full-line comments
        stripped = line.strip()
        if stripped.startswith('--'):
            continue
        
        # Remove inline comments
        if '--' in line:
            line = line[:line.index('--')]
        
        current_statement += line + '\n'
        
        # Check if statement ends with semicolon
        if ';' in line:
            stmt = current_statement.strip()
            if stmt and not stmt.startswith('--'):
                statements.append(stmt)
            current_statement = ""
    
    # Add last statement if any
    if current_statement.strip():
        statements.append(current_statement.strip())
    
    # Separate CREATE TABLE and INSERT statements
    create_statements = [s for s in statements if s.upper().startswith('CREATE TABLE')]
    insert_statements = [s for s in statements if s.upper().startswith('INSERT INTO')]
    
    return create_statements, insert_statements

def main():
    print("=" * 50)
    print("Deploy Flink SQL via SQL Gateway")
    print("=" * 50)
    print(f"Gateway URL: {GATEWAY_URL}")
    print(f"SQL File: {SQL_FILE}")
    print()
    
    # Check if SQL Gateway is available
    try:
        response = requests.get(f"{GATEWAY_URL}/info", timeout=5)
        response.raise_for_status()
        print("✓ SQL Gateway is running")
    except Exception as e:
        print(f"✗ SQL Gateway is not available: {e}")
        sys.exit(1)
    
    # Check if SQL file exists
    if not SQL_FILE.exists():
        print(f"✗ SQL file not found: {SQL_FILE}")
        sys.exit(1)
    
    # Parse SQL file
    print("Parsing SQL file...")
    create_statements, insert_statements = parse_sql_file(SQL_FILE)
    print(f"Found {len(create_statements)} CREATE TABLE statement(s)")
    print(f"Found {len(insert_statements)} INSERT statement(s)")
    print()
    
    # Create session
    print("Creating SQL Gateway session...")
    session_handle = create_session()
    print(f"✓ Session created: {session_handle}")
    print()
    
    # Set execution mode to streaming (submit separately)
    print("Step 1: Setting execution mode to streaming...")
    try:
        execute_statement(session_handle, "SET execution.runtime-mode = 'streaming';")
        print("  ✓ Execution mode set to streaming")
    except Exception as e:
        print(f"  ⚠ Warning: Could not set execution mode: {e}")
    print()
    
    # Execute CREATE TABLE statements
    print("Step 2: Creating tables...")
    for i, stmt in enumerate(create_statements, 1):
        try:
            print(f"  Creating table {i}/{len(create_statements)}...")
            execute_statement(session_handle, stmt)
            print(f"  ✓ Table {i} created")
        except Exception as e:
            if "already exists" in str(e).lower():
                print(f"  ⚠ Table {i} already exists (OK)")
            else:
                print(f"  ✗ Error: {e}")
    print()
    
    # Execute INSERT statements (these create persistent jobs)
    # Remove any SET statements from INSERT (they must be submitted separately)
    print("Step 3: Submitting INSERT statements as persistent jobs...")
    operation_handles = []
    for i, stmt in enumerate(insert_statements, 1):
        try:
            # Remove SET statements from INSERT (submit separately)
            clean_stmt = stmt
            if "SET" in stmt.upper() and "INSERT" in stmt.upper():
                # Extract just the INSERT part
                if "INSERT" in stmt.upper():
                    insert_part = stmt.upper().split("INSERT")[1]
                    clean_stmt = "INSERT" + stmt.split("INSERT")[1]
                    # Remove any leading SET statements
                    if clean_stmt.strip().upper().startswith("SET"):
                        lines = clean_stmt.split('\n')
                        clean_stmt = '\n'.join([l for l in lines if not l.strip().upper().startswith("SET")])
            
            # Extract table name for logging
            table_name = "unknown"
            if "INSERT INTO" in clean_stmt.upper():
                parts = clean_stmt.split("INSERT INTO")[1].split()[0]
                table_name = parts.strip('`')
            
            print(f"  Submitting job {i}/{len(insert_statements)}: {table_name}...")
            operation_handle = execute_statement(session_handle, clean_stmt)
            operation_handles.append(operation_handle)
            print(f"  ✓ Job {i} submitted (operation: {operation_handle})")
            time.sleep(2)  # Brief pause between submissions
        except Exception as e:
            print(f"  ✗ Error submitting job {i}: {e}")
    print()
    
    print("=" * 50)
    print("✓ Deployment completed!")
    print(f"  - {len(create_statements)} tables created")
    print(f"  - {len(operation_handles)} jobs submitted")
    print()
    print("Next steps:")
    print("  1. Check Flink jobs: docker exec cdc-local-flink-jobmanager /opt/flink/bin/flink list")
    print("  2. Verify in REST API: curl -s http://localhost:8082/jobs | jq '.'")
    print("  3. Check Flink Web UI: http://localhost:8082")
    print("=" * 50)

if __name__ == "__main__":
    main()


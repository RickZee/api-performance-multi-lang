#!/usr/bin/env python3
"""Validate data in Aurora PostgreSQL database after k6 batch test."""

import psycopg2
import sys
import os
from typing import Optional, Dict, List, Tuple

# Get connection details from environment or terraform
AURORA_ENDPOINT = os.getenv("AURORA_ENDPOINT", "producer-api-aurora-cluster.cluster-chjum3h144b6.us-east-1.rds.amazonaws.com")
AURORA_USER = os.getenv("AURORA_USER", "postgres")
AURORA_PASSWORD = os.getenv("AURORA_PASSWORD", "")
AURORA_DATABASE = os.getenv("AURORA_DATABASE", "car_entities")

def get_connection():
    """Get database connection."""
    if not AURORA_PASSWORD:
        print("Error: AURORA_PASSWORD environment variable not set", file=sys.stderr)
        sys.exit(1)
    
    try:
        conn = psycopg2.connect(
            host=AURORA_ENDPOINT,
            port=5432,
            database=AURORA_DATABASE,
            user=AURORA_USER,
            password=AURORA_PASSWORD,
            connect_timeout=10
        )
        return conn
    except Exception as e:
        print(f"Error connecting to database: {e}", file=sys.stderr)
        sys.exit(1)

def run_query(conn, query: str) -> Optional[str]:
    """Run a SQL query and return result."""
    try:
        cur = conn.cursor()
        cur.execute(query)
        if cur.rowcount == 0:
            return None
        if cur.description and len(cur.description[0]) == 1:
            # Single column result
            result = cur.fetchone()
            return str(result[0]) if result else None
        else:
            # Multi-column result
            rows = cur.fetchall()
            return '\n'.join([' | '.join(str(cell) for cell in row) for row in rows])
    except Exception as e:
        print(f"Error running query: {e}", file=sys.stderr)
        return None
    finally:
        cur.close()

def validate_business_logic(conn) -> Tuple[bool, List[str]]:
    """Validate business logic rules."""
    issues = []
    
    # 1. Check that all events have corresponding event headers
    query = """
    SELECT COUNT(*) FROM business_events b
    WHERE NOT EXISTS (
        SELECT 1 FROM event_headers e WHERE e.id = b.id
    );
    """
    orphaned_events = run_query(conn, query)
    if orphaned_events and int(orphaned_events) > 0:
        issues.append(f"Found {orphaned_events} business_events without event_headers")
    
    # 2. Check that all entities have valid event_id references
    query = """
    SELECT COUNT(*) FROM (
        SELECT event_id FROM car_entities
        UNION ALL
        SELECT event_id FROM loan_entities
        UNION ALL
        SELECT event_id FROM loan_payment_entities
        UNION ALL
        SELECT event_id FROM service_record_entities
    ) e
    WHERE e.event_id IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM event_headers h WHERE h.id = e.event_id
    );
    """
    orphaned_entities = run_query(conn, query)
    if orphaned_entities and int(orphaned_entities) > 0:
        issues.append(f"Found {orphaned_entities} entities with invalid event_id references")
    
    # 3. Check that loans reference valid cars
    query = """
    SELECT COUNT(*) FROM loan_entities l
    WHERE l.entity_data->>'carId' IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM car_entities c 
        WHERE c.entity_id = l.entity_data->>'carId'
    );
    """
    invalid_loan_cars = run_query(conn, query)
    if invalid_loan_cars and int(invalid_loan_cars) > 0:
        issues.append(f"Found {invalid_loan_cars} loans referencing non-existent cars")
    
    # 4. Check that payments reference valid loans
    query = """
    SELECT COUNT(*) FROM loan_payment_entities p
    WHERE p.entity_data->>'loanId' IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM loan_entities l 
        WHERE l.entity_id = p.entity_data->>'loanId'
    );
    """
    invalid_payment_loans = run_query(conn, query)
    if invalid_payment_loans and int(invalid_payment_loans) > 0:
        issues.append(f"Found {invalid_payment_loans} payments referencing non-existent loans")
    
    # 5. Check that service records reference valid cars
    query = """
    SELECT COUNT(*) FROM service_record_entities s
    WHERE s.entity_data->>'carId' IS NOT NULL
    AND NOT EXISTS (
        SELECT 1 FROM car_entities c 
        WHERE c.entity_id = s.entity_data->>'carId'
    );
    """
    invalid_service_cars = run_query(conn, query)
    if invalid_service_cars and int(invalid_service_cars) > 0:
        issues.append(f"Found {invalid_service_cars} service records referencing non-existent cars")
    
    return len(issues) == 0, issues

def main():
    print("=== Validating Aurora PostgreSQL Database Data ===\n")
    
    conn = get_connection()
    
    try:
        # Count all tables
        print("Table Counts:")
        print("-" * 60)
        
        tables = [
            ("business_events", "SELECT COUNT(*) FROM business_events"),
            ("event_headers", "SELECT COUNT(*) FROM event_headers"),
            ("car_entities", "SELECT COUNT(*) FROM car_entities"),
            ("loan_entities", "SELECT COUNT(*) FROM loan_entities"),
            ("loan_payment_entities", "SELECT COUNT(*) FROM loan_payment_entities"),
            ("service_record_entities", "SELECT COUNT(*) FROM service_record_entities"),
        ]
        
        counts = {}
        for table_name, query in tables:
            count = run_query(conn, query)
            counts[table_name] = int(count) if count else 0
            print(f"  {table_name:30s}: {count if count else '0'}")
        
        print("\n" + "-" * 60)
        
        # Count by event name
        print("\nEvents by Event Name:")
        print("-" * 60)
        event_counts_query = """
        SELECT event_name, COUNT(*) as count 
        FROM business_events 
        GROUP BY event_name 
        ORDER BY event_name;
        """
        event_counts = run_query(conn, event_counts_query)
        if event_counts:
            for line in event_counts.split('\n'):
                if line.strip():
                    parts = line.strip().split(' | ')
                    if len(parts) == 2:
                        print(f"  {parts[0].strip():30s}: {parts[1].strip()}")
        
        print("\n" + "-" * 60)
        
        # Validate business logic
        print("\nBusiness Logic Validation:")
        print("-" * 60)
        is_valid, issues = validate_business_logic(conn)
        
        if is_valid:
            print("  ✅ All business logic rules passed")
        else:
            print("  ❌ Business logic validation issues found:")
            for issue in issues:
                print(f"    - {issue}")
        
        print("\n" + "-" * 60)
        
        # Expected counts (5 events per type = 20 total)
        print("\nExpected vs Actual:")
        print("-" * 60)
        expected_events = 20
        actual_events = counts.get('business_events', 0)
        print(f"  Business Events: {actual_events}/{expected_events} {'✅' if actual_events >= expected_events else '⚠️'}")
        
        expected_cars = 5
        actual_cars = counts.get('car_entities', 0)
        print(f"  Car Entities: {actual_cars}/{expected_cars} {'✅' if actual_cars >= expected_cars else '⚠️'}")
        
        expected_loans = 5
        actual_loans = counts.get('loan_entities', 0)
        print(f"  Loan Entities: {actual_loans}/{expected_loans} {'✅' if actual_loans >= expected_loans else '⚠️'}")
        
        expected_payments = 5
        actual_payments = counts.get('loan_payment_entities', 0)
        print(f"  Payment Entities: {actual_payments}/{expected_payments} {'✅' if actual_payments >= expected_payments else '⚠️'}")
        
        expected_services = 5
        actual_services = counts.get('service_record_entities', 0)
        print(f"  Service Entities: {actual_services}/{expected_services} {'✅' if actual_services >= expected_services else '⚠️'}")
        
        print("\n" + "-" * 60)
        print("\nValidation complete!")
        
        if not is_valid or actual_events < expected_events:
            sys.exit(1)
        
    finally:
        conn.close()

if __name__ == "__main__":
    main()

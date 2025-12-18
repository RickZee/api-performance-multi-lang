#!/usr/bin/env python3
"""Validate events in Aurora PostgreSQL database.
Checks event_headers and business_events tables for submitted events.

Usage:
    python3 validate-database-events.py --aurora-endpoint <endpoint> \\
        --aurora-password <password> --db-name <name> --db-user <user> \\
        --events-file <file>

Example:
    python3 validate-database-events.py \\
        --aurora-endpoint cluster.xxxxx.us-east-1.rds.amazonaws.com \\
        --aurora-password mypassword \\
        --db-name car_entities \\
        --db-user postgres \\
        --events-file /tmp/events.json
"""

import argparse
import json
import sys
import os
from typing import Dict, List, Optional

try:
    import psycopg2
except ImportError:
    print("Error: psycopg2 not found. Install with: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)


def validate_event(
    conn,
    event_uuid: str,
    event_type: str,
    event_name: str
) -> tuple[bool, Optional[str]]:
    """Validate a single event in the database.
    
    Returns:
        (is_valid, error_message)
    """
    try:
        cur = conn.cursor()
        
        # Check event_headers table
        cur.execute("SELECT COUNT(*) FROM event_headers WHERE id = %s", (event_uuid,))
        header_count = cur.fetchone()[0]
        
        if header_count == 0:
            return False, f"Event {event_uuid} not found in event_headers table"
        
        # Verify event_type matches
        cur.execute("SELECT event_type FROM event_headers WHERE id = %s", (event_uuid,))
        db_event_type = cur.fetchone()[0]
        
        if db_event_type != event_type:
            return False, f"Event type mismatch: expected {event_type}, found {db_event_type}"
        
        # Verify header_data is populated
        cur.execute("SELECT header_data::text FROM event_headers WHERE id = %s", (event_uuid,))
        header_data = cur.fetchone()[0]
        
        if not header_data or header_data == "null":
            return False, "header_data is empty or null"
        
        # Check business_events table (optional - events may not be in business_events immediately)
        found_in_business = False
        try:
            cur.execute("SELECT COUNT(*) FROM business_events WHERE id = %s", (event_uuid,))
            business_count = cur.fetchone()[0]
            found_in_business = business_count > 0
        except Exception as be_error:
            # business_events table might not exist or have issues - that's okay
            pass
        
        cur.close()
        return True, None
        
    except Exception as e:
        return False, f"Database error: {str(e)}"


def validate_events(
    aurora_endpoint: str,
    aurora_password: str,
    db_name: str,
    db_user: str,
    events_file: str
) -> int:
    """Validate all events from the events file.
    
    Returns:
        Exit code: 0 if all events validated, 1 otherwise
    """
    # Load events file
    try:
        with open(events_file, 'r') as f:
            events = json.load(f)
    except FileNotFoundError:
        print(f"Error: Events file not found: {events_file}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in events file: {e}", file=sys.stderr)
        return 1
    
    if not events:
        print("Error: No events found in events file", file=sys.stderr)
        return 1
    
    # Connect to database
    try:
        conn = psycopg2.connect(
            host=aurora_endpoint,
            port=5432,
            database=db_name,
            user=db_user,
            password=aurora_password,
            connect_timeout=10
        )
    except psycopg2.OperationalError as e:
        print(f"Error: Failed to connect to database: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error: Database connection error: {e}", file=sys.stderr)
        return 1
    
    # Validate each event
    validated_count = 0
    missing_count = 0
    missing_events = []
    
    print(f"Validating {len(events)} events in database...")
    print("")
    
    for event in events:
        event_uuid = event.get('uuid')
        event_type = event.get('eventType')
        event_name = event.get('eventName', '')
        
        if not event_uuid:
            print(f"⚠ Warning: Event missing UUID, skipping")
            missing_count += 1
            continue
        
        print(f"Validating event: {event_uuid} ({event_type})")
        
        is_valid, error_msg = validate_event(conn, event_uuid, event_type, event_name)
        
        if is_valid:
            # Check if in business_events (optional)
            try:
                cur = conn.cursor()
                cur.execute("SELECT COUNT(*) FROM business_events WHERE id = %s", (event_uuid,))
                business_count = cur.fetchone()[0]
                cur.close()
                
                if business_count > 0:
                    print(f"  ✓ Event found in business_events table")
                else:
                    print(f"  ⚠ Event not found in business_events table (may be expected)")
            except Exception:
                pass
            
            print(f"  ✓ Event validated: {event_uuid}")
            validated_count += 1
        else:
            print(f"  ✗ {error_msg}")
            missing_count += 1
            missing_events.append(event_uuid)
        
        print("")
    
    conn.close()
    
    # Summary
    print("Validation Summary:")
    print(f"  Total events: {len(events)}")
    print(f"  Validated: {validated_count}")
    print(f"  Missing: {missing_count}")
    print("")
    
    if missing_count > 0:
        print("Missing event UUIDs:")
        for uuid in missing_events:
            print(f"  - {uuid}")
        return 1
    
    print("✓ All events validated in database")
    return 0


def main():
    parser = argparse.ArgumentParser(
        description='Validate events in Aurora PostgreSQL database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        '--aurora-endpoint',
        required=True,
        help='Aurora PostgreSQL endpoint (hostname)'
    )
    parser.add_argument(
        '--aurora-password',
        required=True,
        help='Aurora PostgreSQL password (or use AURORA_PASSWORD env var)'
    )
    parser.add_argument(
        '--db-name',
        default='car_entities',
        help='Database name (default: car_entities)'
    )
    parser.add_argument(
        '--db-user',
        default='postgres',
        help='Database user (default: postgres)'
    )
    parser.add_argument(
        '--events-file',
        required=True,
        help='Path to JSON file containing events to validate'
    )
    
    args = parser.parse_args()
    
    # Get password from argument or environment
    aurora_password = args.aurora_password or os.getenv('AURORA_PASSWORD') or os.getenv('DB_PASSWORD')
    
    if not aurora_password:
        print("Error: Aurora password required (use --aurora-password or AURORA_PASSWORD env var)", file=sys.stderr)
        return 1
    
    return validate_events(
        args.aurora_endpoint,
        aurora_password,
        args.db_name,
        args.db_user,
        args.events_file
    )


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Validate databases against sent events from k6 test."""

import json
import sys
import os
import subprocess
import argparse
from typing import Dict, List, Set, Optional
from collections import defaultdict

# Default events file path
DEFAULT_EVENTS_FILE = '/tmp/k6-sent-events.json'

def load_sent_events(events_file: str) -> List[Dict]:
    """Load sent events from JSON file."""
    try:
        with open(events_file, 'r') as f:
            events = json.load(f)
        return events
    except FileNotFoundError:
        print(f"Error: Events file not found: {events_file}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in events file: {e}")
        sys.exit(1)

def validate_aurora(events: List[Dict], aurora_endpoint: str, aurora_password: str) -> Dict:
    """Validate events in Aurora PostgreSQL database."""
    import asyncpg
    import asyncio
    
    results = {
        'total_sent': len(events),
        'found': 0,
        'missing': [],
        'by_event_type': defaultdict(int),
        'by_entity_type': defaultdict(int),
        'errors': []
    }
    
    async def validate():
        try:
            database_url = f"postgresql://postgres:{aurora_password}@{aurora_endpoint}:5432/car_entities"
            conn = await asyncpg.connect(database_url, command_timeout=30)
            
            try:
                # Get all event UUIDs from database
                db_uuids = await conn.fetch("SELECT id, event_name, event_type FROM event_headers")
                db_uuid_set = {row['id'] for row in db_uuids}
                
                # Get entity IDs by type
                entity_queries = {
                    'Car': "SELECT entity_id FROM car_entities",
                    'Loan': "SELECT entity_id FROM loan_entities",
                    'LoanPayment': "SELECT entity_id FROM loan_payment_entities",
                    'ServiceRecord': "SELECT entity_id FROM service_record_entities"
                }
                
                entity_sets = {}
                for entity_type, query in entity_queries.items():
                    rows = await conn.fetch(query)
                    entity_sets[entity_type] = {row['entity_id'] for row in rows}
                
                # Validate each sent event
                for event in events:
                    uuid = event.get('uuid')
                    event_type = event.get('eventType', '')
                    entity_type = event.get('entityType', '')
                    entity_id = event.get('entityId', '')
                    
                    if uuid in db_uuid_set:
                        results['found'] += 1
                        results['by_event_type'][event_type] += 1
                        if entity_type and entity_id:
                            results['by_entity_type'][entity_type] += 1
                    else:
                        results['missing'].append({
                            'uuid': uuid,
                            'eventType': event_type,
                            'entityType': entity_type,
                            'entityId': entity_id
                        })
                
            finally:
                await conn.close()
                
        except Exception as e:
            results['errors'].append(f"Aurora validation error: {str(e)}")
    
    asyncio.run(validate())
    return results

def validate_dsql(events: List[Dict], query_script: str) -> Dict:
    """Validate events in DSQL database using query script."""
    results = {
        'total_sent': len(events),
        'found': 0,
        'missing': [],
        'by_event_type': defaultdict(int),
        'by_entity_type': defaultdict(int),
        'errors': []
    }
    
    try:
        # Get all UUIDs from sent events
        sent_uuids = {event.get('uuid') for event in events if event.get('uuid')}
        
        if not sent_uuids:
            results['errors'].append("No UUIDs found in sent events")
            return results
        
        # Query DSQL for event headers - use IN clause with proper escaping
        # Build query with UUIDs
        uuid_list = "','".join(sent_uuids)
        query = f"""
        SELECT id, event_name, event_type 
        FROM event_headers 
        WHERE id IN ('{uuid_list}')
        """
        
        # Run query via bastion host
        result = subprocess.run(
            [query_script, query],
            capture_output=True,
            text=True,
            timeout=60
        )
        
        if result.returncode != 0:
            results['errors'].append(f"DSQL query failed: {result.stderr}")
            return results
        
        # Parse results
        output = result.stdout.strip()
        if not output:
            results['errors'].append("DSQL query returned no results")
            return results
        
        # Extract UUIDs from query results
        found_uuids = set()
        for line in output.split('\n'):
            if line.strip() and '|' in line:
                # Parse line format: uuid | event_name | event_type
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= 1 and parts[0]:
                    found_uuids.add(parts[0])
        
        # Validate each sent event
        for event in events:
            uuid = event.get('uuid')
            event_type = event.get('eventType', '')
            entity_type = event.get('entityType', '')
            entity_id = event.get('entityId', '')
            
            if uuid in found_uuids:
                results['found'] += 1
                results['by_event_type'][event_type] += 1
                if entity_type and entity_id:
                    results['by_entity_type'][entity_type] += 1
            else:
                results['missing'].append({
                    'uuid': uuid,
                    'eventType': event_type,
                    'entityType': entity_type,
                    'entityId': entity_id
                })
                
    except subprocess.TimeoutExpired:
        results['errors'].append("DSQL query timed out")
    except Exception as e:
        results['errors'].append(f"DSQL validation error: {str(e)}")
    
    return results

def print_results(database_name: str, results: Dict):
    """Print validation results."""
    print(f"\n{'='*60}")
    print(f"{database_name} Validation Results")
    print(f"{'='*60}")
    print(f"Total Events Sent: {results['total_sent']}")
    print(f"Events Found: {results['found']}")
    print(f"Events Missing: {len(results['missing'])}")
    
    if results['by_event_type']:
        print(f"\nBy Event Type:")
        for event_type, count in sorted(results['by_event_type'].items()):
            print(f"  {event_type}: {count}")
    
    if results['by_entity_type']:
        print(f"\nBy Entity Type:")
        for entity_type, count in sorted(results['by_entity_type'].items()):
            print(f"  {entity_type}: {count}")
    
    if results['missing']:
        print(f"\nMissing Events ({len(results['missing'])}):")
        for missing in results['missing'][:10]:  # Show first 10
            print(f"  UUID: {missing.get('uuid', 'N/A')}, Type: {missing.get('eventType', 'N/A')}")
        if len(results['missing']) > 10:
            print(f"  ... and {len(results['missing']) - 10} more")
    
    if results['errors']:
        print(f"\nErrors:")
        for error in results['errors']:
            print(f"  ❌ {error}")
    
    success_rate = (results['found'] / results['total_sent'] * 100) if results['total_sent'] > 0 else 0
    print(f"\nSuccess Rate: {success_rate:.2f}%")
    
    if success_rate == 100:
        print("✅ All events found in database!")
    elif success_rate >= 95:
        print("⚠️  Most events found (>=95%)")
    else:
        print("❌ Many events missing (<95%)")

def main():
    parser = argparse.ArgumentParser(description='Validate databases against sent events from k6 test')
    parser.add_argument('--events-file', default=DEFAULT_EVENTS_FILE,
                       help=f'Path to events JSON file (default: {DEFAULT_EVENTS_FILE})')
    parser.add_argument('--aurora', action='store_true',
                       help='Validate against Aurora PostgreSQL')
    parser.add_argument('--dsql', action='store_true',
                       help='Validate against DSQL')
    parser.add_argument('--aurora-endpoint', 
                       help='Aurora endpoint (or use AURORA_ENDPOINT env var)')
    parser.add_argument('--aurora-password',
                       help='Aurora password (or use AURORA_PASSWORD env var)')
    parser.add_argument('--query-dsql-script', default='scripts/query-dsql.sh',
                       help='Path to query-dsql.sh script (default: scripts/query-dsql.sh)')
    
    args = parser.parse_args()
    
    # Load sent events
    print(f"Loading sent events from: {args.events_file}")
    events = load_sent_events(args.events_file)
    print(f"Loaded {len(events)} events")
    
    # Validate Aurora if requested
    if args.aurora:
        aurora_endpoint = args.aurora_endpoint or os.getenv('AURORA_ENDPOINT')
        aurora_password = args.aurora_password or os.getenv('AURORA_PASSWORD')
        
        if not aurora_endpoint or not aurora_password:
            print("Error: Aurora endpoint and password required (use --aurora-endpoint/--aurora-password or env vars)")
            sys.exit(1)
        
        results = validate_aurora(events, aurora_endpoint, aurora_password)
        print_results("Aurora PostgreSQL", results)
    
    # Validate DSQL if requested
    if args.dsql:
        if not os.path.exists(args.query_dsql_script):
            print(f"Error: DSQL query script not found: {args.query_dsql_script}")
            sys.exit(1)
        
        results = validate_dsql(events, args.query_dsql_script)
        print_results("DSQL", results)
    
    # If neither specified, validate both
    if not args.aurora and not args.dsql:
        print("No database specified. Validating both Aurora and DSQL...")
        
        # Aurora
        aurora_endpoint = args.aurora_endpoint or os.getenv('AURORA_ENDPOINT')
        aurora_password = args.aurora_password or os.getenv('AURORA_PASSWORD')
        
        if aurora_endpoint and aurora_password:
            results = validate_aurora(events, aurora_endpoint, aurora_password)
            print_results("Aurora PostgreSQL", results)
        else:
            print("\n⚠️  Skipping Aurora validation (endpoint/password not provided)")
        
        # DSQL
        if os.path.exists(args.query_dsql_script):
            results = validate_dsql(events, args.query_dsql_script)
            print_results("DSQL", results)
        else:
            print("\n⚠️  Skipping DSQL validation (query script not found)")

if __name__ == "__main__":
    main()

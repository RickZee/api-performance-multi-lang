#!/usr/bin/env python3
"""Validate databases against sent events from k6 test."""

import json
import sys
import os
import subprocess
import argparse
import time
from datetime import datetime
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
        'errors': [],
        'eventual_consistency_log': []  # Track eventual consistency patterns
    }
    
    # Track event timestamps for analysis
    event_timestamps = {}
    for event in events:
        uuid = event.get('uuid')
        if uuid:
            # Try to parse timestamp from event
            timestamp_str = event.get('timestamp', '')
            if timestamp_str:
                try:
                    # Parse ISO format timestamp (e.g., "2025-12-15T02:11:32.243Z")
                    # Remove 'Z' and parse
                    timestamp_clean = timestamp_str.replace('Z', '+00:00')
                    event_timestamps[uuid] = datetime.fromisoformat(timestamp_clean)
                except:
                    try:
                        # Try without timezone
                        event_timestamps[uuid] = datetime.fromisoformat(timestamp_str.replace('Z', ''))
                    except:
                        pass
    
    validation_start_time = datetime.now()
    
    try:
        # Get all UUIDs from sent events
        sent_uuids = {event.get('uuid') for event in events if event.get('uuid')}
        
        if not sent_uuids:
            results['errors'].append("No UUIDs found in sent events")
            return results
        
        print(f"[DSQL Validation] Starting validation at {validation_start_time.strftime('%Y-%m-%d %H:%M:%S')}", file=sys.stderr)
        print(f"[DSQL Validation] Total events to validate: {len(sent_uuids)}", file=sys.stderr)
        
        # Query DSQL for event headers - use IN clause with proper escaping
        # DSQL has transaction row limits, so we may need to query in batches
        # Split into batches of 1000 UUIDs to avoid issues
        batch_size = 1000
        found_uuids = set()
        uuid_list = list(sent_uuids)
        
        pass1_start = time.time()
        
        for i in range(0, len(uuid_list), batch_size):
            batch = uuid_list[i:i + batch_size]
            batch_num = i // batch_size + 1
            total_batches = (len(uuid_list) + batch_size - 1) // batch_size
            uuid_list_str = "','".join(batch)
            query = f"""
            SELECT id, event_name, event_type 
            FROM event_headers 
            WHERE id IN ('{uuid_list_str}')
            """
        
            # Run query via bastion host with retry for eventual consistency
            max_retries = 2
            batch_found = set()
            for retry in range(max_retries):
                batch_query_start = time.time()
                result = subprocess.run(
                    [query_script, query],
                    capture_output=True,
                    text=True,
                    timeout=90  # Increased timeout for large batches
                )
                batch_query_duration = time.time() - batch_query_start
                
                if result.returncode != 0:
                    print(f"[DSQL Validation] Batch {batch_num}/{total_batches}, retry {retry + 1}/{max_retries}: Query failed (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
                    if retry < max_retries - 1:
                        # Retry on error (might be temporary)
                        time.sleep(2)
                        continue
                    results['errors'].append(f"DSQL query failed (batch {batch_num}): {result.stderr}")
                    break
                
                # Parse results
                output = result.stdout.strip()
                if output:
                    # Extract UUIDs from query results
                    for line in output.split('\n'):
                        if line.strip() and '|' in line:
                            # Parse line format: uuid | event_name | event_type
                            parts = [p.strip() for p in line.split('|')]
                            if len(parts) >= 1 and parts[0]:
                                batch_found.add(parts[0])
                    
                    # If we found results, add them and break retry loop
                    if batch_found:
                        found_uuids.update(batch_found)
                        print(f"[DSQL Validation] Batch {batch_num}/{total_batches}, retry {retry + 1}/{max_retries}: Found {len(batch_found)}/{len(batch)} events (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
                        break
                elif retry < max_retries - 1:
                    # No results but might be eventual consistency - retry
                    print(f"[DSQL Validation] Batch {batch_num}/{total_batches}, retry {retry + 1}/{max_retries}: No results, retrying... (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
                    time.sleep(2)
                    continue
                else:
                    print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: No results after {max_retries} retries (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
        
        pass1_duration = time.time() - pass1_start
        pass1_found = len(found_uuids)
        print(f"[DSQL Validation] Pass 1 complete: Found {pass1_found}/{len(sent_uuids)} events ({pass1_found/len(sent_uuids)*100:.1f}%) in {pass1_duration:.2f}s", file=sys.stderr)
        results['eventual_consistency_log'].append({
            'pass': 1,
            'found': pass1_found,
            'total': len(sent_uuids),
            'duration': pass1_duration,
            'timestamp': datetime.now().isoformat()
        })
        
        if not found_uuids and not results['errors']:
            results['errors'].append("DSQL query returned no results for any batch (may be eventual consistency issue)")
        
        # Validate each sent event and track timing
        missing_uuids = []
        missing_by_type = defaultdict(list)
        found_by_type = defaultdict(int)
        
        for event in events:
            uuid = event.get('uuid')
            event_type = event.get('eventType', '')
            entity_type = event.get('entityType', '')
            entity_id = event.get('entityId', '')
            
            if uuid in found_uuids:
                results['found'] += 1
                results['by_event_type'][event_type] += 1
                found_by_type[event_type] += 1
                if entity_type and entity_id:
                    results['by_entity_type'][entity_type] += 1
            else:
                missing_uuids.append(uuid)
                missing_by_type[event_type].append({
                    'uuid': uuid,
                    'timestamp': event.get('timestamp', ''),
                    'vuId': event.get('vuId', ''),
                    'iteration': event.get('iteration', '')
                })
                results['missing'].append({
                    'uuid': uuid,
                    'eventType': event_type,
                    'entityType': entity_type,
                    'entityId': entity_id
                })
        
        # Log missing events by type
        if missing_uuids:
            print(f"[DSQL Validation] Missing events breakdown by type:", file=sys.stderr)
            for event_type, missing_list in missing_by_type.items():
                print(f"  {event_type}: {len(missing_list)} missing, {found_by_type[event_type]} found", file=sys.stderr)
        
        # For DSQL, do additional passes for missing events after waits (eventual consistency)
        if missing_uuids and len(missing_uuids) > 0 and len(missing_uuids) < len(sent_uuids):
            # Calculate time since test start
            if event_timestamps:
                oldest_event_time = min(event_timestamps.values())
                # Handle timezone-aware vs naive datetime
                if oldest_event_time.tzinfo is not None:
                    from datetime import timezone
                    now = datetime.now(timezone.utc)
                    oldest_event_time = oldest_event_time.replace(tzinfo=None) if oldest_event_time.tzinfo else oldest_event_time
                    now = now.replace(tzinfo=None)
                else:
                    now = datetime.now()
                time_since_first_event = (now - oldest_event_time).total_seconds()
                print(f"[DSQL Validation] Time since first event sent: {time_since_first_event:.1f}s", file=sys.stderr)
            
            # Pass 2: Wait 10 seconds
            wait_time = 10
            print(f"[DSQL Validation] ⚠️  {len(missing_uuids)} events not found initially. Waiting {wait_time} seconds for DSQL eventual consistency...", file=sys.stderr)
            time.sleep(wait_time)
            
            pass2_start = time.time()
            pass2_found_count = 0
            
            # Re-query for missing UUIDs in batches
            for i in range(0, len(missing_uuids), batch_size):
                batch = missing_uuids[i:i + batch_size]
                batch_num = i // batch_size + 1
                total_batches = (len(missing_uuids) + batch_size - 1) // batch_size
                uuid_list_str = "','".join(batch)
                query = f"""
                SELECT id, event_name, event_type 
                FROM event_headers 
                WHERE id IN ('{uuid_list_str}')
                """
                
                batch_query_start = time.time()
                result = subprocess.run(
                    [query_script, query],
                    capture_output=True,
                    text=True,
                    timeout=90
                )
                batch_query_duration = time.time() - batch_query_start
                
                if result.returncode == 0:
                    output = result.stdout.strip()
                    if output:
                        batch_found = 0
                        for line in output.split('\n'):
                            if line.strip() and '|' in line:
                                parts = [p.strip() for p in line.split('|')]
                                if len(parts) >= 1 and parts[0] and parts[0] in missing_uuids:
                                    # Found a previously missing event
                                    found_uuids.add(parts[0])
                                    batch_found += 1
                                    pass2_found_count += 1
                                    
                                    # Calculate time since event was sent
                                    event_time_info = ""
                                    if parts[0] in event_timestamps:
                                        event_sent_time = event_timestamps[parts[0]]
                                        time_to_appear = (datetime.now() - event_sent_time.replace(tzinfo=None)).total_seconds()
                                        event_time_info = f" (appeared after {time_to_appear:.1f}s)"
                                    
                                    # Update results
                                    for event in events:
                                        if event.get('uuid') == parts[0]:
                                            # Remove from missing, add to found
                                            results['missing'] = [m for m in results['missing'] if m['uuid'] != parts[0]]
                                            results['found'] += 1
                                            results['by_event_type'][event.get('eventType', '')] += 1
                                            if event.get('entityType') and event.get('entityId'):
                                                results['by_entity_type'][event.get('entityType', '')] += 1
                                            break
                        
                        if batch_found > 0:
                            print(f"[DSQL Validation] Pass 2, Batch {batch_num}/{total_batches}: Found {batch_found}/{len(batch)} previously missing events{event_time_info} (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
                else:
                    print(f"[DSQL Validation] Pass 2, Batch {batch_num}/{total_batches}: Query failed (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
            
            pass2_duration = time.time() - pass2_start
            pass2_total_found = len(found_uuids)
            print(f"[DSQL Validation] Pass 2 complete: Found {pass2_found_count} additional events. Total: {pass2_total_found}/{len(sent_uuids)} ({pass2_total_found/len(sent_uuids)*100:.1f}%) in {pass2_duration:.2f}s", file=sys.stderr)
            results['eventual_consistency_log'].append({
                'pass': 2,
                'found': pass2_found_count,
                'total_found': pass2_total_found,
                'total': len(sent_uuids),
                'duration': pass2_duration,
                'wait_time': wait_time,
                'timestamp': datetime.now().isoformat()
            })
            
            # Update missing_uuids for potential pass 3
            missing_uuids = [uuid for uuid in missing_uuids if uuid not in found_uuids]
            
            # Pass 3: If still missing events, wait another 10 seconds
            if missing_uuids and len(missing_uuids) > 0:
                wait_time = 10
                print(f"[DSQL Validation] ⚠️  {len(missing_uuids)} events still missing. Waiting {wait_time} more seconds...", file=sys.stderr)
                time.sleep(wait_time)
                
                pass3_start = time.time()
                pass3_found_count = 0
                
                for i in range(0, len(missing_uuids), batch_size):
                    batch = missing_uuids[i:i + batch_size]
                    batch_num = i // batch_size + 1
                    total_batches = (len(missing_uuids) + batch_size - 1) // batch_size
                    uuid_list_str = "','".join(batch)
                    query = f"""
                    SELECT id, event_name, event_type 
                    FROM event_headers 
                    WHERE id IN ('{uuid_list_str}')
                    """
                    
                    batch_query_start = time.time()
                    result = subprocess.run(
                        [query_script, query],
                        capture_output=True,
                        text=True,
                        timeout=90
                    )
                    batch_query_duration = time.time() - batch_query_start
                    
                    if result.returncode == 0:
                        output = result.stdout.strip()
                        if output:
                            batch_found = 0
                            for line in output.split('\n'):
                                if line.strip() and '|' in line:
                                    parts = [p.strip() for p in line.split('|')]
                                    if len(parts) >= 1 and parts[0] and parts[0] in missing_uuids:
                                        found_uuids.add(parts[0])
                                        batch_found += 1
                                        pass3_found_count += 1
                                        
                                        event_time_info = ""
                                        if parts[0] in event_timestamps:
                                            event_sent_time = event_timestamps[parts[0]]
                                            # Handle timezone-aware vs naive datetime
                                            if event_sent_time.tzinfo is not None:
                                                from datetime import timezone
                                                now = datetime.now(timezone.utc)
                                                event_sent_time = event_sent_time.replace(tzinfo=None) if event_sent_time.tzinfo else event_sent_time
                                                now = now.replace(tzinfo=None)
                                            else:
                                                now = datetime.now()
                                            time_to_appear = (now - event_sent_time).total_seconds()
                                            event_time_info = f" (appeared after {time_to_appear:.1f}s)"
                                        
                                        for event in events:
                                            if event.get('uuid') == parts[0]:
                                                results['missing'] = [m for m in results['missing'] if m['uuid'] != parts[0]]
                                                results['found'] += 1
                                                results['by_event_type'][event.get('eventType', '')] += 1
                                                if event.get('entityType') and event.get('entityId'):
                                                    results['by_entity_type'][event.get('entityType', '')] += 1
                                                break
                            
                            if batch_found > 0:
                                print(f"[DSQL Validation] Pass 3, Batch {batch_num}/{total_batches}: Found {batch_found}/{len(batch)} previously missing events{event_time_info} (duration: {batch_query_duration:.2f}s)", file=sys.stderr)
                
                pass3_duration = time.time() - pass3_start
                pass3_total_found = len(found_uuids)
                print(f"[DSQL Validation] Pass 3 complete: Found {pass3_found_count} additional events. Total: {pass3_total_found}/{len(sent_uuids)} ({pass3_total_found/len(sent_uuids)*100:.1f}%) in {pass3_duration:.2f}s", file=sys.stderr)
                results['eventual_consistency_log'].append({
                    'pass': 3,
                    'found': pass3_found_count,
                    'total_found': pass3_total_found,
                    'total': len(sent_uuids),
                    'duration': pass3_duration,
                    'wait_time': wait_time,
                    'timestamp': datetime.now().isoformat()
                })
        
        total_validation_duration = (datetime.now() - validation_start_time).total_seconds()
        print(f"[DSQL Validation] Total validation time: {total_validation_duration:.2f}s", file=sys.stderr)
                
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
    
    # Print eventual consistency statistics for DSQL
    if 'eventual_consistency_log' in results and results['eventual_consistency_log']:
        print(f"\nEventual Consistency Analysis:")
        for log_entry in results['eventual_consistency_log']:
            pass_num = log_entry.get('pass', 0)
            found = log_entry.get('found', 0)
            total = log_entry.get('total', 0)
            duration = log_entry.get('duration', 0)
            wait_time = log_entry.get('wait_time', 0)
            
            if pass_num == 1:
                print(f"  Pass {pass_num}: Found {found}/{total} events ({found/total*100:.1f}%) in {duration:.2f}s")
            else:
                total_found = log_entry.get('total_found', found)
                print(f"  Pass {pass_num}: Found {found} additional events after {wait_time}s wait. Total: {total_found}/{total} ({total_found/total*100:.1f}%) in {duration:.2f}s")
    
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

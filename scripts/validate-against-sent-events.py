#!/usr/bin/env python3
"""Validate databases against sent events from k6 test."""

import json
import sys
import os
import subprocess
import argparse
import time
import asyncio
import asyncpg
import socket
from datetime import datetime
from typing import Dict, List, Set, Optional
from collections import defaultdict

# Import DSQL connection helper
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from dsql_connection import get_dsql_connection

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

def get_terraform_output(output_name: str, terraform_dir: str = None) -> Optional[str]:
    """Get terraform output value."""
    if terraform_dir is None:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        terraform_dir = os.path.join(os.path.dirname(script_dir), 'terraform')
    
    try:
        result = subprocess.run(
            ['terraform', 'output', '-raw', output_name],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    
    # Special case: iam_database_user is a variable, not an output
    # Try to read from terraform.tfvars
    if output_name == 'iam_database_user':
        try:
            tfvars_path = os.path.join(terraform_dir, 'terraform.tfvars')
            if os.path.exists(tfvars_path):
                with open(tfvars_path, 'r') as f:
                    for line in f:
                        if line.strip().startswith('iam_database_user'):
                            # Extract value from: iam_database_user = "value" # comment
                            # Remove comments first
                            line_no_comment = line.split('#')[0]
                            parts = line_no_comment.split('=')
                            if len(parts) == 2:
                                value = parts[1].strip().strip('"').strip("'")
                                # Remove any remaining whitespace or comments
                                value = value.split('#')[0].strip().strip('"').strip("'")
                                if value:
                                    return value
        except Exception:
            pass
    
    return None


async def query_batch_parallel(
    conn: asyncpg.Connection,
    batch: List[str],
    semaphore: asyncio.Semaphore,
    batch_num: int,
    total_batches: int
) -> Set[str]:
    """Query a batch of UUIDs in parallel with semaphore control."""
    async with semaphore:
        batch_start = time.time()
        try:
            # Filter out empty UUIDs
            uuid_list = [uuid for uuid in batch if uuid]
            if not uuid_list:
                return set()
            
            # Use ANY with array parameter - asyncpg will handle UUID conversion
            # Format: WHERE id = ANY($1::uuid[])
            # This is more efficient than building a large IN clause
            rows = await conn.fetch(
                "SELECT id FROM event_headers WHERE id = ANY($1::uuid[])",
                uuid_list
            )
            found = {str(row['id']) for row in rows}  # Convert UUID objects to strings
            duration = time.time() - batch_start
            print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Found {len(found)}/{len(batch)} events (duration: {duration:.2f}s)", file=sys.stderr)
            return found
        except Exception as e:
            duration = time.time() - batch_start
            error_msg = str(e)[:200]
            print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Error - {error_msg} (duration: {duration:.2f}s)", file=sys.stderr)
            # If ANY with array fails, fall back to IN clause (less efficient but more compatible)
            try:
                # Build IN clause as fallback
                placeholders = ','.join([f'${i+1}' for i in range(len(uuid_list))])
                query = f"SELECT id FROM event_headers WHERE id IN ({placeholders})"
                rows = await conn.fetch(query, *uuid_list)
                found = {str(row['id']) for row in rows}
                print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Fallback query found {len(found)}/{len(batch)} events", file=sys.stderr)
                return found
            except Exception as e2:
                print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Fallback query also failed - {str(e2)[:200]}", file=sys.stderr)
                return set()


async def validate_dsql_async(
    events: List[Dict],
    dsql_host: str,
    dsql_port: int,
    iam_username: str,
    aws_region: str,
    database_name: str = "postgres",
    batch_size: int = 500,
    max_concurrent: int = 10
) -> Dict:
    """Validate events in DSQL database using direct async connection."""
    results = {
        'total_sent': len(events),
        'found': 0,
        'missing': [],
        'by_event_type': defaultdict(int),
        'by_entity_type': defaultdict(int),
        'errors': []
    }
    
    # Track event timestamps for analysis
    event_timestamps = {}
    for event in events:
        uuid = event.get('uuid')
        if uuid:
            timestamp_str = event.get('timestamp', '')
            if timestamp_str:
                try:
                    timestamp_clean = timestamp_str.replace('Z', '+00:00')
                    event_timestamps[uuid] = datetime.fromisoformat(timestamp_clean)
                except:
                    try:
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
        print(f"[DSQL Validation] Using batch size: {batch_size}, max concurrent: {max_concurrent}", file=sys.stderr)
        
        # Create connection
        conn = await get_dsql_connection(
            dsql_host=dsql_host,
            port=dsql_port,
            iam_username=iam_username,
            region=aws_region,
            database_name=database_name
        )
        
        try:
            # Split into batches
            uuid_list = list(sent_uuids)
            batches = [uuid_list[i:i + batch_size] for i in range(0, len(uuid_list), batch_size)]
            total_batches = len(batches)
            
            print(f"[DSQL Validation] Processing {total_batches} batches in parallel...", file=sys.stderr)
            
            # Create semaphore for concurrency control
            semaphore = asyncio.Semaphore(max_concurrent)
            
            # Execute all batches in parallel
            pass1_start = time.time()
            batch_tasks = [
                query_batch_parallel(conn, batch, semaphore, i + 1, total_batches)
                for i, batch in enumerate(batches)
            ]
            
            batch_results = await asyncio.gather(*batch_tasks, return_exceptions=True)
            
            # Collect all found UUIDs
            found_uuids = set()
            for i, result in enumerate(batch_results):
                if isinstance(result, Exception):
                    results['errors'].append(f"Batch {i + 1} error: {str(result)[:200]}")
                elif isinstance(result, set):
                    found_uuids.update(result)
            
            pass1_duration = time.time() - pass1_start
            pass1_found = len(found_uuids)
            print(f"[DSQL Validation] Pass 1 complete: Found {pass1_found}/{len(sent_uuids)} events ({pass1_found/len(sent_uuids)*100:.1f}%) in {pass1_duration:.2f}s", file=sys.stderr)
            
            if not found_uuids and not results['errors']:
                results['errors'].append("DSQL query returned no results for any batch")
            
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
            
            # For DSQL, do additional passes for missing events after waits
            if missing_uuids and len(missing_uuids) > 0 and len(missing_uuids) < len(sent_uuids):
                # Calculate time since test start
                if event_timestamps:
                    oldest_event_time = min(event_timestamps.values())
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
                print(f"[DSQL Validation] ⚠️  {len(missing_uuids)} events not found initially. Waiting {wait_time} seconds...", file=sys.stderr)
                await asyncio.sleep(wait_time)
                
                pass2_start = time.time()
                
                # Re-query for missing UUIDs in parallel batches
                missing_batches = [missing_uuids[i:i + batch_size] for i in range(0, len(missing_uuids), batch_size)]
                missing_batch_tasks = [
                    query_batch_parallel(conn, batch, semaphore, i + 1, len(missing_batches))
                    for i, batch in enumerate(missing_batches)
                ]
                
                missing_results = await asyncio.gather(*missing_batch_tasks, return_exceptions=True)
                
                pass2_found_count = 0
                for i, result in enumerate(missing_results):
                    if isinstance(result, set):
                        for uuid in result:
                            if uuid in missing_uuids:
                                found_uuids.add(uuid)
                                pass2_found_count += 1
                                # Update results
                                for event in events:
                                    if event.get('uuid') == uuid:
                                        results['missing'] = [m for m in results['missing'] if m['uuid'] != uuid]
                                        results['found'] += 1
                                        results['by_event_type'][event.get('eventType', '')] += 1
                                        if event.get('entityType') and event.get('entityId'):
                                            results['by_entity_type'][event.get('entityType', '')] += 1
                                        break
                
                pass2_duration = time.time() - pass2_start
                pass2_total_found = len(found_uuids)
                print(f"[DSQL Validation] Pass 2 complete: Found {pass2_found_count} additional events. Total: {pass2_total_found}/{len(sent_uuids)} ({pass2_total_found/len(sent_uuids)*100:.1f}%) in {pass2_duration:.2f}s", file=sys.stderr)
                
                # Update missing_uuids for potential pass 3
                missing_uuids = [uuid for uuid in missing_uuids if uuid not in found_uuids]
                
                # Pass 3: If still missing events, wait another 10 seconds
                if missing_uuids and len(missing_uuids) > 0:
                    wait_time = 10
                    print(f"[DSQL Validation] ⚠️  {len(missing_uuids)} events still missing. Waiting {wait_time} more seconds...", file=sys.stderr)
                    await asyncio.sleep(wait_time)
                    
                    pass3_start = time.time()
                    
                    missing_batches = [missing_uuids[i:i + batch_size] for i in range(0, len(missing_uuids), batch_size)]
                    missing_batch_tasks = [
                        query_batch_parallel(conn, batch, semaphore, i + 1, len(missing_batches))
                        for i, batch in enumerate(missing_batches)
                    ]
                    
                    missing_results = await asyncio.gather(*missing_batch_tasks, return_exceptions=True)
                    
                    pass3_found_count = 0
                    for i, result in enumerate(missing_results):
                        if isinstance(result, set):
                            for uuid in result:
                                if uuid in missing_uuids:
                                    found_uuids.add(uuid)
                                    pass3_found_count += 1
                                    # Update results
                                    for event in events:
                                        if event.get('uuid') == uuid:
                                            results['missing'] = [m for m in results['missing'] if m['uuid'] != uuid]
                                            results['found'] += 1
                                            results['by_event_type'][event.get('eventType', '')] += 1
                                            if event.get('entityType') and event.get('entityId'):
                                                results['by_entity_type'][event.get('entityType', '')] += 1
                                            break
                    
                    pass3_duration = time.time() - pass3_start
                    pass3_total_found = len(found_uuids)
                    print(f"[DSQL Validation] Pass 3 complete: Found {pass3_found_count} additional events. Total: {pass3_total_found}/{len(sent_uuids)} ({pass3_total_found/len(sent_uuids)*100:.1f}%) in {pass3_duration:.2f}s", file=sys.stderr)
            
        finally:
            await conn.close()
        
        total_validation_duration = (datetime.now() - validation_start_time).total_seconds()
        print(f"[DSQL Validation] Total validation time: {total_validation_duration:.2f}s", file=sys.stderr)
                
    except Exception as e:
        results['errors'].append(f"DSQL validation error: {str(e)}")
        import traceback
        print(f"[DSQL Validation] Error details: {traceback.format_exc()}", file=sys.stderr)
    
    return results


def validate_dsql(
    events: List[Dict],
    dsql_host: Optional[str] = None,
    dsql_port: int = 5432,
    iam_username: Optional[str] = None,
    aws_region: Optional[str] = None,
    database_name: str = "postgres",
    batch_size: int = 500,
    max_concurrent: int = 10,
    use_bastion: bool = False,
    bastion_instance_id: Optional[str] = None
) -> Dict:
    """
    Validate events in DSQL database using direct connection (wrapper for async function).
    
    If direct connection fails and use_bastion is True, falls back to bastion host validation.
    """
    try:
        results = asyncio.run(validate_dsql_async(
            events, dsql_host, dsql_port, iam_username, aws_region, database_name, batch_size, max_concurrent
        ))
        
        # Check if results indicate a connection error that would benefit from bastion
        if use_bastion and results.get('errors'):
            error_messages = ' '.join(results['errors']).lower()
            if any(keyword in error_messages for keyword in ['nodename', 'servname', 'connection', 'dns', 'gaierror', 'unable to connect']):
                print(f"[DSQL Validation] Direct connection failed with errors: {', '.join(results['errors'][:2])}", file=sys.stderr)
                print(f"[DSQL Validation] Falling back to bastion host validation...", file=sys.stderr)
                return validate_dsql_via_bastion(
                    events, dsql_host, dsql_port, iam_username, aws_region, bastion_instance_id
                )
        
        return results
    except (ConnectionError, OSError, socket.gaierror) as e:
        error_str = str(e).lower()
        # Check if it's a connection/DNS error that would benefit from bastion host
        if use_bastion and ('nodename' in error_str or 'servname' in error_str or 'connection' in error_str or 'dns' in error_str or 'gaierror' in error_str):
            print(f"[DSQL Validation] Direct connection failed: {str(e)[:200]}", file=sys.stderr)
            print(f"[DSQL Validation] Falling back to bastion host validation...", file=sys.stderr)
            return validate_dsql_via_bastion(
                events, dsql_host, dsql_port, iam_username, aws_region, bastion_instance_id
            )
        else:
            # Re-raise if not a connection error or bastion not requested
            raise
    except Exception as e:
        # For any other exception, check if it's connection-related
        error_str = str(e).lower()
        if use_bastion and ('nodename' in error_str or 'servname' in error_str or 'connection' in error_str or 'dns' in error_str or 'gaierror' in error_str):
            print(f"[DSQL Validation] Direct connection failed: {str(e)[:200]}", file=sys.stderr)
            print(f"[DSQL Validation] Falling back to bastion host validation...", file=sys.stderr)
            return validate_dsql_via_bastion(
                events, dsql_host, dsql_port, iam_username, aws_region, bastion_instance_id
            )
        raise


def validate_dsql_via_bastion(
    events: List[Dict],
    dsql_host: Optional[str],
    dsql_port: int,
    iam_username: Optional[str],
    aws_region: Optional[str],
    bastion_instance_id: Optional[str] = None
) -> Dict:
    """Validate events in DSQL database via bastion host using SSM."""
    import tempfile
    
    # Save events to temporary file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
        json.dump(events, f)
        events_file = f.name
    
    try:
        # Get bastion instance ID if not provided
        if not bastion_instance_id:
            script_dir = os.path.dirname(os.path.abspath(__file__))
            terraform_dir = os.path.join(os.path.dirname(script_dir), 'terraform')
            result = subprocess.run(
                ['terraform', 'output', '-raw', 'bastion_host_instance_id'],
                cwd=terraform_dir,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                bastion_instance_id = result.stdout.strip()
        
        if not bastion_instance_id:
            return {
                'total_sent': len(events),
                'found': 0,
                'missing': events,
                'by_event_type': defaultdict(int),
                'by_entity_type': defaultdict(int),
                'errors': ['Bastion host instance ID not found']
            }
        
        # Run validation via bastion host script
        bastion_script = os.path.join(os.path.dirname(__file__), 'validate-dsql-via-bastion.sh')
        if not os.path.exists(bastion_script):
            return {
                'total_sent': len(events),
                'found': 0,
                'missing': events,
                'by_event_type': defaultdict(int),
                'by_entity_type': defaultdict(int),
                'errors': ['Bastion validation script not found']
            }
        
        result = subprocess.run(
            [bastion_script, events_file, bastion_instance_id, aws_region or 'us-east-1'],
            capture_output=True,
            text=True,
            timeout=600  # 10 minute timeout
        )
        
        if result.returncode != 0:
            error_msg = result.stderr[:1000] if result.stderr else "Unknown error"
            stdout_msg = result.stdout[:500] if result.stdout else ""
            return {
                'total_sent': len(events),
                'found': 0,
                'missing': events,
                'by_event_type': defaultdict(int),
                'by_entity_type': defaultdict(int),
                'errors': [f'Bastion validation failed: {error_msg}. stdout: {stdout_msg}']
            }
        
        # Parse JSON output from bastion script
        # The script outputs JSON to stdout
        output_lines = result.stdout.strip().split('\n')
        json_start = None
        json_end = None
        
        for i, line in enumerate(output_lines):
            if line.strip().startswith('{'):
                json_start = i
                break
        
        if json_start is not None:
            json_lines = output_lines[json_start:]
            json_str = '\n'.join(json_lines)
            try:
                return json.loads(json_str)
            except json.JSONDecodeError:
                pass
        
        # If JSON parsing failed, return error
        return {
            'total_sent': len(events),
            'found': 0,
            'missing': events,
            'by_event_type': defaultdict(int),
            'by_entity_type': defaultdict(int),
            'errors': ['Failed to parse validation results from bastion host']
        }
        
    finally:
        # Clean up temporary file
        try:
            os.unlink(events_file)
        except Exception:
            pass

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
    parser.add_argument('--dsql-host',
                       help='DSQL host (or use DSQL_HOST env var or terraform output)')
    parser.add_argument('--dsql-port', type=int, default=5432,
                       help='DSQL port (default: 5432)')
    parser.add_argument('--iam-username',
                       help='IAM database username (or use IAM_USERNAME env var or terraform output)')
    parser.add_argument('--aws-region',
                       help='AWS region (or use AWS_REGION env var or terraform output)')
    parser.add_argument('--dsql-database', default='postgres',
                       help='DSQL database name (default: postgres)')
    parser.add_argument('--dsql-batch-size', type=int, default=500,
                       help='Batch size for DSQL queries (default: 500)')
    parser.add_argument('--dsql-max-concurrent', type=int, default=10,
                       help='Max concurrent DSQL queries (default: 10)')
    parser.add_argument('--query-dsql-script', default='scripts/query-dsql.sh',
                       help='[DEPRECATED] Path to query-dsql.sh script (legacy SSM method, not used with direct connection)')
    
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
        # Auto-detect DSQL connection parameters from terraform if not provided
        dsql_host = args.dsql_host or os.getenv('DSQL_HOST')
        iam_username = args.iam_username or os.getenv('IAM_USERNAME')
        aws_region = args.aws_region or os.getenv('AWS_REGION') or os.getenv('AWS_DEFAULT_REGION')
        
        # Try to get from terraform outputs if not provided
        if not dsql_host:
            dsql_host = get_terraform_output('aurora_dsql_host')
        if not iam_username:
            iam_username = get_terraform_output('iam_database_user')
        if not aws_region:
            # Try terraform output first, then AWS CLI, then default
            aws_region = get_terraform_output('aws_region')
            if not aws_region:
                try:
                    result = subprocess.run(
                        ['aws', 'configure', 'get', 'region'],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
                    if result.returncode == 0:
                        aws_region = result.stdout.strip()
                except Exception:
                    pass
            if not aws_region:
                aws_region = 'us-east-1'  # Default region
        
        if not dsql_host:
            print("Error: DSQL host required (use --dsql-host, DSQL_HOST env var, or terraform output aurora_dsql_host)")
            sys.exit(1)
        if not iam_username:
            print("Error: IAM username required (use --iam-username, IAM_USERNAME env var, or terraform output iam_database_user)")
            sys.exit(1)
        if not aws_region:
            print("Error: AWS region required (use --aws-region, AWS_REGION env var, or terraform output aws_region)")
            sys.exit(1)
        
        print(f"[DSQL] Using host: {dsql_host}, port: {args.dsql_port}, user: {iam_username}, region: {aws_region}")
        
        results = validate_dsql(
            events,
            dsql_host=dsql_host,
            dsql_port=args.dsql_port,
            iam_username=iam_username,
            aws_region=aws_region,
            database_name=args.dsql_database,
            batch_size=args.dsql_batch_size,
            max_concurrent=args.dsql_max_concurrent,
            use_bastion=True,  # Automatically fall back to bastion if direct connection fails
            bastion_instance_id=None  # Will be auto-detected
        )
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
        dsql_host = args.dsql_host or os.getenv('DSQL_HOST')
        iam_username = args.iam_username or os.getenv('IAM_USERNAME')
        aws_region = args.aws_region or os.getenv('AWS_REGION') or os.getenv('AWS_DEFAULT_REGION')
        
        # Try to get from terraform outputs if not provided
        if not dsql_host:
            dsql_host = get_terraform_output('aurora_dsql_host')
        if not iam_username:
            iam_username = get_terraform_output('iam_database_user')
        if not aws_region:
            aws_region = get_terraform_output('aws_region')
        
        if dsql_host and iam_username and aws_region:
            print(f"[DSQL] Using host: {dsql_host}, port: {args.dsql_port}, user: {iam_username}, region: {aws_region}")
            results = validate_dsql(
                events,
                dsql_host=dsql_host,
                dsql_port=args.dsql_port,
                iam_username=iam_username,
                aws_region=aws_region,
                database_name=args.dsql_database,
                batch_size=args.dsql_batch_size,
                max_concurrent=args.dsql_max_concurrent,
                use_bastion=True,  # Automatically fall back to bastion if direct connection fails
                bastion_instance_id=None  # Will be auto-detected
            )
            print_results("DSQL", results)
        else:
            print("\n⚠️  Skipping DSQL validation (connection parameters not provided)")

if __name__ == "__main__":
    main()

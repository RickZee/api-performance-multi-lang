"""DSQL validation script for bastion host execution."""

import json
import sys
import asyncio
import asyncpg
import boto3
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from urllib.parse import urlencode, urlparse
from datetime import datetime, timedelta
from typing import Dict, List, Set
from collections import defaultdict

# IAM token cache
_token_cache = None


def generate_iam_auth_token(endpoint: str, port: int, iam_username: str, region: str) -> str:
    """Generate IAM authentication token for Aurora DSQL."""
    global _token_cache
    
    if _token_cache is not None:
        cached_token = _token_cache.get('token')
        expires_at = _token_cache.get('expires_at')
        cache_key = _token_cache.get('key')
        expected_key = f"{endpoint}:{port}:{iam_username}"
        if cache_key == expected_key and expires_at:
            time_until_expiry = expires_at - datetime.utcnow()
            if time_until_expiry > timedelta(minutes=1):
                return cached_token
    
    session = boto3.Session(region_name=region)
    credentials = session.get_credentials()
    if not credentials:
        raise Exception("No AWS credentials available")
    
    query_params = {'Action': 'DbConnect'}
    dsql_url = f"https://{endpoint}/?{urlencode(query_params)}"
    request = AWSRequest(method='GET', url=dsql_url)
    expires_in = 900
    signer = SigV4QueryAuth(credentials, 'dsql', region, expires=expires_in)
    signer.add_auth(request)
    
    parsed = urlparse(request.url)
    signed_query = parsed.query
    if not signed_query:
        raise Exception("Failed to generate DSQL token")
    
    token = f"{endpoint}:{port}/?{signed_query}"
    expires_at = datetime.utcnow() + timedelta(minutes=14)
    _token_cache = {
        'token': token,
        'expires_at': expires_at,
        'key': f"{endpoint}:{port}:{iam_username}"
    }
    return token


async def get_connection(dsql_host: str, port: int, iam_username: str, region: str, database_name: str = "postgres"):
    """Get DSQL connection."""
    try:
        iam_token = generate_iam_auth_token(dsql_host, port, iam_username, region)
        print(f"[DSQL Validation] Connecting to {dsql_host}:{port} as {iam_username}...", file=sys.stderr)
        conn = await asyncpg.connect(
            host=dsql_host,
            port=port,
            user=iam_username,
            password=iam_token,
            database=database_name,
            ssl='require',
            command_timeout=30,
            server_settings={'search_path': 'car_entities_schema'}
        )
        print(f"[DSQL Validation] Connection established successfully", file=sys.stderr)
        return conn
    except Exception as e:
        print(f"[DSQL Validation] Connection failed: {type(e).__name__}: {str(e)}", file=sys.stderr)
        raise


async def query_batch(conn: asyncpg.Connection, batch: List[str], batch_num: int, total_batches: int) -> Set[str]:
    """Query a batch of UUIDs."""
    import time
    batch_start = time.time()
    try:
        uuid_list = [uuid for uuid in batch if uuid]
        if not uuid_list:
            return set()
        
        # The id column is VARCHAR(255) in DSQL, so we compare as text
        # Use IN clause with text parameters
        placeholders = ','.join([f'${i+1}' for i in range(len(uuid_list))])
        query = f"SELECT id FROM event_headers WHERE id IN ({placeholders})"
        rows = await conn.fetch(query, *uuid_list)
        found = {str(row['id']) for row in rows}
        duration = time.time() - batch_start
        print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Found {len(found)}/{len(batch)} events (duration: {duration:.2f}s)", file=sys.stderr)
        return found
    except Exception as e:
        print(f"[DSQL Validation] Batch {batch_num}/{total_batches}: Error - {str(e)[:200]}", file=sys.stderr)
        return set()


async def validate_dsql_async(
    events: List[Dict],
    dsql_host: str,
    dsql_port: int,
    iam_username: str,
    aws_region: str,
    batch_size: int = 500,
    max_concurrent: int = 10
) -> Dict:
    """Validate events in DSQL database."""
    results = {
        'total_sent': len(events),
        'found': 0,
        'missing': [],
        'by_event_type': defaultdict(int),
        'by_entity_type': defaultdict(int),
        'errors': []
    }
    
    sent_uuids = {event.get('uuid') for event in events if event.get('uuid')}
    if not sent_uuids:
        results['errors'].append("No UUIDs found in sent events")
        return results
    
    print(f"[DSQL Validation] Starting validation", file=sys.stderr)
    print(f"[DSQL Validation] Total events to validate: {len(sent_uuids)}", file=sys.stderr)
    
    conn = await get_connection(dsql_host, dsql_port, iam_username, aws_region)
    
    try:
        uuid_list = list(sent_uuids)
        batches = [uuid_list[i:i + batch_size] for i in range(0, len(uuid_list), batch_size)]
        total_batches = len(batches)
        
        # DSQL doesn't support concurrent operations on the same connection
        # Run batches sequentially instead of in parallel
        found_uuids = set()
        for i, batch in enumerate(batches):
            result = await query_batch(conn, batch, i + 1, total_batches)
            if isinstance(result, set):
                found_uuids.update(result)
            elif isinstance(result, Exception):
                results['errors'].append(f"Batch {i + 1} error: {str(result)[:200]}")
        
        # found_uuids already populated above
        
        for event in events:
            uuid = event.get('uuid')
            if uuid in found_uuids:
                results['found'] += 1
                results['by_event_type'][event.get('eventType', '')] += 1
                if event.get('entityType') and event.get('entityId'):
                    results['by_entity_type'][event.get('entityType', '')] += 1
            else:
                results['missing'].append({
                    'uuid': uuid,
                    'eventType': event.get('eventType', ''),
                    'entityType': event.get('entityType', ''),
                    'entityId': event.get('entityId', '')
                })
    finally:
        await conn.close()
    
    return results


def validate_dsql_bastion(
    events: List[Dict],
    dsql_host: str,
    dsql_port: int,
    iam_username: str,
    aws_region: str,
    batch_size: int = 500,
    max_concurrent: int = 10
) -> Dict:
    """Wrapper for async validation."""
    return asyncio.run(validate_dsql_async(events, dsql_host, dsql_port, iam_username, aws_region, batch_size, max_concurrent))


if __name__ == "__main__":
    # For direct execution
    if len(sys.argv) < 5:
        print("Usage: validate_dsql_bastion.py <events_file> <dsql_host> <dsql_port> <iam_username> <aws_region>")
        sys.exit(1)
    
    events_file = sys.argv[1]
    dsql_host = sys.argv[2]
    dsql_port = int(sys.argv[3])
    iam_username = sys.argv[4]
    aws_region = sys.argv[5]
    
    with open(events_file, 'r') as f:
        events = json.load(f)
    
    results = validate_dsql_bastion(events, dsql_host, dsql_port, iam_username, aws_region)
    print(json.dumps(results, indent=2))

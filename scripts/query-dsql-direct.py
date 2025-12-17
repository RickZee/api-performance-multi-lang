#!/usr/bin/env python3
"""Query DSQL database directly using asyncpg (same method as Lambda)."""

import asyncio
import asyncpg
import boto3
import os
import sys
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest
from urllib.parse import urlencode, urlparse

DSQL_HOST = os.getenv("DSQL_HOST", "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
IAM_USERNAME = os.getenv("IAM_USERNAME", "admin")
PORT = 5432

def generate_iam_token(endpoint, port, iam_username, region):
    """Generate IAM auth token for DSQL."""
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
    
    signed_url = request.url
    parsed = urlparse(signed_url)
    signed_query = parsed.query
    
    if not signed_query:
        raise Exception(f"Failed to generate DSQL token")
    
    token = f"{endpoint}:{port}/?{signed_query}"
    return token

async def query_database():
    """Query DSQL database."""
    print("=== Querying DSQL Database ===\n")
    
    # Generate IAM token
    print("Generating IAM auth token...")
    iam_token = generate_iam_token(DSQL_HOST, PORT, IAM_USERNAME, AWS_REGION)
    print("Token generated successfully\n")
    
    # Connect to database
    print(f"Connecting to {DSQL_HOST}...")
    conn = await asyncpg.connect(
        host=DSQL_HOST,
        port=PORT,
        user=IAM_USERNAME,
        password=iam_token,
        database="postgres",
        ssl='require',
        command_timeout=30
    )
    print("Connected successfully\n")
    
    try:
        # Count all tables
        print("Table Counts:")
        print("-" * 50)
        
        tables = [
            "business_events",
            "event_headers",
            "car_entities",
            "loan_entities",
            "loan_payment_entities",
            "service_record_entities",
        ]
        
        for table in tables:
            count = await conn.fetchval(f"SELECT COUNT(*) FROM {table}")
            print(f"  {table:30s}: {count}")
        
        print("\n" + "-" * 50)
        
        # Count by event name
        print("\nEvents by Event Name:")
        print("-" * 50)
        rows = await conn.fetch("""
            SELECT event_name, COUNT(*) as count 
            FROM business_events 
            GROUP BY event_name 
            ORDER BY event_name
        """)
        for row in rows:
            print(f"  {row['event_name']:30s}: {row['count']}")
        
        print("\n" + "-" * 50)
        
        # Count by entity type
        print("\nEntities by Type:")
        print("-" * 50)
        entity_counts = await conn.fetch("""
            SELECT 'Car' as entity_type, COUNT(*) as count FROM car_entities
            UNION ALL
            SELECT 'Loan', COUNT(*) FROM loan_entities
            UNION ALL
            SELECT 'LoanPayment', COUNT(*) FROM loan_payment_entities
            UNION ALL
            SELECT 'ServiceRecord', COUNT(*) FROM service_record_entities
            ORDER BY entity_type
        """)
        for row in entity_counts:
            print(f"  {row['entity_type']:30s}: {row['count']}")
        
        print("\n" + "-" * 50)
        print("\nValidation complete!")
        
    finally:
        await conn.close()
        print("\nConnection closed.")

if __name__ == "__main__":
    asyncio.run(query_database())

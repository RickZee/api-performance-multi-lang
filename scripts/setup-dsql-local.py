#!/usr/bin/env python3
"""
Setup DSQL database schema using local AWS credentials
Run this from your local machine (requires psycopg2-binary)
"""
import os
import sys
import boto3
import subprocess

DSQL_HOST = "vftmkydwxvxys6asbsc6ih2the.dsql-fnh4.us-east-1.on.aws"
AWS_REGION = "us-east-1"

def generate_token():
    """Generate DSQL admin auth token"""
    rds_client = boto3.client('rds', region_name=AWS_REGION)
    token = rds_client.generate_db_auth_token(
        DBHostname=DSQL_HOST,
        Port=5432,
        DBUsername='admin',
        Region=AWS_REGION
    )
    return token

def run_psql_command(sql, database='postgres'):
    """Run SQL command via psql (requires psql in PATH or Docker)"""
    token = generate_token()
    
    # Try to use psql if available
    psql_cmd = ['psql', 
                f'postgresql://admin:{token}@{DSQL_HOST}:5432/{database}',
                '-c', sql]
    
    try:
        result = subprocess.run(psql_cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout
        else:
            print(f"Error: {result.stderr}", file=sys.stderr)
            return None
    except FileNotFoundError:
        print("psql not found. Trying with psycopg2...", file=sys.stderr)
        return None

def setup_with_psycopg2():
    """Setup using psycopg2 (Python library)"""
    try:
        import psycopg2
    except ImportError:
        print("ERROR: psycopg2 not installed. Install with: pip install psycopg2-binary", file=sys.stderr)
        return False
    
    token = generate_token()
    
    try:
        # Connect to postgres database
        conn = psycopg2.connect(
            host=DSQL_HOST,
            port=5432,
            user='admin',
            password=token,
            database='postgres',
            sslmode='require'
        )
        conn.autocommit = True
        cur = conn.cursor()
        
        print("✅ Connected to DSQL as admin")
        
        # Create IAM user
        print("Creating IAM database user...")
        cur.execute("""
            DO $$
            BEGIN
                IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'lambda_dsql_user') THEN
                    CREATE ROLE lambda_dsql_user WITH LOGIN;
                END IF;
            END $$;
        """)
        cur.execute("GRANT rds_iam TO lambda_dsql_user;")
        print("✅ IAM user 'lambda_dsql_user' created")
        
        # Create database
        print("Creating database...")
        try:
            cur.execute("CREATE DATABASE car_entities;")
            print("✅ Database 'car_entities' created")
        except psycopg2.errors.DuplicateDatabase:
            print("ℹ️  Database 'car_entities' already exists")
        
        # Connect to car_entities database
        conn.close()
        conn = psycopg2.connect(
            host=DSQL_HOST,
            port=5432,
            user='admin',
            password=token,
            database='car_entities',
            sslmode='require'
        )
        conn.autocommit = True
        cur = conn.cursor()
        
        # Create tables
        print("Creating tables...")
        schema_sql = """
        CREATE TABLE IF NOT EXISTS business_events (
            id VARCHAR(255) PRIMARY KEY,
            event_name VARCHAR(255) NOT NULL,
            event_type VARCHAR(255),
            created_date TIMESTAMP WITH TIME ZONE,
            saved_date TIMESTAMP WITH TIME ZONE,
            event_data JSONB NOT NULL
        );
        
        CREATE TABLE IF NOT EXISTS event_headers (
            id VARCHAR(255) PRIMARY KEY,
            event_name VARCHAR(255) NOT NULL,
            event_type VARCHAR(255),
            created_date TIMESTAMP WITH TIME ZONE,
            saved_date TIMESTAMP WITH TIME ZONE,
            header_data JSONB NOT NULL,
            CONSTRAINT fk_event_headers_business_events 
                FOREIGN KEY (id) REFERENCES business_events(id) 
                ON DELETE CASCADE
        );
        
        CREATE TABLE IF NOT EXISTS car_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL,
            event_id VARCHAR(255),
            CONSTRAINT fk_car_entities_event_headers 
                FOREIGN KEY (event_id) REFERENCES event_headers(id) 
                ON DELETE SET NULL
        );
        
        CREATE TABLE IF NOT EXISTS loan_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL,
            event_id VARCHAR(255),
            CONSTRAINT fk_loan_entities_event_headers 
                FOREIGN KEY (event_id) REFERENCES event_headers(id) 
                ON DELETE SET NULL
        );
        
        CREATE TABLE IF NOT EXISTS loan_payment_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL,
            event_id VARCHAR(255),
            CONSTRAINT fk_loan_payment_entities_event_headers 
                FOREIGN KEY (event_id) REFERENCES event_headers(id) 
                ON DELETE SET NULL
        );
        
        CREATE TABLE IF NOT EXISTS service_record_entities (
            entity_id VARCHAR(255) PRIMARY KEY,
            entity_type VARCHAR(255) NOT NULL,
            created_at TIMESTAMP WITH TIME ZONE,
            updated_at TIMESTAMP WITH TIME ZONE,
            entity_data JSONB NOT NULL,
            event_id VARCHAR(255),
            CONSTRAINT fk_service_record_entities_event_headers 
                FOREIGN KEY (event_id) REFERENCES event_headers(id) 
                ON DELETE SET NULL
        );
        
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lambda_dsql_user;
        GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lambda_dsql_user;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO lambda_dsql_user;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO lambda_dsql_user;
        """
        
        cur.execute(schema_sql)
        print("✅ All tables created")
        
        # List tables
        cur.execute("SELECT tablename FROM pg_tables WHERE schemaname = 'public';")
        tables = cur.fetchall()
        print(f"\n✅ Created {len(tables)} tables:")
        for table in tables:
            print(f"   - {table[0]}")
        
        cur.close()
        conn.close()
        
        print("\n✅ DSQL setup complete!")
        return True
        
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False

if __name__ == '__main__':
    print("=== DSQL Setup Script ===")
    print(f"DSQL Host: {DSQL_HOST}")
    print(f"Region: {AWS_REGION}\n")
    
    if setup_with_psycopg2():
        sys.exit(0)
    else:
        print("\nTo install psycopg2: pip install psycopg2-binary", file=sys.stderr)
        sys.exit(1)

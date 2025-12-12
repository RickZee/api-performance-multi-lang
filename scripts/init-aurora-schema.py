#!/usr/bin/env python3
"""Initialize Aurora RDS schema using Python."""

import asyncio
import asyncpg
import sys
import os
from pathlib import Path

# Get script directory
SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent
SCHEMA_FILE = REPO_ROOT / "data" / "schema.sql"

# Get connection details from Terraform
TERRAFORM_DIR = REPO_ROOT / "terraform"


async def get_terraform_output(output_name: str) -> str:
    """Get Terraform output value."""
    import subprocess
    try:
        result = subprocess.run(
            ["terraform", "output", "-raw", output_name],
            cwd=TERRAFORM_DIR,
            capture_output=True,
            text=True,
            check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return ""


async def get_password_from_tfvars() -> str:
    """Extract password from terraform.tfvars."""
    tfvars_file = TERRAFORM_DIR / "terraform.tfvars"
    if not tfvars_file.exists():
        return ""
    
    with open(tfvars_file, 'r') as f:
        for line in f:
            if 'database_password' in line:
                # Extract value between quotes
                import re
                match = re.search(r'"([^"]+)"', line)
                if match:
                    return match.group(1)
    return ""


async def main():
    """Main function to initialize schema."""
    print("=" * 40)
    print("Initialize Aurora RDS Schema")
    print("=" * 40)
    print()
    
    # Get connection details - prioritize environment variables (from Terraform provisioner)
    aurora_endpoint = os.getenv("AURORA_ENDPOINT", "")
    aurora_port = os.getenv("AURORA_PORT", "5432")
    db_name = os.getenv("DATABASE_NAME", "")
    db_user = os.getenv("DATABASE_USER", "")
    db_password = os.getenv("DATABASE_PASSWORD", "")
    
    # Fall back to Terraform outputs if env vars not set (for manual execution)
    if not aurora_endpoint:
        aurora_endpoint = await get_terraform_output("aurora_endpoint")
    if not db_name:
        db_name = await get_terraform_output("database_name") or "car_entities"
    if not db_user:
        db_user = await get_terraform_output("database_user") or "postgres"
    if not db_password:
        db_password = await get_password_from_tfvars()
    
    if not aurora_endpoint:
        print("✗ Aurora endpoint not found")
        print("  Run: cd terraform && terraform output aurora_endpoint")
        sys.exit(1)
    
    if not db_password:
        print("✗ Database password not found")
        print("  Set DATABASE_PASSWORD environment variable or check terraform.tfvars")
        sys.exit(1)
    
    if not SCHEMA_FILE.exists():
        print(f"✗ Schema file not found: {SCHEMA_FILE}")
        sys.exit(1)
    
    print(f"Aurora Endpoint: {aurora_endpoint}")
    print(f"Database: {db_name}")
    print(f"User: {db_user}")
    print()
    
    # Read schema file
    print("Reading schema file...")
    with open(SCHEMA_FILE, 'r') as f:
        schema_sql = f.read()
    
    # Connect to database
    print("Connecting to Aurora...")
    try:
        conn = await asyncpg.connect(
            host=aurora_endpoint,
            port=int(aurora_port),
            user=db_user,
            password=db_password,
            database=db_name
        )
        print("✓ Connected successfully")
        print()
        
        # Check if business_events table already exists
        print("Checking if schema already exists...")
        table_exists = await conn.fetchval("""
            SELECT EXISTS (
                SELECT FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_name = 'business_events'
            );
        """)
        
        if table_exists:
            print("✓ Schema already exists (business_events table found)")
            print("  Skipping schema initialization to avoid unnecessary re-runs")
        else:
            # Execute schema in a transaction for atomicity
            print("Running schema migration...")
            async with conn.transaction():
                # asyncpg.execute() can handle multiple statements in one call
                # This is more efficient and ensures proper execution order
                # The schema SQL is already idempotent (uses IF NOT EXISTS)
                try:
                    await conn.execute(schema_sql)
                except Exception as e:
                    # If executing all at once fails, try splitting statements
                    error_str = str(e).lower()
                    if 'relation' in error_str and 'does not exist' in error_str:
                        # This might be a statement ordering issue, try splitting
                        print("  Note: Executing statements individually for better error handling...")
                        # Split by semicolon and execute each statement
                        statements = []
                        parts = schema_sql.split(';')
                        
                        for part in parts:
                            # Clean up the statement
                            stmt = part.strip()
                            # Remove leading/trailing whitespace and normalize newlines
                            stmt = ' '.join(line.strip() for line in stmt.split('\n') if line.strip() and not line.strip().startswith('--'))
                            # Skip empty statements
                            if stmt:
                                statements.append(stmt)
                        
                        # Execute each statement with semicolon
                        for stmt in statements:
                            if stmt:
                                try:
                                    # Ensure statement ends with semicolon
                                    if not stmt.rstrip().endswith(';'):
                                        stmt = stmt + ';'
                                    await conn.execute(stmt)
                                except Exception as e2:
                                    # Ignore "already exists" errors for idempotent operations
                                    error_str2 = str(e2).lower()
                                    if 'already exists' not in error_str2 and 'duplicate' not in error_str2:
                                        print(f"  Error executing statement: {stmt[:100]}...")
                                        raise
                    else:
                        # Re-raise if it's not a relation error
                        raise
            print("✓ Schema initialized successfully")
            print()
        
        # Verify tables
        print("Verifying tables...")
        tables = await conn.fetch("""
            SELECT tablename 
            FROM pg_tables 
            WHERE schemaname = 'public'
            ORDER BY tablename;
        """)
        
        if tables:
            print("Tables found:")
            for table in tables:
                print(f"  - {table['tablename']}")
        else:
            print("  No tables found")
        
        await conn.close()
        print()
        print("✓ Schema initialization complete!")
        
    except Exception as e:
        print(f"✗ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())

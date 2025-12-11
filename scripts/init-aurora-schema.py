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
    
    # Get connection details
    aurora_endpoint = await get_terraform_output("aurora_endpoint")
    db_name = await get_terraform_output("database_name") or "car_entities"
    db_user = await get_terraform_output("database_user") or "postgres"
    db_password = await get_password_from_tfvars()
    
    if not db_password:
        db_password = os.getenv("DATABASE_PASSWORD", "")
    
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
            port=5432,
            user=db_user,
            password=db_password,
            database=db_name
        )
        print("✓ Connected successfully")
        print()
        
        # Execute schema
        print("Running schema migration...")
        await conn.execute(schema_sql)
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
            print("Tables created:")
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

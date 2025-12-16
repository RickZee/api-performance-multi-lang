#!/usr/bin/env python3
"""Fix PostgreSQL User Replication Privileges for CDC
Grants REPLICATION privilege to the postgres user for Debezium CDC connector
"""

import os
import sys
import asyncio
import asyncpg
from pathlib import Path

# Get project root
PROJECT_ROOT = Path(__file__).parent.parent.parent

# Colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
NC = '\033[0m'

def print_colored(message, color=NC):
    """Print colored message."""
    print(f"{color}{message}{NC}")

def get_password():
    """Get database password from various sources."""
    # Try environment variable first
    password = os.getenv("DB_PASSWORD") or os.getenv("AURORA_PASSWORD")
    
    # Try .env.aurora file
    if not password:
        env_file = PROJECT_ROOT / ".env.aurora"
        if env_file.exists():
            with open(env_file) as f:
                for line in f:
                    if line.startswith("export DB_PASSWORD="):
                        password = line.split('"')[1] if '"' in line else line.split("=")[1].strip()
                        break
    
    # Try terraform.tfvars
    if not password:
        tfvars = PROJECT_ROOT / "terraform" / "terraform.tfvars"
        if tfvars.exists():
            with open(tfvars) as f:
                for line in f:
                    if line.strip().startswith("database_password"):
                        password = line.split('"')[1] if '"' in line else line.split("=")[1].strip()
                        break
    
    return password

async def check_replication_role(conn, username):
    """Check if user has rds_replication role."""
    # Check if user has rds_replication role
    has_role = await conn.fetchval(
        "SELECT COUNT(*) > 0 FROM pg_roles r1, pg_roles r2, pg_auth_members m "
        "WHERE r1.rolname = $1 AND m.member = r1.oid AND m.roleid = r2.oid "
        "AND r2.rolname = 'rds_replication'",
        username
    )
    return has_role

async def check_replication_privilege(conn, username):
    """Check if user has REPLICATION privilege (legacy check)."""
    result = await conn.fetchval(
        "SELECT rolreplication FROM pg_roles WHERE rolname = $1",
        username
    )
    return result

async def grant_replication_role(conn, username):
    """Grant rds_replication role to user (Aurora PostgreSQL method)."""
    await conn.execute(f"GRANT rds_replication TO {username};")

async def main():
    """Main function."""
    print_colored("=" * 40, BLUE)
    print_colored("Fix PostgreSQL Replication Privileges", BLUE)
    print_colored("=" * 40, BLUE)
    print()
    
    # Get connection details
    endpoint = os.getenv("AURORA_ENDPOINT", 
                        "producer-api-aurora-cluster.cluster-chjum3h144b6.us-east-1.rds.amazonaws.com")
    db_user = os.getenv("DB_USER", "postgres")
    db_name = os.getenv("DB_NAME", "car_entities")
    db_password = get_password()
    
    if not db_password:
        print_colored("✗ Database password not found", RED)
        print("  Set DB_PASSWORD environment variable or ensure .env.aurora exists")
        sys.exit(1)
    
    print_colored("Configuration:", CYAN)
    print(f"  Endpoint: {endpoint}")
    print(f"  User: {db_user}")
    print(f"  Database: {db_name}")
    print()
    
    # Step 1: Check current privileges
    print_colored("Step 1: Checking current user privileges...", BLUE)
    
    try:
        conn = await asyncpg.connect(
            host=endpoint,
            port=5432,
            user=db_user,
            password=db_password,
            database=db_name,
            ssl='require',
            timeout=10
        )
        
        # Check for rds_replication role (Aurora PostgreSQL method)
        has_rds_replication = await check_replication_role(conn, db_user)
        has_replication_priv = await check_replication_privilege(conn, db_user)
        
        if has_rds_replication or has_replication_priv:
            print_colored("✓ User already has replication privileges", GREEN)
            if has_rds_replication:
                print_colored("  (has rds_replication role)", CYAN)
            if has_replication_priv:
                print_colored("  (has REPLICATION privilege)", CYAN)
            print()
            print_colored("User privileges are correct.", CYAN)
            print("  If connector still fails, check:")
            print("    1. Connector logs: confluent connect cluster logs <connector-id>")
            print("    2. Security group allows Confluent Cloud IPs")
            print("    3. Database is accessible from Confluent Cloud")
            await conn.close()
            return 0
        else:
            print_colored(f"⚠ User does NOT have replication privileges", YELLOW)
            print_colored("  (missing rds_replication role and REPLICATION privilege)", CYAN)
        
        print()
        
        # Step 2: Grant rds_replication role (Aurora PostgreSQL method)
        print_colored("Step 2: Granting rds_replication role...", BLUE)
        print_colored("  (Aurora PostgreSQL uses rds_replication role, not REPLICATION privilege)", CYAN)
        
        try:
            await grant_replication_role(conn, db_user)
            print_colored("✓ rds_replication role granted successfully", GREEN)
        except Exception as e:
            error_msg = str(e)
            if "permission denied" in error_msg.lower() or "must be superuser" in error_msg.lower():
                print_colored("✗ Cannot grant rds_replication role - insufficient privileges", RED)
                print()
                print_colored("Solution:", CYAN)
                print("  The postgres user needs rds_superuser role to grant rds_replication.")
                print("  In Aurora PostgreSQL, the master user should have rds_superuser by default.")
                print()
                print("  Try one of these:")
                print("  1. Check if postgres has rds_superuser role:")
                print("     SELECT r.rolname, m.roleid FROM pg_roles r, pg_auth_members m")
                print("     WHERE r.oid = m.member AND r.rolname = 'postgres';")
                print()
                print("  2. If postgres doesn't have rds_superuser, you may need to:")
                print("     - Use AWS RDS Console to modify the cluster")
                print("     - Or recreate the cluster with proper master user privileges")
                print("     - Or connect as rdsadmin (system user) to grant the role")
                await conn.close()
                return 1
            else:
                raise
        
        print()
        
        # Step 3: Verify privileges
        print_colored("Step 3: Verifying privileges...", BLUE)
        
        verify_role = await check_replication_role(conn, db_user)
        
        if verify_role:
            print_colored("✓ Verified: User has rds_replication role", GREEN)
        else:
            print_colored("✗ Verification failed: User still does not have rds_replication role", RED)
            await conn.close()
            return 1
        
        print()
        
        # Step 4: Check other privileges
        print_colored("Step 4: Checking additional privileges...", BLUE)
        
        all_privs = await conn.fetchrow(
            "SELECT rolname, rolreplication, rolsuper FROM pg_roles WHERE rolname = $1",
            db_user
        )
        
        print_colored("User privileges:", CYAN)
        print(f"  User: {all_privs['rolname']}")
        print(f"  REPLICATION: {all_privs['rolreplication']}")
        print(f"  SUPERUSER: {all_privs['rolsuper']}")
        print()
        
        await conn.close()
        
        # Summary
        print_colored("=" * 40, BLUE)
        print_colored("Replication Privileges Fixed!", GREEN)
        print_colored("=" * 40, BLUE)
        print()
        print_colored("Next Steps:", CYAN)
        print("  1. Restart the connector:")
        print("     confluent connect cluster pause <connector-id>")
        print("     confluent connect cluster resume <connector-id>")
        print()
        print("  2. Wait a few seconds and check connector status:")
        print("     confluent connect cluster describe <connector-id>")
        print()
        print("  3. If still failing, check connector logs:")
        print("     confluent connect cluster logs <connector-id>")
        print()
        print_colored("Note:", CYAN)
        print("  The 'pg_hba.conf' error in Aurora PostgreSQL is misleading.")
        print("  It typically means the user lacks REPLICATION privilege,")
        print("  which is now fixed. The connector should be able to connect.")
        print()
        
        return 0
        
    except asyncpg.exceptions.InvalidPasswordError:
        print_colored("✗ Authentication failed - incorrect password", RED)
        return 1
    except asyncpg.exceptions.InvalidCatalogNameError:
        print_colored(f"✗ Database '{db_name}' does not exist", RED)
        return 1
    except Exception as e:
        print_colored(f"✗ Failed to connect to database: {e}", RED)
        print()
        print_colored("Troubleshooting:", CYAN)
        print("  1. Verify database credentials are correct")
        print("  2. Check if security group allows your IP")
        print("  3. Verify endpoint is correct")
        return 1

if __name__ == "__main__":
    sys.exit(asyncio.run(main()))

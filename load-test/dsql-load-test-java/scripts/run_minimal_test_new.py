#!/usr/bin/env python3
"""
Run minimal test using new simplified architecture.
"""

import sys
import os
from pathlib import Path
from datetime import datetime

sys.path.insert(0, str(Path(__file__).parent.parent))

from test_suite.config import Config
from test_suite.executor import RemoteExecutor
from test_suite.runner import TestRunner, TestConfigLoader


def create_minimal_config(tmp_path):
    """Create a minimal test-config.json for testing."""
    import json
    
    minimal_config = {
        "baseline": {
            "threads": 2,
            "iterations": 2,
            "batch_size": 2,
            "payload_size": None,
            "event_type": "CarCreated"
        },
        "test_groups": {
            "minimal_scenario1": {
                "scenario": 1,
                "threads": 2,
                "iterations": 2,
                "count": 2,
                "payload_size": None,
                "tags": ["minimal"]
            },
            "minimal_scenario2": {
                "scenario": 2,
                "threads": 2,
                "iterations": 2,
                "count": 2,
                "payload_size": None,
                "tags": ["minimal"]
            }
        }
    }
    
    config_file = tmp_path / 'test-config-minimal.json'
    with open(config_file, 'w') as f:
        json.dump(minimal_config, f, indent=2)
    
    return str(config_file)


def main():
    print("=" * 80)
    print("Minimal Test Run - Simplified Architecture")
    print("=" * 80)
    print()
    
    # Check for required environment variables
    try:
        config = Config.from_env()
    except ValueError as e:
        print(f"Error: {e}")
        print("\nPlease set required environment variables:")
        print("  export DSQL_HOST=your-host.dsql.us-east-1.on.aws")
        print("  export TEST_RUNNER_INSTANCE_ID=i-xxxxxxxxxxxxx")
        print("  export S3_BUCKET=your-bucket-name")
        sys.exit(1)
    
    print(f"DSQL Host: {config.dsql_host}")
    print(f"Instance ID: {config.instance_id}")
    print(f"S3 Bucket: {config.s3_bucket}")
    print()
    
    # Create minimal config
    script_dir = Path(__file__).parent.parent
    minimal_config_path = create_minimal_config(script_dir)
    
    # Create results directory
    timestamp = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
    results_dir = script_dir / 'results' / f'minimal-{timestamp}'
    
    # Initialize
    executor = RemoteExecutor(config)
    
    # Ensure EC2 instance is ready
    print("=== Checking EC2 Instance ===")
    if not executor.ensure_instance_ready():
        print("Error: Failed to start EC2 instance or SSM agent not ready")
        sys.exit(1)
    print()
    
    # Clear database before running tests
    print("=== Clearing DSQL Database ===")
    clear_commands = [
        "set +e",
        f"export DSQL_HOST={config.dsql_host}",
        "export DSQL_PORT=5432",
        "export DATABASE_NAME=postgres",
        f"export IAM_USERNAME={config.iam_username}",
        f"export AWS_REGION={config.region}",
        "python3 << 'PYTHON_EOF'",
        "import psycopg2",
        "import os",
        "import sys",
        "from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT",
        "",
        "try:",
        "    conn_string = f\"host={os.environ['DSQL_HOST']} port=5432 dbname=postgres user={os.environ['IAM_USERNAME']} sslmode=require\"",
        "    conn = psycopg2.connect(conn_string)",
        "    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)",
        "    cur = conn.cursor()",
        "    # Drop the table (DSQL doesn't support TRUNCATE)",
        "    print('Dropping table car_entities_schema.business_events...')",
        "    cur.execute('DROP TABLE IF EXISTS car_entities_schema.business_events CASCADE')",
        "    # Recreate the table",
        "    print('Recreating table...')",
        "    cur.execute('''",
        "        CREATE TABLE car_entities_schema.business_events (",
        "            id VARCHAR(255) PRIMARY KEY,",
        "            event_name VARCHAR(255) NOT NULL,",
        "            event_type VARCHAR(255),",
        "            created_date TIMESTAMP WITH TIME ZONE,",
        "            saved_date TIMESTAMP WITH TIME ZONE,",
        "            event_data TEXT NOT NULL",
        "        )",
        "    ''')",
        "    cur.close()",
        "    conn.close()",
        "    print('SUCCESS')",
        "except Exception as e:",
        "    print(f'ERROR: {e}', file=sys.stderr)",
        "    sys.exit(1)",
        "PYTHON_EOF",
    ]
    
    success, stdout, stderr = executor.run_command(clear_commands, timeout=60)
    
    if success and 'SUCCESS' in stdout:
        print("✓ Database cleared successfully")
    else:
        print("⚠️  Database clear failed or incomplete")
        if stderr:
            print(f"Error: {stderr[:500]}")
        print("Continuing anyway...")
    print()
    
    runner = TestRunner(
        config=config,
        executor=executor,
        config_path=minimal_config_path,
        results_dir=str(results_dir),
        max_pool_size=10,  # Small pool for minimal test
        connection_rate_limit=100
    )
    
    # Run minimal tests
    print("Running minimal test suite (2 tests)...")
    print()
    
    try:
        result = runner.run_suite(test_groups=['minimal_scenario1', 'minimal_scenario2'])
        
        print()
        print("=" * 80)
        print("Minimal Test Complete")
        print("=" * 80)
        print(f"Results directory: {results_dir}")
        print(f"Completed: {result['completed']}/{result['total']}")
        print(f"Failed: {result['failed']}/{result['total']}")
        print()
        print("Next step: Analyze results")
        print(f"  python3 scripts/analyze_results.py {results_dir}")
        
        return result['results_dir']
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(130)


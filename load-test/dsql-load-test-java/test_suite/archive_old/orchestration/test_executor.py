"""
Execute individual tests on EC2.
"""

import os
import tempfile
from pathlib import Path
from typing import Optional, List, Tuple
from datetime import datetime
from test_suite.config.loader import TestDefinition
from test_suite.infrastructure.ssm_executor import SSMExecutor, SSMExecutionError
from test_suite.archive.manager import ArchiveManager, ArchiveError
from test_suite.infrastructure.s3_manager import S3Manager


class TestExecutionError(Exception):
    """Test execution errors."""
    pass


class TestExecutor:
    """Execute individual tests on EC2."""
    
    def __init__(
        self,
        ssm_executor: SSMExecutor,
        s3_manager: Optional[S3Manager],
        source_dir: str,
        dsql_host: str,
        iam_username: str,
        aws_region: str,
        max_pool_size: int = 2000,
        connection_rate_limit: int = 100
    ):
        self.ssm_executor = ssm_executor
        self.s3_manager = s3_manager
        self.source_dir = Path(source_dir)
        self.dsql_host = dsql_host
        self.iam_username = iam_username
        self.aws_region = aws_region
        self.max_pool_size = max_pool_size
        self.connection_rate_limit = connection_rate_limit
    
    def prepare_archive(self) -> str:
        """Create and upload deployment archive."""
        # Create archive
        archive_manager = ArchiveManager(str(self.source_dir))
        archive_path = os.path.join(tempfile.gettempdir(), 'dsql-load-test-java.tar.gz')
        
        try:
            archive_manager.create_archive(archive_path)
            print(f"Created archive: {archive_path} ({archive_manager.get_archive_size(archive_path)} bytes)")
        except ArchiveError as e:
            raise TestExecutionError(f"Failed to create archive: {e}") from e
        
        # Upload to S3 if available
        if self.s3_manager and self.s3_manager.bucket_name:
            s3_key = "dsql-load-test-java.tar.gz"
            if self.s3_manager.upload_file(archive_path, s3_key):
                print(f"Uploaded archive to S3: s3://{self.s3_manager.bucket_name}/{s3_key}")
            else:
                print("Warning: Failed to upload to S3, will use direct transfer")
        
        return archive_path
    
    def clear_database(self) -> bool:
        """Clear DSQL database by dropping and recreating the business_events table.
        
        DSQL doesn't support TRUNCATE, so we must DROP and recreate.
        
        Returns:
            True if successful, False otherwise
        """
        print("=== Clearing DSQL database ===")
        
        # DSQL doesn't support TRUNCATE, so we DROP and recreate
        commands = [
            "set +e",
            f"export DSQL_HOST={self.dsql_host}",
            "export DSQL_PORT=5432",
            "export DATABASE_NAME=postgres",
            f"export IAM_USERNAME={self.iam_username}",
            f"export AWS_REGION={self.aws_region}",
            # Use Python to connect and clear database
            "python3 << 'PYTHON_EOF'",
            "import psycopg2",
            "import os",
            "import sys",
            "from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT",
            "",
            "try:",
            "    conn_string = f\"host={{os.environ['DSQL_HOST']}} port=5432 dbname=postgres user={{os.environ['IAM_USERNAME']}} sslmode=require\"",
            "    conn = psycopg2.connect(conn_string)",
            "    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)",
            "    cur = conn.cursor()",
            "    ",
            "    # Get current count",
            "    cur.execute('SELECT COUNT(*) FROM car_entities_schema.business_events')",
            "    current_count = cur.fetchone()[0]",
            "    print(f'Current row count: {{current_count}}')",
            "    ",
            "    # Drop the table (DSQL doesn't support TRUNCATE)",
            "    print('Dropping table...')",
            "    cur.execute('DROP TABLE IF EXISTS car_entities_schema.business_events CASCADE')",
            "    ",
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
            "    ",
            "    # Verify",
            "    cur.execute('SELECT COUNT(*) FROM car_entities_schema.business_events')",
            "    new_count = cur.fetchone()[0]",
            "    print(f'Database cleared! New row count: {{new_count}}')",
            "    ",
            "    cur.close()",
            "    conn.close()",
            "    print('SUCCESS')",
            "except Exception as e:",
            "    print(f'ERROR: {{e}}', file=sys.stderr)",
            "    sys.exit(1)",
            "PYTHON_EOF",
        ]
        
        try:
            result = self.ssm_executor.execute_command(commands, timeout=60)
            if result.status == 'Success' and 'SUCCESS' in result.output:
                print("✓ Database cleared successfully")
                return True
            else:
                print(f"✗ Database clear failed: {result.error}")
                if result.output:
                    print(f"Output: {result.output[:500]}")
                return False
        except SSMExecutionError as e:
            print(f"✗ SSM execution error during database clear: {e}")
            return False
    
    def prepare_environment(self) -> bool:
        """Prepare EC2 environment once: download, extract, and build.
        
        Returns:
            True if successful, False otherwise
        """
        print("=== Preparing EC2 environment (download, extract, build) ===")
        
        commands = [
            "set +e",
            "cd /tmp",
            "mkdir -p /tmp/results",
            # Check if already built
            "if [ -f /tmp/dsql-load-test-java/target/dsql-load-test-1.0.0.jar ]; then",
            "  echo 'JAR already exists, skipping build'",
            "  exit 0",
            "fi",
            # Clean up old directory if it exists
            "rm -rf dsql-load-test-java",
            "mkdir -p dsql-load-test-java",
            "cd dsql-load-test-java || exit 1",
        ]
        
        # Download archive from S3
        if self.s3_manager and self.s3_manager.bucket_name:
            commands.extend([
                f"echo 'Downloading archive from S3...'",
                f"command -v aws >/dev/null 2>&1 && aws s3 cp s3://{self.s3_manager.bucket_name}/dsql-load-test-java.tar.gz ./ || "
                f"/usr/bin/aws s3 cp s3://{self.s3_manager.bucket_name}/dsql-load-test-java.tar.gz ./ || "
                f"{{ echo 'ERROR: Failed to download archive from S3'; exit 1; }}"
            ])
        else:
            commands.append("echo 'S3 not available'")
            return False
        
        commands.extend([
            "if [ ! -f dsql-load-test-java.tar.gz ]; then echo 'ERROR: Archive file not found'; exit 1; fi",
            "echo 'Extracting archive...'",
            "tar xzf dsql-load-test-java.tar.gz || { echo 'ERROR: Failed to extract archive'; exit 1; }",
            "if [ ! -f pom.xml ]; then echo 'ERROR: pom.xml not found after extraction'; ls -la; exit 1; fi",
            "echo 'Extraction successful - pom.xml found'",
            "if ! command -v mvn &> /dev/null; then echo 'Installing Maven...'; dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1 || true; fi",
            "echo 'Building application (this may take a few minutes)...'",
            "mvn clean package -DskipTests -q || { echo 'ERROR: Maven build failed'; exit 1; }",
            "if [ ! -f target/dsql-load-test-1.0.0.jar ]; then",
            "  echo 'ERROR: JAR file not found after build';",
            "  ls -la target/ 2>/dev/null || echo 'target directory does not exist';",
            "  exit 1;",
            "fi",
            "echo 'Build successful - JAR ready at /tmp/dsql-load-test-java/target/dsql-load-test-1.0.0.jar'",
        ])
        
        try:
            # Maven build can take 5-10 minutes, but we should timeout if it takes longer
            # Use 15 minutes max for environment preparation (download + extract + build)
            result = self.ssm_executor.execute_command(commands, timeout=900)
            if result.status == 'Success':
                print("✓ Environment prepared successfully")
                return True
            else:
                print(f"✗ Environment preparation failed: {result.error}")
                return False
        except SSMExecutionError as e:
            print(f"✗ SSM execution error during environment preparation: {e}")
            return False
    
    def execute_test(self, test_def: TestDefinition) -> Tuple[bool, Optional[datetime], Optional[datetime]]:
        """Execute a single test on EC2.
        
        Returns:
            Tuple of (success: bool, start_time: datetime, end_time: datetime)
        """
        # Build SSM commands
        commands = self._build_test_commands(test_def)
        
        start_time = datetime.utcnow()
        
        try:
            # Calculate reasonable timeout based on test parameters
            # Base: 60s for JVM startup + DSQL connection + HikariCP init
            # Per-thread overhead: 5s per thread (connection pool growth)
            # Per-iteration overhead: 1s per 10 iterations
            # Minimum: 180s, Maximum: 600s
            base_timeout = 60
            thread_overhead = test_def.threads * 5
            iteration_overhead = (test_def.iterations * test_def.count) // 10
            test_timeout = min(600, max(180, base_timeout + thread_overhead + iteration_overhead))
            result = self.ssm_executor.execute_command(commands, timeout=test_timeout)
            
            end_time = datetime.utcnow()
            
            if result.status == 'Success':
                # Check if result file was created
                check_commands = [
                    f"if [ -f /tmp/results/{test_def.test_id}.json ]; then",
                    f"  FILE_SIZE=$(stat -f%z /tmp/results/{test_def.test_id}.json 2>/dev/null || stat -c%s /tmp/results/{test_def.test_id}.json 2>/dev/null || echo 0)",
                    f"  if [ $FILE_SIZE -gt 50000 ]; then",
                ]
                
                if self.s3_manager and self.s3_manager.bucket_name:
                    check_commands.extend([
                        f"    (command -v aws >/dev/null 2>&1 && aws s3 cp /tmp/results/{test_def.test_id}.json s3://{self.s3_manager.bucket_name}/test-results/{test_def.test_id}.json 2>&1 || /usr/bin/aws s3 cp /tmp/results/{test_def.test_id}.json s3://{self.s3_manager.bucket_name}/test-results/{test_def.test_id}.json 2>&1) && echo 'Uploaded to S3' || echo 'S3 upload failed'",
                    ])
                else:
                    check_commands.append("    echo 'S3 bucket not configured'")
                
                check_commands.extend([
                    "  fi",
                    "  echo 'Result file exists'",
                    "else",
                    "  echo 'Result file not found'",
                    "fi"
                ])
                
                # Run check command
                check_result = self.ssm_executor.execute_command(check_commands, timeout=30)
                print(f"  Test execution: {result.status}")
                if check_result.output:
                    print(f"  {check_result.output.strip()}")
                
                return (result.status == 'Success', start_time, end_time)
            else:
                end_time = datetime.utcnow()
                print(f"  Test execution failed: {result.error}")
                print(f"  Exit code: {result.exit_code}")
                print(f"  Output: {result.output[:500] if result.output else 'None'}")
                if result.error:
                    print(f"  Error output: {result.error[:500]}")
                return (False, start_time, end_time)
                
        except SSMExecutionError as e:
            end_time = datetime.utcnow()
            print(f"  SSM execution error: {e}")
            return (False, start_time, end_time)
    
    def _build_test_commands(self, test_def: TestDefinition) -> List[str]:
        """Build SSM commands for test execution.
        
        Assumes environment is already prepared (archive downloaded, extracted, built).
        """
        # Determine payload size export
        payload_export = f"export PAYLOAD_SIZE={test_def.payload_size}" if test_def.payload_size != 'default' else "unset PAYLOAD_SIZE"
        
        # Build commands - just run the test, no download/extract/build
        commands = [
            "set +e",
            "cd /tmp/dsql-load-test-java",
            # Verify JAR exists (should be built by prepare_environment)
            "if [ ! -f target/dsql-load-test-1.0.0.jar ]; then",
            "  echo 'ERROR: JAR file not found. Environment may not be prepared.';",
            "  echo 'Expected location: /tmp/dsql-load-test-java/target/dsql-load-test-1.0.0.jar';",
            "  ls -la target/ 2>/dev/null || echo 'target directory does not exist';",
            "  exit 1;",
            "fi",
            "echo 'Using pre-built JAR (no rebuild needed)'",
            f"export DSQL_HOST={self.dsql_host}",
            "export DSQL_PORT=5432",
            "export DATABASE_NAME=postgres",
            f"export IAM_USERNAME={self.iam_username}",
            f"export AWS_REGION={self.aws_region}",
            f"export SCENARIO={test_def.scenario}",
            f"export THREADS={test_def.threads}",
            f"export ITERATIONS={test_def.iterations}",
            f"export COUNT={test_def.count}",
            "export EVENT_TYPE=CarCreated",
            payload_export,
            f"export TEST_ID={test_def.test_id}",
            "export OUTPUT_DIR=/tmp/results",
            f"export MAX_POOL_SIZE={self.max_pool_size}",
            f"export DSQL_CONNECTION_RATE_LIMIT={self.connection_rate_limit}",
            "echo 'OUTPUT_DIR is set to: $OUTPUT_DIR'",
            "echo 'TEST_ID is set to: $TEST_ID'",
            "JAVA_EXIT=0",
            "java -jar target/dsql-load-test-1.0.0.jar 2>&1 | tee /tmp/test-output.log || JAVA_EXIT=$?",
            "echo '=== Java application exit code: $JAVA_EXIT ==='",
            "sleep 3",
            "echo '=== Result files after test ==='",
            "ls -lah /tmp/results/ 2>/dev/null || echo 'No results directory'",
        ]
        
        return commands


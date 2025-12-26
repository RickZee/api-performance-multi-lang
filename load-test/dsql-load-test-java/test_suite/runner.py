"""
Test runner - orchestrates test execution.
"""

import json
import os
import tarfile
import tempfile
from pathlib import Path
from typing import List, Optional, Dict, Any
from dataclasses import dataclass
from datetime import datetime, timezone

from test_suite.config import Config
from test_suite.executor import RemoteExecutor
from test_suite.resource_metrics import ResourceMetricsCollector


@dataclass
class TestDefinition:
    """Represents a single test configuration."""
    test_id: str
    scenario: int
    threads: int
    iterations: int
    count: int
    batch_size: Optional[int] = None
    payload_size: Optional[str] = None
    event_type: str = "CarCreated"
    tags: List[str] = None
    
    def __post_init__(self):
        if self.tags is None:
            self.tags = []


class TestConfigLoader:
    """Load and normalize test configuration from JSON."""
    
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.config: Dict[str, Any] = {}
    
    def load_config(self) -> Dict[str, Any]:
        """Load test-config.json."""
        if not self.config_path.exists():
            raise FileNotFoundError(f"Config file not found: {self.config_path}")
        
        with open(self.config_path, 'r') as f:
            self.config = json.load(f)
        
        return self.config
    
    def normalize_value(self, value: Any) -> List[Any]:
        """Convert single values to lists for uniform processing."""
        if value is None:
            return [None]
        if isinstance(value, list):
            return value
        return [value]
    
    def generate_test_matrix(self, test_groups: Optional[List[str]] = None) -> List[TestDefinition]:
        """Generate all test combinations from config."""
        if not self.config:
            self.load_config()
        
        baseline = self.config.get('baseline', {})
        test_groups_config = self.config.get('test_groups', {})
        
        # If specific groups requested, filter
        if test_groups:
            test_groups_config = {k: v for k, v in test_groups_config.items() if k in test_groups}
        
        tests: List[TestDefinition] = []
        test_counter = 1
        
        for group_name, group_config in test_groups_config.items():
            # Normalize all values to lists
            threads_list = self.normalize_value(
                group_config.get('threads', baseline.get('threads', 10))
            )
            iterations_list = self.normalize_value(
                group_config.get('iterations', baseline.get('iterations', 20))
            )
            count_list = self.normalize_value(
                group_config.get('count', group_config.get('batch_size', baseline.get('batch_size', 10)))
            )
            payload_list = self.normalize_value(
                group_config.get('payload_size', baseline.get('payload_size'))
            )
            scenario = group_config.get('scenario', 1)
            event_type = group_config.get('event_type', baseline.get('event_type', 'CarCreated'))
            tags = group_config.get('tags', baseline.get('tags', []))
            if not isinstance(tags, list):
                tags = [tags] if tags else []
            
            # Generate all combinations
            for threads in threads_list:
                for iterations in iterations_list:
                    for count in count_list:
                        for payload_size in payload_list:
                            # Determine batch_size based on scenario
                            batch_size = None
                            if scenario == 2:
                                batch_size = count
                            
                            # Generate test ID
                            test_id = f"test-{test_counter:03d}-{group_name}-threads{threads}-loops{iterations}-count{count}"
                            
                            if scenario == 2 and batch_size:
                                test_id += f"-batch{batch_size}"
                            
                            if payload_size:
                                test_id += f"-payload{payload_size}"
                            else:
                                test_id += "-payloaddefault"
                            
                            test_def = TestDefinition(
                                test_id=test_id,
                                scenario=scenario,
                                threads=threads,
                                iterations=iterations,
                                count=count,
                                batch_size=batch_size,
                                payload_size=payload_size if payload_size else 'default',
                                event_type=event_type,
                                tags=tags
                            )
                            
                            tests.append(test_def)
                            test_counter += 1
        
        return tests


class TestRunner:
    """Orchestrate test suite execution."""
    
    def __init__(
        self,
        config: Config,
        executor: RemoteExecutor,
        config_path: str,
        results_dir: str,
        max_pool_size: int = 2000,
        connection_rate_limit: int = 100
    ):
        self.config = config
        self.executor = executor
        self.config_path = Path(config_path)
        self.results_dir = Path(results_dir)
        self.results_dir.mkdir(parents=True, exist_ok=True)
        self.max_pool_size = max_pool_size
        self.connection_rate_limit = connection_rate_limit
        
        # Load completed tests
        self.completed_file = self.results_dir / 'completed.json'
        self.completed: set[str] = self._load_completed()
        
        # Source directory for archive
        self.source_dir = self.config_path.parent
        
        # Resource metrics collector
        self.resource_metrics_collector = ResourceMetricsCollector(config, config.instance_id)
    
    def _load_completed(self) -> set[str]:
        """Load set of completed test IDs."""
        if self.completed_file.exists():
            try:
                with open(self.completed_file, 'r') as f:
                    data = json.load(f)
                    return set(data.get('completed', []))
            except Exception:
                pass
        return set()
    
    def _save_completed(self) -> None:
        """Save set of completed test IDs."""
        with open(self.completed_file, 'w') as f:
            json.dump({'completed': list(self.completed)}, f, indent=2)
    
    def _create_archive(self) -> str:
        """Create tar.gz archive of source directory."""
        archive_path = os.path.join(tempfile.gettempdir(), 'dsql-load-test-java.tar.gz')
        
        print(f"Creating archive: {archive_path}")
        with tarfile.open(archive_path, 'w:gz') as tar:
            # Add pom.xml
            pom_path = self.source_dir / 'pom.xml'
            if pom_path.exists():
                tar.add(pom_path, arcname='pom.xml')
            
            # Add src/ directory
            src_path = self.source_dir / 'src'
            if src_path.exists():
                tar.add(src_path, arcname='src', recursive=True)
        
        # Validate archive
        try:
            with tarfile.open(archive_path, 'r:gz') as tar:
                names = tar.getnames()
                if 'pom.xml' not in names:
                    raise ValueError("Archive missing pom.xml")
        except Exception as e:
            raise RuntimeError(f"Archive validation failed: {e}")
        
        size = os.path.getsize(archive_path)
        print(f"Archive created: {archive_path} ({size} bytes)")
        return archive_path
    
    def _prepare_environment(self) -> bool:
        """Prepare EC2 environment: upload archive, download, extract, build."""
        print("=== Preparing EC2 environment ===")
        
        # Create and upload archive
        archive_path = self._create_archive()
        s3_key = "dsql-load-test-java.tar.gz"
        
        if not self.executor.upload_file(archive_path, s3_key):
            print("Failed to upload archive to S3")
            return False
        
        print(f"Uploaded archive to S3: s3://{self.config.s3_bucket}/{s3_key}")
        
        # Prepare environment on EC2
        # Use /usr/bin/aws explicitly to avoid architecture mismatch issues
        commands = [
            "set +e",
            "export PATH=/usr/bin:/usr/local/bin:$PATH",
            "cd /tmp",
            "mkdir -p /tmp/results",
            # Check if already built
            "if [ -f /tmp/dsql-load-test-java/target/dsql-load-test-1.0.0.jar ]; then",
            "  echo 'JAR already exists, skipping build'",
            "  exit 0",
            "fi",
            # Clean up old directory
            "rm -rf dsql-load-test-java",
            "mkdir -p dsql-load-test-java",
            "cd dsql-load-test-java || exit 1",
            # Use /usr/bin/aws explicitly (works on ARM64 instances)
            f"/usr/bin/aws s3 cp s3://{self.config.s3_bucket}/{s3_key} ./ || exit 1",
            "tar xzf dsql-load-test-java.tar.gz || exit 1",
            "if [ ! -f pom.xml ]; then echo 'ERROR: pom.xml not found'; exit 1; fi",
            "if ! command -v mvn &> /dev/null; then dnf install -y maven >/dev/null 2>&1 || yum install -y maven >/dev/null 2>&1 || true; fi",
            "mvn clean package -DskipTests -q || exit 1",
            "if [ ! -f target/dsql-load-test-1.0.0.jar ]; then echo 'ERROR: JAR not found'; exit 1; fi",
            "echo 'Environment prepared successfully'"
        ]
        
        success, stdout, stderr = self.executor.run_command(commands, timeout=900)
        
        # Check for success - either "Environment prepared successfully" or "JAR already exists"
        if success and ('Environment prepared successfully' in stdout or 'JAR already exists' in stdout):
            if 'JAR already exists' in stdout:
                print("✓ Environment already prepared (JAR exists)")
            else:
                print("✓ Environment prepared")
            return True
        else:
            print(f"✗ Environment preparation failed")
            print(f"Success status: {success}")
            if stdout:
                print(f"Stdout (last 1000 chars):\n{stdout[-1000:]}")
            if stderr:
                print(f"Stderr (last 1000 chars):\n{stderr[-1000:]}")
            return False
    
    def _clear_database(self) -> bool:
        """Clear DSQL database by dropping and recreating table."""
        print("=== Clearing DSQL database ===")
        
        commands = [
            "set +e",
            # Install psycopg2 if not available
            "python3 -c 'import psycopg2' 2>/dev/null || pip3 install psycopg2-binary --quiet || dnf install -y python3-psycopg2 >/dev/null 2>&1 || yum install -y python3-psycopg2 >/dev/null 2>&1 || true",
            f"export DSQL_HOST={self.config.dsql_host}",
            "export DSQL_PORT=5432",
            "export DATABASE_NAME=postgres",
            f"export IAM_USERNAME={self.config.iam_username}",
            f"export AWS_REGION={self.config.region}",
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
            "    cur.execute('DROP TABLE IF EXISTS car_entities_schema.business_events CASCADE')",
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
        
        success, stdout, stderr = self.executor.run_command(commands, timeout=60)
        
        if success and 'SUCCESS' in stdout:
            print("✓ Database cleared")
            return True
        else:
            print(f"✗ Database clear failed")
            if stderr:
                print(f"Error: {stderr[:500]}")
            return False
    
    def _run_single_test(self, test_def: TestDefinition) -> bool:
        """Run a single test on EC2 with resource metrics collection."""
        # Start resource metrics collection
        print(f"  Starting resource metrics collection...")
        self.resource_metrics_collector.start_collection()
        
        try:
            # Build test commands
            payload_export = f"export PAYLOAD_SIZE={test_def.payload_size}" if test_def.payload_size != 'default' else "unset PAYLOAD_SIZE"
            
            commands = [
                "set +e",
                "cd /tmp/dsql-load-test-java",
                "if [ ! -f target/dsql-load-test-1.0.0.jar ]; then",
                "  echo 'ERROR: JAR file not found';",
                "  exit 1;",
                "fi",
                f"export DSQL_HOST={self.config.dsql_host}",
                "export DSQL_PORT=5432",
                "export DATABASE_NAME=postgres",
                f"export IAM_USERNAME={self.config.iam_username}",
                f"export AWS_REGION={self.config.region}",
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
                "java -jar target/dsql-load-test-1.0.0.jar 2>&1 | tee /tmp/test-output.log || JAVA_EXIT=$?",
                "echo '=== Java exit code: $JAVA_EXIT ==='",
                "sleep 3",
                # Upload result to S3 (lower threshold for smoke tests)
                f"if [ -f /tmp/results/{test_def.test_id}.json ]; then",
                f"  FILE_SIZE=$(stat -f%z /tmp/results/{test_def.test_id}.json 2>/dev/null || stat -c%s /tmp/results/{test_def.test_id}.json 2>/dev/null || echo 0)",
                f"  if [ $FILE_SIZE -gt 1000 ]; then",  # Lower threshold: 1KB instead of 50KB
                f"    /usr/bin/aws s3 cp /tmp/results/{test_def.test_id}.json s3://{self.config.s3_bucket}/test-results/{test_def.test_id}.json 2>&1 || true",
                f"    echo 'Result uploaded to S3 (size: $FILE_SIZE bytes)'",
                f"  else",
                f"    echo 'Warning: Result file too small ($FILE_SIZE bytes), skipping upload'",
                f"  fi",
                f"fi",
            ]
            
            # Calculate timeout based on test size
            # Base timeout: 120s, add 2s per thread, 1s per iteration
            # Account for: execution time, result writing, S3 upload, and buffer
            timeout = 120 + (test_def.threads * 2) + (test_def.iterations * test_def.count)
            timeout = min(timeout, 1800)  # Cap at 30 minutes for extreme tests
            
            success, stdout, stderr = self.executor.run_command(commands, timeout=timeout)
            
            if not success:
                print(f"  Test execution failed: {stderr[:200] if stderr else 'Unknown error'}")
                return False
            
            # Stop resource metrics collection and get collected data
            print(f"  Stopping resource metrics collection...")
            resource_metrics = self.resource_metrics_collector.stop_collection()
            summary_stats = self.resource_metrics_collector.get_summary_statistics(resource_metrics)
            
            # Download result from S3
            result_path = self.results_dir / f"{test_def.test_id}.json"
            if self.executor.download_result(test_def.test_id, result_path):
                # Merge resource metrics into result JSON
                self._merge_resource_metrics(result_path, resource_metrics, summary_stats)
                print(f"  Resource metrics: {len(resource_metrics)} samples collected")
                return True
            else:
                print(f"  Warning: Result collection failed")
                return False
        except Exception as e:
            # Ensure metrics collection stops even on error
            self.resource_metrics_collector.stop_collection()
            print(f"  Error during test execution: {e}")
            return False
    
    def _upload_test_suite_start_marker(self, total_tests: int):
        """Upload test suite start marker to S3 for monitoring."""
        try:
            from datetime import datetime, timezone
            start_marker = {
                'test_suite_start_time': datetime.now(timezone.utc).isoformat(),
                'total_tests': total_tests,
                'config_path': str(self.config_path.name) if self.config_path else None,
                'results_dir': str(self.results_dir.name) if self.results_dir else None
            }
            
            # Create temporary file
            import tempfile
            with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
                json.dump(start_marker, f, indent=2)
                temp_path = f.name
            
            # Upload to S3
            s3_key = "test-results/.test-suite-start.json"
            if self.executor.upload_file(temp_path, s3_key):
                print(f"Test suite start marker uploaded to S3: {s3_key}")
            
            # Clean up
            Path(temp_path).unlink()
        except Exception as e:
            # Don't fail if marker upload fails
            print(f"Warning: Failed to upload test suite start marker: {e}")
    
    def _merge_resource_metrics(self, result_path: Path, raw_metrics: List[Dict], summary_stats: Dict):
        """Merge resource metrics into test result JSON file."""
        try:
            with open(result_path, 'r') as f:
                result_data = json.load(f)
            
            # Add resource metrics section
            result_data['resource_metrics'] = {
                'summary': summary_stats,
                'raw_samples': raw_metrics[:100] if len(raw_metrics) > 100 else raw_metrics,  # Limit to 100 samples to avoid huge files
                'total_samples': len(raw_metrics),
                'collection_interval_seconds': self.resource_metrics_collector.metrics_interval
            }
            
            # Write back to file
            with open(result_path, 'w') as f:
                json.dump(result_data, f, indent=2)
            
            # Also upload updated result to S3
            self.executor.upload_file(
                str(result_path),
                f"test-results/{result_path.name}"
            )
        except Exception as e:
            # Don't fail the test if metrics merging fails
            print(f"  Warning: Failed to merge resource metrics: {e}")
    
    def run_suite(
        self,
        test_groups: Optional[List[str]] = None,
        resume: bool = False,
        tags: Optional[List[str]] = None,
        stop_instance_after: bool = True
    ) -> dict:
        """Run full test suite or specific groups."""
        print("=" * 80)
        print("DSQL Performance Test Suite")
        print("=" * 80)
        print(f"Results directory: {self.results_dir}")
        print()
        
        try:
            # Ensure EC2 instance is ready
            print("=== Checking EC2 Instance ===")
            if not self.executor.ensure_instance_ready():
                raise RuntimeError("Failed to start EC2 instance or SSM agent not ready")
            print()
            
            # Load test configuration
            print("=== Loading test configuration ===")
            config_loader = TestConfigLoader(str(self.config_path))
            config_loader.load_config()
            tests = config_loader.generate_test_matrix(test_groups)
            
            # Filter by tags if specified
            if tags:
                original_count = len(tests)
                tests = [t for t in tests if any(tag in t.tags for tag in tags)]
                print(f"Filtered by tags {tags}: {len(tests)}/{original_count} tests")
            
            # Filter completed tests if resuming
            if resume:
                original_count = len(tests)
                tests = [t for t in tests if t.test_id not in self.completed]
                skipped = original_count - len(tests)
                if skipped > 0:
                    print(f"Skipping {skipped} already completed tests")
            
            total_tests = len(tests)
            print(f"Total tests to run: {total_tests}")
            print()
            
            if total_tests == 0:
                print("No tests to run")
                return {'total': 0, 'completed': 0, 'failed': 0, 'results_dir': str(self.results_dir)}
            
            # Prepare environment (one-time setup)
            if not self._prepare_environment():
                raise RuntimeError("Failed to prepare EC2 environment")
            print()
            
            # Clear database
            if not self._clear_database():
                print("Warning: Failed to clear database, continuing anyway...")
            print()
            
            # Upload test suite start marker to S3
            self._upload_test_suite_start_marker(total_tests)
            
            # Run tests
            completed_count = 0
            failed_count = 0
            
            for i, test_def in enumerate(tests, 1):
                print(f"[{i}/{total_tests}] Running: {test_def.test_id}")
                print(f"  Scenario: {test_def.scenario}, Threads: {test_def.threads}, "
                      f"Iterations: {test_def.iterations}, Count: {test_def.count}")
                
                try:
                    success = self._run_single_test(test_def)
                    
                    if success:
                        self.completed.add(test_def.test_id)
                        self._save_completed()
                        completed_count += 1
                        print(f"  ✓ Test completed")
                    else:
                        failed_count += 1
                        print(f"  ✗ Test failed")
                except KeyboardInterrupt:
                    print("\n  ⚠ Test execution interrupted by user")
                    failed_count += 1
                    raise  # Re-raise to trigger cleanup
                except Exception as e:
                    print(f"  ✗ Error: {e}")
                    failed_count += 1
                
                print()
            
            # Summary
            print("=" * 80)
            print("Test Suite Complete")
            print("=" * 80)
            print(f"Results saved to: {self.results_dir}")
            print(f"Completed: {completed_count}/{total_tests}")
            print(f"Failed: {failed_count}/{total_tests}")
            print()
            
            return {
                'total': total_tests,
                'completed': completed_count,
                'failed': failed_count,
                'results_dir': str(self.results_dir)
            }
        except KeyboardInterrupt:
            print("\n⚠ Test execution interrupted by user")
            raise  # Re-raise after cleanup
        finally:
            # Always stop instance after tests (unless explicitly disabled)
            if stop_instance_after:
                print("=== Stopping EC2 Instance ===")
                try:
                    self.executor.stop_instance()
                except Exception as e:
                    print(f"Warning: Failed to stop instance: {e}")
                print()


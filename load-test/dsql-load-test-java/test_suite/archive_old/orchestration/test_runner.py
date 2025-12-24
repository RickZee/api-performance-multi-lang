"""
Main test orchestrator.
"""

import os
import sys
from pathlib import Path
from typing import Optional, List, Callable, Dict
from datetime import datetime

from test_suite.config.loader import TestConfigLoader, TestDefinition
from test_suite.config.aws_config import AWSConfig as ConfigLoader
from test_suite.infrastructure.ec2_manager import EC2Manager
from test_suite.infrastructure.ssm_executor import SSMExecutor
from test_suite.infrastructure.s3_manager import S3Manager
from test_suite.archive.manager import ArchiveManager, ArchiveError
from test_suite.orchestration.test_executor import TestExecutor, TestExecutionError
from test_suite.orchestration.result_collector import ResultCollector
from test_suite.utils.manifest import ManifestManager
from test_suite.infrastructure.cloudwatch_metrics import CloudWatchMetricsCollector
from datetime import datetime


class TestRunner:
    """Orchestrate test suite execution."""
    
    def __init__(
        self,
        config_path: str,
        results_dir: str,
        terraform_dir: Optional[str] = None,
        max_pool_size: int = 2000,
        connection_rate_limit: int = 100
    ):
        self.config_path = Path(config_path)
        self.results_dir = Path(results_dir)
        self.results_dir.mkdir(parents=True, exist_ok=True)
        
        # Load configuration
        self.config_loader = TestConfigLoader(str(self.config_path))
        self.aws_config = ConfigLoader(region=os.getenv('AWS_REGION'))
        
        # Get infrastructure config
        infra_config = self.aws_config.get_all_config()
        is_valid, error = self.aws_config.validate_config()
        if not is_valid:
            raise RuntimeError(f"Configuration validation failed: {error}")
        
        # Initialize infrastructure managers
        self.ec2_manager = EC2Manager(
            infra_config['test_runner_instance_id'],
            infra_config['aws_region']
        )
        self.ssm_executor = SSMExecutor(
            infra_config['test_runner_instance_id'],
            infra_config['aws_region']
        )
        self.cloudwatch_collector = CloudWatchMetricsCollector(
            infra_config['test_runner_instance_id'],
            infra_config['aws_region']
        )
        # Get S3 bucket (try multiple sources)
        s3_bucket = infra_config.get('s3_bucket') or infra_config.get('s3_bucket_name')
        if not s3_bucket:
            try:
                from test_suite.config.terraform import TerraformConfig
                tf_config = TerraformConfig()
                s3_bucket = tf_config.get_output('s3_bucket_name')
            except Exception:
                pass
        
        self.s3_manager = S3Manager(
            s3_bucket,
            infra_config['aws_region']
        ) if s3_bucket else None
        
        # Initialize test executor
        script_dir = Path(__file__).parent.parent.parent
        self.test_executor = TestExecutor(
            self.ssm_executor,
            self.s3_manager,
            str(script_dir),
            infra_config['dsql_host'],
            infra_config['iam_username'],
            infra_config['aws_region'],
            max_pool_size=max_pool_size,
            connection_rate_limit=connection_rate_limit
        )
        
        # Initialize result collector
        self.result_collector = ResultCollector(self.ssm_executor, self.s3_manager)
        
        # Initialize manifest
        manifest_path = self.results_dir / 'manifest.json'
        self.manifest = ManifestManager(str(manifest_path))
        # Only load existing manifest if resuming, otherwise start fresh
        # We'll check for resume flag later and load then if needed
        
        # Progress callback
        self.progress_callback: Optional[Callable[[str, int, int], None]] = None
    
    def set_progress_callback(self, callback: Callable[[str, int, int], None]) -> None:
        """Set callback for progress updates."""
        self.progress_callback = callback
    
    def run_suite(
        self,
        test_groups: Optional[List[str]] = None,
        resume: bool = False,
        tags: Optional[List[str]] = None,
        retry_failed: bool = False
    ) -> dict:
        """Run full test suite or specific groups."""
        print("=" * 80)
        print("DSQL Performance Test Suite")
        print("=" * 80)
        print(f"Results directory: {self.results_dir}")
        print()
        
        # Ensure EC2 instance is running
        print("=== Checking EC2 Instance Status ===")
        if not self.ec2_manager.ensure_running():
            raise RuntimeError("Failed to start EC2 instance or SSM agent not ready")
        print()
        
        # Prepare archive
        print("=== Creating deployment package ===")
        try:
            archive_path = self.test_executor.prepare_archive()
            print(f"Archive prepared: {archive_path}")
        except TestExecutionError as e:
            raise RuntimeError(f"Failed to prepare archive: {e}") from e
        print()
        
        # Clear DSQL database
        print("=== Clearing DSQL database ===")
        if not self.test_executor.clear_database():
            print("Warning: Failed to clear database, continuing anyway...")
        print()
        
        # Prepare EC2 environment once (download, extract, build)
        # This is done once for all tests to avoid rebuilding for each test
        print("=== Preparing EC2 environment (one-time setup) ===")
        if not self.test_executor.prepare_environment():
            raise RuntimeError("Failed to prepare EC2 environment")
        print()
        
        # Generate test matrix
        print("=== Loading test configuration ===")
        self.config_loader.load_config()
        tests = self.config_loader.generate_test_matrix(test_groups)
        
        # Filter by tags if specified
        if tags:
            original_count = len(tests)
            tests = [t for t in tests if any(tag in t.tags for tag in tags)]
            filtered_count = len(tests)
            print(f"Filtered by tags {tags}: {filtered_count}/{original_count} tests")
        
        total_tests = len(tests)
        print(f"Total tests to run: {total_tests}")
        print()
        
        # Load existing manifest only if resuming or retrying
        if resume or retry_failed:
            self.manifest.load()
        else:
            # Start fresh manifest for new run
            self.manifest.manifest = {
                'start_time': datetime.utcnow().isoformat() + 'Z',
                'total_expected': 0,
                'test_groups': [],
                'tests': []
            }
        
        # Filter tests based on resume or retry_failed BEFORE initializing manifest
        original_total = total_tests
        if retry_failed:
            # Get failed tests from manifest
            failed_tests = set(self.manifest.get_failed_tests())
            tests = [t for t in tests if t.test_id in failed_tests]
            skipped = total_tests - len(tests)
            if skipped > 0:
                print(f"Retrying {len(tests)} failed tests (skipping {skipped} passed/completed tests)")
                print()
            if len(tests) == 0:
                print("No failed tests to retry")
                return {
                    'total': 0,
                    'completed': 0,
                    'failed': 0,
                    'results_dir': str(self.results_dir)
                }
        elif resume:
            completed = set(self.manifest.get_completed_tests())
            tests = [t for t in tests if t.test_id not in completed]
            skipped = total_tests - len(tests)
            if skipped > 0:
                print(f"Skipping {skipped} already completed tests")
                print()
        
        # Update total after filtering
        total_tests = len(tests)
        
        # Store total expected and test groups in manifest (after filtering)
        self.manifest.set_total_expected(total_tests)
        if test_groups:
            self.manifest.set_test_groups(test_groups)
        
        # Initialize all planned tests as "pending" in manifest before execution
        print("=== Initializing test manifest ===")
        for test_def in tests:
            self.manifest.add_test(
                test_def.test_id,
                test_def.scenario,
                test_def.threads,
                test_def.iterations,
                test_def.count,
                test_def.payload_size,
                status="pending"
            )
        print(f"Initialized {total_tests} tests in manifest")
        print()
        
        # Run tests
        completed_count = 0
        failed_count = 0
        
        for i, test_def in enumerate(tests, 1):
            if self.progress_callback:
                self.progress_callback(test_def.test_id, i, total_tests)
            
            print(f"[{i}/{total_tests}] Running: {test_def.test_id}")
            print(f"  Scenario: {test_def.scenario}, Threads: {test_def.threads}, "
                  f"Iterations: {test_def.iterations}, Count: {test_def.count}, "
                  f"Payload: {test_def.payload_size}")
            
            # Warn for extreme scaling
            if test_def.threads >= 500 or test_def.count >= 500:
                print("  ⚠️  Extreme scaling test detected")
            
            # Update status to "running" at start of execution
            self.manifest.update_status(test_def.test_id, "running")
            
            try:
                # Execute test (returns success, start_time, end_time)
                success, test_start_time, test_end_time = self.test_executor.execute_test(test_def)
                
                if success:
                    # Collect result
                    result_collected = self.result_collector.collect_result(
                        test_def.test_id,
                        self.results_dir
                    )
                    
                    # Collect CloudWatch metrics and add to result file
                    if result_collected:
                        try:
                            cloudwatch_data = self.cloudwatch_collector.collect_test_metrics(
                                test_start_time, test_end_time
                            )
                            self._add_cloudwatch_metrics_to_result(test_def.test_id, cloudwatch_data)
                        except Exception as e:
                            print(f"  Warning: Failed to collect CloudWatch metrics: {e}")
                    
                    if result_collected:
                        print(f"  ✅ Test completed and result collected")
                        completed_count += 1
                    else:
                        print(f"  ⚠️  Test completed but result collection failed")
                        failed_count += 1
                else:
                    print(f"  ❌ Test execution failed")
                    failed_count += 1
                
                # Update manifest status
                final_status = "completed" if success else "failed"
                self.manifest.update_status(test_def.test_id, final_status)
                
            except Exception as e:
                print(f"  ❌ Error: {e}")
                failed_count += 1
                self.manifest.update_status(test_def.test_id, "error")
            
            print()
        
        # Finalize manifest
        self.manifest.set_end_time()
        
        # Summary
        print("=" * 80)
        print("Test Suite Complete")
        print("=" * 80)
        print(f"Results saved to: {self.results_dir}")
        print(f"Completed: {completed_count}/{total_tests}")
        print(f"Failed: {failed_count}/{total_tests}")
        print()
        print("Next steps:")
        print(f"  1. Run analysis: python3 analyze-results.py {self.results_dir}")
        print(f"  2. Generate report: python3 generate-report.py {self.results_dir}")
        print()
        
        return {
            'total': total_tests,
            'completed': completed_count,
            'failed': failed_count,
            'results_dir': str(self.results_dir)
        }
    
    def _add_cloudwatch_metrics_to_result(self, test_id: str, cloudwatch_data: Dict) -> None:
        """Add CloudWatch metrics to the result JSON file."""
        result_file = self.results_dir / f"{test_id}.json"
        if not result_file.exists():
            return
        
        try:
            import json
            with open(result_file, 'r') as f:
                result_data = json.load(f)
            
            # Add CloudWatch metrics
            if 'cloudwatch_metrics' not in result_data:
                result_data['cloudwatch_metrics'] = {}
            
            result_data['cloudwatch_metrics'] = cloudwatch_data
            
            # Write back
            with open(result_file, 'w') as f:
                json.dump(result_data, f, indent=2)
        except Exception as e:
            print(f"  Warning: Failed to add CloudWatch metrics to result: {e}")


"""
S3-based progress monitoring - inexpensive alternative to local file monitoring.
"""

import time
import json
import os
from pathlib import Path
from typing import Optional, Set
from dataclasses import dataclass
from datetime import datetime, timezone
from botocore.exceptions import ClientError, BotoCoreError


@dataclass
class MonitorConfig:
    """Configuration for S3 and EC2 monitoring."""
    s3_bucket: str
    region: str = "us-east-1"
    instance_id: Optional[str] = None  # Optional: enables EC2 process checking
    
    @classmethod
    def from_env(cls) -> "MonitorConfig":
        """Load config from environment - only requires S3_BUCKET."""
        s3_bucket = os.getenv("S3_BUCKET")
        region = os.getenv("AWS_REGION", "us-east-1")
        
        # Try to load from Terraform if not set
        if not s3_bucket:
            try:
                import subprocess
                from pathlib import Path
                
                # Try to find terraform directory
                # From test_suite/s3_monitor.py -> load-test/dsql-load-test-java -> api-performance-multi-lang -> terraform
                current_dir = Path.cwd()
                file_path = Path(__file__).resolve()
                possible_terraform_dirs = [
                    file_path.parent.parent.parent / 'terraform',  # From test_suite -> terraform (repo root)
                    current_dir.parent.parent / 'terraform',  # From load-test/dsql-load-test-java -> terraform (repo root)
                    current_dir.parent / 'terraform',  # From load-test -> terraform
                    current_dir / 'terraform',  # If already in root
                ]
                
                for terraform_dir in possible_terraform_dirs:
                    terraform_dir = terraform_dir.resolve()
                    # Check if directory exists and has terraform files
                    if terraform_dir.exists() and terraform_dir.is_dir():
                        try:
                            result = subprocess.run(
                                ['terraform', 'output', '-raw', 's3_bucket_name'],
                                cwd=str(terraform_dir),
                                capture_output=True,
                                text=True,
                                timeout=10
                            )
                            if result.returncode == 0:
                                s3_bucket = result.stdout.strip()
                                if s3_bucket:
                                    os.environ['S3_BUCKET'] = s3_bucket
                                    print(f"Loaded S3_BUCKET from Terraform: {s3_bucket}")
                                    break
                        except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
                            continue
            except Exception:
                pass
        
        if not s3_bucket:
            raise ValueError(
                "Missing required environment variable: S3_BUCKET\n"
                "Please set: export S3_BUCKET=your-bucket-name\n"
                "Or ensure Terraform outputs are available: cd terraform && terraform output"
            )
        
        # Try to load instance ID for EC2 checking (optional)
        instance_id = os.getenv("TEST_RUNNER_INSTANCE_ID")
        if not instance_id:
            try:
                import subprocess
                for terraform_dir in possible_terraform_dirs:
                    terraform_dir = terraform_dir.resolve()
                    if terraform_dir.exists() and terraform_dir.is_dir():
                        try:
                            result = subprocess.run(
                                ['terraform', 'output', '-raw', 'dsql_test_runner_instance_id'],
                                cwd=str(terraform_dir),
                                capture_output=True,
                                text=True,
                                timeout=10
                            )
                            if result.returncode == 0:
                                instance_id = result.stdout.strip()
                                if instance_id:
                                    os.environ['TEST_RUNNER_INSTANCE_ID'] = instance_id
                                    break
                        except (subprocess.TimeoutExpired, FileNotFoundError, Exception):
                            continue
            except Exception:
                pass
        
        return cls(s3_bucket=s3_bucket, region=region, instance_id=instance_id)


def get_s3_client(config: MonitorConfig):
    """Get configured S3 client."""
    import boto3
    from botocore.config import Config as BotoConfig
    
    boto_config = BotoConfig(
        read_timeout=30,
        connect_timeout=10,
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )
    return boto3.client('s3', region_name=config.region, config=boto_config)


def get_ssm_client(config: MonitorConfig):
    """Get configured SSM client."""
    import boto3
    from botocore.config import Config as BotoConfig
    
    boto_config = BotoConfig(
        read_timeout=30,
        connect_timeout=10,
        retries={'max_attempts': 3, 'mode': 'adaptive'}
    )
    return boto3.client('ssm', region_name=config.region, config=boto_config)


def check_running_tests_on_ec2(config: MonitorConfig) -> dict:
    """
    Check EC2 instance for currently running test processes and recent results.
    
    Returns:
        Dict with:
        - running_processes: int (number of Java test processes)
        - recent_results: list of result file info
        - error: str if error occurred
    """
    if not config.instance_id:
        return {'running_processes': 0, 'recent_results': [], 'enabled': False}
    
    try:
        ssm = get_ssm_client(config)
        
        # Send command to check processes and results
        result = ssm.send_command(
            InstanceIds=[config.instance_id],
            DocumentName='AWS-RunShellScript',
            Parameters={
                'commands': [
                    # Check for running Java test processes
                    'ps aux | grep -E "(dsql-load-test|java.*dsql)" | grep -v grep | wc -l',
                    # List recent result files
                    'ls -lth /tmp/results/*.json 2>/dev/null | head -5 | awk \'{print $9, $6, $7, $8}\' || echo "No results"'
                ]
            },
            TimeoutSeconds=30
        )
        
        command_id = result['Command']['CommandId']
        
        # Wait a bit for command to execute
        import time
        time.sleep(2)
        
        # Get command output
        try:
            output = ssm.get_command_invocation(
                CommandId=command_id,
                InstanceId=config.instance_id
            )
            
            if output['Status'] == 'Success':
                stdout = output.get('StandardOutputContent', '').strip()
                lines = stdout.split('\n')
                
                # Parse process count (first line)
                process_count = 0
                if lines:
                    try:
                        process_count = int(lines[0].strip())
                    except (ValueError, IndexError):
                        pass
                
                # Parse result files (remaining lines)
                recent_results = []
                for line in lines[1:]:
                    if line and 'No results' not in line and line.strip():
                        parts = line.strip().split()
                        if len(parts) >= 4:
                            filepath = parts[0]
                            # Extract test ID from filename
                            import re
                            match = re.search(r'test-\d+[^/]*', filepath)
                            if match:
                                test_id = match.group(0)
                                recent_results.append({
                                    'test_id': test_id,
                                    'filepath': filepath,
                                    'time': ' '.join(parts[1:4]) if len(parts) >= 4 else ''
                                })
                
                return {
                    'running_processes': process_count,
                    'recent_results': recent_results[:3],  # Limit to 3 most recent
                    'enabled': True
                }
            else:
                return {
                    'running_processes': 0,
                    'recent_results': [],
                    'enabled': True,
                    'error': f"SSM command status: {output['Status']}"
                }
        except Exception as e:
            # Command might still be running, return partial info
            return {
                'running_processes': 0,
                'recent_results': [],
                'enabled': True,
                'error': 'Command still executing'
            }
            
    except ClientError as e:
        return {
            'running_processes': 0,
            'recent_results': [],
            'enabled': True,
            'error': f"SSM error: {e.response.get('Error', {}).get('Code', 'Unknown')}"
        }
    except Exception as e:
        return {
            'running_processes': 0,
            'recent_results': [],
            'enabled': True,
            'error': str(e)
        }


def get_test_suite_start_marker(config: MonitorConfig) -> Optional[dict]:
    """
    Get test suite start marker from S3.
    
    Args:
        config: Test configuration with S3 bucket info
    
    Returns:
        Dict with start_time and total_tests, or None if not found
    """
    s3 = get_s3_client(config)
    s3_key = "test-results/.test-suite-start.json"
    
    try:
        response = s3.get_object(Bucket=config.s3_bucket, Key=s3_key)
        data = json.loads(response['Body'].read().decode('utf-8'))
        return data
    except ClientError:
        # File doesn't exist yet
        return None
    except (json.JSONDecodeError, Exception):
        return None


def get_completed_tests_from_s3(config: MonitorConfig, prefix: str = "test-results/") -> Set[str]:
    """
    Get set of completed test IDs from S3.
    
    Args:
        config: Test configuration with S3 bucket info
        prefix: S3 prefix for test results (default: "test-results/")
    
    Returns:
        Set of test IDs (e.g., {"test-001-...", "test-002-..."})
    """
    s3 = get_s3_client(config)
    completed = set()
    
    try:
        # List all objects with the test-results prefix
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=config.s3_bucket, Prefix=prefix)
        
        for page in pages:
            if 'Contents' not in page:
                continue
            
            for obj in page['Contents']:
                key = obj['Key']
                # Extract test ID from key: test-results/test-001-... -> test-001-...
                if key.endswith('.json'):
                    # Remove prefix and .json extension
                    test_id = key[len(prefix):].replace('.json', '')
                    if test_id.startswith('test-'):
                        completed.add(test_id)
    
    except ClientError as e:
        error_code = e.response.get('Error', {}).get('Code', '')
        if error_code == 'NoSuchBucket':
            print(f"Error: S3 bucket not found: {config.s3_bucket}")
        elif error_code == 'AccessDenied':
            print(f"Error: Access denied to S3 bucket: {config.s3_bucket}")
        else:
            print(f"Error listing S3 objects: {e}")
    except BotoCoreError as e:
        print(f"Error connecting to S3: {e}")
    except Exception as e:
        print(f"Unexpected error: {e}")
    
    return completed


def get_test_metrics_from_s3(config: MonitorConfig, test_id: str, prefix: str = "test-results/") -> Optional[dict]:
    """
    Download and parse test result JSON from S3 to extract key metrics.
    
    Args:
        config: Test configuration with S3 bucket info
        test_id: Test ID to fetch
        prefix: S3 prefix for test results (default: "test-results/")
    
    Returns:
        Dict with key metrics, or None if failed
    """
    s3 = get_s3_client(config)
    s3_key = f"{prefix}{test_id}.json"
    
    try:
        # Download JSON from S3
        response = s3.get_object(Bucket=config.s3_bucket, Key=s3_key)
        data = json.loads(response['Body'].read().decode('utf-8'))
        
        if not data or 'test_id' not in data:
            return None
        
        # Extract key metrics
        metrics = {
            'test_id': test_id,
            'timestamp': data.get('timestamp', ''),
        }
        
        # Get results from first available scenario
        results = data.get('results', {})
        scenario_result = results.get('scenario_1') or results.get('scenario_2')
        
        if scenario_result:
            metrics['throughput'] = scenario_result.get('throughput_inserts_per_sec', 0)
            metrics['total_success'] = scenario_result.get('total_success', 0)
            metrics['total_errors'] = scenario_result.get('total_errors', 0)
            metrics['duration_ms'] = scenario_result.get('duration_ms', 0)
            
            # Latency stats
            latency_stats = scenario_result.get('latency_stats', {})
            metrics['p95_latency_ms'] = latency_stats.get('p95_latency_ms', 0)
            metrics['p99_latency_ms'] = latency_stats.get('p99_latency_ms', 0)
            metrics['avg_latency_ms'] = latency_stats.get('avg_latency_ms', 0)
            
            # Error rate
            total_ops = metrics['total_success'] + metrics['total_errors']
            metrics['error_rate_pct'] = (metrics['total_errors'] / total_ops * 100) if total_ops > 0 else 0
        
        # Pool metrics
        pool_metrics = data.get('pool_metrics', {})
        if pool_metrics:
            metrics['active_connections'] = pool_metrics.get('active_connections', 0)
            metrics['max_pool_size'] = pool_metrics.get('max_pool_size', 0)
            pool_utilization = (metrics['active_connections'] / metrics['max_pool_size'] * 100) if metrics.get('max_pool_size', 0) > 0 else 0
            metrics['pool_utilization_pct'] = pool_utilization
        
        # Configuration
        config_data = data.get('configuration', {})
        if config_data:
            metrics['threads'] = config_data.get('threads', 0)
            metrics['scenario'] = config_data.get('scenario', 0)
        
        # Resource metrics (if available)
        resource_metrics = data.get('resource_metrics', {})
        if resource_metrics and 'summary' in resource_metrics:
            metrics['resource_metrics'] = resource_metrics['summary']
        
        return metrics
        
    except ClientError as e:
        # File might not exist yet
        return None
    except (json.JSONDecodeError, KeyError, Exception) as e:
        # Invalid JSON or missing fields
        return None


def get_aggregate_metrics(config: MonitorConfig, test_ids: Set[str], max_age_hours: int = 24) -> dict:
    """
    Get aggregate metrics from all completed tests.
    
    Args:
        config: Test configuration
        test_ids: Set of completed test IDs
        max_age_hours: Only consider tests from the last N hours (default: 24)
    
    Returns:
        Dict with aggregate metrics including resource utilization
    """
    if not test_ids:
        return {}
    
    all_metrics = []
    now = datetime.now(timezone.utc)
    
    for test_id in test_ids:
        metrics = get_test_metrics_from_s3(config, test_id)
        if metrics:
            # Filter by timestamp - only include recent tests
            timestamp_str = metrics.get('timestamp', '')
            if timestamp_str:
                try:
                    # Parse timestamp
                    if 'T' in timestamp_str:
                        # Parse ISO format with timezone
                        if timestamp_str.endswith('Z'):
                            test_dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        else:
                            test_dt = datetime.fromisoformat(timestamp_str)
                        
                        # Ensure both are timezone-aware for comparison
                        if test_dt.tzinfo is None:
                            test_dt = test_dt.replace(tzinfo=timezone.utc)
                        
                        # Check if test is within max_age_hours
                        age_hours = (now - test_dt).total_seconds() / 3600
                        if age_hours > max_age_hours:
                            continue  # Skip old tests
                except Exception:
                    pass  # If timestamp parsing fails, include the test anyway
            
            all_metrics.append(metrics)
    
    if not all_metrics:
        return {}
    
    # Calculate aggregates
    total_success = sum(m.get('total_success', 0) for m in all_metrics)
    total_errors = sum(m.get('total_errors', 0) for m in all_metrics)
    total_ops = total_success + total_errors
    
    throughputs = [m.get('throughput', 0) for m in all_metrics if m.get('throughput', 0) > 0]
    p95_latencies = [m.get('p95_latency_ms', 0) for m in all_metrics if m.get('p95_latency_ms', 0) > 0]
    p99_latencies = [m.get('p99_latency_ms', 0) for m in all_metrics if m.get('p99_latency_ms', 0) > 0]
    
    pool_utilizations = [m.get('pool_utilization_pct', 0) for m in all_metrics if m.get('pool_utilization_pct', 0) > 0]
    
    # Get earliest timestamp from recent tests only (test suite start time)
    timestamps = []
    for m in all_metrics:
        ts = m.get('timestamp', '')
        if ts:
            timestamps.append(ts)
    earliest_timestamp = min(timestamps) if timestamps else None
    
    # Aggregate resource metrics
    resource_summaries = [m.get('resource_metrics', {}) for m in all_metrics if m.get('resource_metrics')]
    resource_agg = {}
    
    if resource_summaries:
        # CPU metrics
        cpu_utils = [r.get('cpu', {}).get('avg_utilization_percent', 0) for r in resource_summaries if r.get('cpu', {}).get('avg_utilization_percent', 0) > 0]
        cpu_max_utils = [r.get('cpu', {}).get('max_utilization_percent', 0) for r in resource_summaries if r.get('cpu', {}).get('max_utilization_percent', 0) > 0]
        
        # Memory metrics
        mem_utils = [r.get('memory', {}).get('avg_used_percent', 0) for r in resource_summaries if r.get('memory', {}).get('avg_used_percent', 0) > 0]
        mem_max_utils = [r.get('memory', {}).get('max_used_percent', 0) for r in resource_summaries if r.get('memory', {}).get('max_used_percent', 0) > 0]
        
        # Disk I/O metrics
        disk_read_rates = [r.get('disk', {}).get('avg_read_ops_per_sec', 0) for r in resource_summaries if r.get('disk', {}).get('avg_read_ops_per_sec', 0) > 0]
        disk_write_rates = [r.get('disk', {}).get('avg_write_ops_per_sec', 0) for r in resource_summaries if r.get('disk', {}).get('avg_write_ops_per_sec', 0) > 0]
        
        # Network I/O metrics
        net_rx_rates = [r.get('network', {}).get('avg_rx_bytes_per_sec', 0) for r in resource_summaries if r.get('network', {}).get('avg_rx_bytes_per_sec', 0) > 0]
        net_tx_rates = [r.get('network', {}).get('avg_tx_bytes_per_sec', 0) for r in resource_summaries if r.get('network', {}).get('avg_tx_bytes_per_sec', 0) > 0]
        
        # Java process metrics
        java_cpu = [r.get('java_process', {}).get('avg_cpu_percent', 0) for r in resource_summaries if r.get('java_process', {}).get('avg_cpu_percent', 0) > 0]
        java_mem = [r.get('java_process', {}).get('avg_mem_percent', 0) for r in resource_summaries if r.get('java_process', {}).get('avg_mem_percent', 0) > 0]
        
        resource_agg = {
            'cpu_avg_pct': sum(cpu_utils) / len(cpu_utils) if cpu_utils else 0,
            'cpu_max_pct': max(cpu_max_utils) if cpu_max_utils else 0,
            'memory_avg_pct': sum(mem_utils) / len(mem_utils) if mem_utils else 0,
            'memory_max_pct': max(mem_max_utils) if mem_max_utils else 0,
            'disk_read_ops_sec': sum(disk_read_rates) / len(disk_read_rates) if disk_read_rates else 0,
            'disk_write_ops_sec': sum(disk_write_rates) / len(disk_write_rates) if disk_write_rates else 0,
            'network_rx_mbps': (sum(net_rx_rates) / len(net_rx_rates) / 1024 / 1024) if net_rx_rates else 0,
            'network_tx_mbps': (sum(net_tx_rates) / len(net_tx_rates) / 1024 / 1024) if net_tx_rates else 0,
            'java_cpu_avg_pct': sum(java_cpu) / len(java_cpu) if java_cpu else 0,
            'java_mem_avg_pct': sum(java_mem) / len(java_mem) if java_mem else 0,
        }
    
    result = {
        'total_tests': len(all_metrics),
        'total_success': total_success,
        'total_errors': total_errors,
        'error_rate_pct': (total_errors / total_ops * 100) if total_ops > 0 else 0,
        'avg_throughput': sum(throughputs) / len(throughputs) if throughputs else 0,
        'max_throughput': max(throughputs) if throughputs else 0,
        'avg_p95_latency_ms': sum(p95_latencies) / len(p95_latencies) if p95_latencies else 0,
        'max_p95_latency_ms': max(p95_latencies) if p95_latencies else 0,
        'avg_p99_latency_ms': sum(p99_latencies) / len(p99_latencies) if p99_latencies else 0,
        'max_p99_latency_ms': max(p99_latencies) if p99_latencies else 0,
        'avg_pool_utilization_pct': sum(pool_utilizations) / len(pool_utilizations) if pool_utilizations else 0,
        'test_suite_start_time': earliest_timestamp,
    }
    result.update(resource_agg)
    return result


def detect_config_from_recent_tests(config: MonitorConfig, max_age_hours: int = 1) -> Optional[Path]:
    """
    Detect which test config was used by matching recent test IDs in S3 against available configs.
    
    Args:
        config: Monitor configuration with S3 bucket info
        max_age_hours: Only consider tests from the last N hours (default: 1)
    
    Returns:
        Path to the detected config file, or None if cannot determine
    """
    # Get recent test IDs from S3
    all_completed = get_completed_tests_from_s3(config)
    if not all_completed:
        return None
    
    # Filter to recent tests only
    recent_test_ids = set()
    now = datetime.now(timezone.utc)
    for test_id in all_completed:
        metrics = get_test_metrics_from_s3(config, test_id)
        if metrics:
            timestamp_str = metrics.get('timestamp', '')
            if timestamp_str:
                try:
                    if 'T' in timestamp_str:
                        if timestamp_str.endswith('Z'):
                            test_dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        else:
                            test_dt = datetime.fromisoformat(timestamp_str)
                        if test_dt.tzinfo is None:
                            test_dt = test_dt.replace(tzinfo=timezone.utc)
                        age_hours = (now - test_dt).total_seconds() / 3600
                        if age_hours <= max_age_hours:
                            recent_test_ids.add(test_id)
                except Exception:
                    pass
    
    if not recent_test_ids:
        return None
    
    # Try to find config files in the project directory
    script_dir = Path(__file__).parent.parent
    possible_configs = [
        script_dir / 'test-config-smoke.json',
        script_dir / 'test-config-max-throughput-minimal.json',
        script_dir / 'test-config-max-throughput.json',
        script_dir / 'test-config.json',
    ]
    
    # Try each config and see which one matches the recent test IDs
    best_match = None
    best_match_count = 0
    
    for config_path in possible_configs:
        if not config_path.exists():
            continue
        
        try:
            from test_suite.runner import TestConfigLoader
            loader = TestConfigLoader(str(config_path))
            loader.load_config()
            all_tests = loader.generate_test_matrix()
            expected_test_ids = {t.test_id for t in all_tests}
            
            # Count how many recent test IDs match this config
            matching = recent_test_ids & expected_test_ids
            match_count = len(matching)
            
            # If all recent tests match this config, it's a perfect match
            if match_count == len(recent_test_ids) and match_count > 0:
                return config_path
            
            # Track the best match
            if match_count > best_match_count:
                best_match = config_path
                best_match_count = match_count
        except Exception:
            continue
    
    # Return best match if we found one with at least some matches
    if best_match_count > 0:
        return best_match
    
    return None


def get_total_tests_from_config(config_path: Optional[Path] = None) -> Optional[int]:
    """
    Get total number of tests from test-config.json.
    
    Args:
        config_path: Path to test-config.json (if None, tries to find it)
    
    Returns:
        Total number of tests, or None if cannot determine
    """
    if config_path is None:
        # Try to find test-config.json in common locations
        possible_paths = [
            Path('test-config.json'),
            Path(__file__).parent.parent / 'test-config.json',
        ]
        for path in possible_paths:
            if path.exists():
                config_path = path
                break
        
        if config_path is None:
            return None
    
    try:
        from test_suite.runner import TestConfigLoader
        loader = TestConfigLoader(str(config_path))
        loader.load_config()
        all_tests = loader.generate_test_matrix()
        return len(all_tests)
    except Exception:
        return None


def monitor_s3_progress(
    config: MonitorConfig,
    total_tests: Optional[int] = None,
    interval: int = 10,
    config_path: Optional[Path] = None
):
    """
    Monitor test progress by polling S3 bucket directly.
    
    Args:
        config: Test configuration with S3 bucket info
        total_tests: Total number of tests (if None, will try to infer from config)
        interval: Check interval in seconds (default: 10)
        config_path: Path to test-config.json (for determining total tests).
                    If None, will try to auto-detect from recent test results.
    """
    # Auto-detect config from recent tests if not provided
    if config_path is None:
        detected_config = detect_config_from_recent_tests(config, max_age_hours=1)
        if detected_config:
            config_path = detected_config
            print(f"Auto-detected config from recent tests: {config_path.name}")
    
    # Generate expected test IDs from config if available
    expected_test_ids = set()
    if config_path and config_path.exists():
        try:
            from test_suite.runner import TestConfigLoader
            loader = TestConfigLoader(str(config_path))
            loader.load_config()
            all_tests = loader.generate_test_matrix()
            expected_test_ids = {t.test_id for t in all_tests}
            if total_tests is None:
                total_tests = len(all_tests)
        except Exception:
            pass
    
    # Determine total tests if not provided
    if total_tests is None:
        total_tests = get_total_tests_from_config(config_path)
    
    if total_tests is None:
        print("Warning: Could not determine total tests, will show completed count only")
    
    # Clear screen and show header
    os.system('clear' if os.name != 'nt' else 'cls')
    
    print("=" * 80)
    print("S3-Based Test Progress Monitoring")
    print("=" * 80)
    print(f"S3 Bucket: {config.s3_bucket}")
    print(f"Region: {config.region}")
    if config.instance_id:
        print(f"EC2 Instance: {config.instance_id} (real-time process checking enabled)")
    else:
        print("EC2 Instance: Not configured (S3-only monitoring)")
    if total_tests:
        print(f"Total Tests: {total_tests}")
    if expected_test_ids:
        print(f"Monitoring tests from config: {config_path.name if config_path else 'N/A'}")
    print(f"Check Interval: {interval} seconds")
    print()
    
    start_time = time.time()
    last_count = 0
    last_metrics_display = 0
    metrics_display_interval = 30  # Show metrics every 30 seconds
    use_clear_screen = os.getenv('CLEAR_SCREEN', 'true').lower() == 'true'
    test_suite_start_timestamp = None  # Will be set from start marker or first completed test
    
    # Try to get start time from S3 start marker first
    start_marker = get_test_suite_start_marker(config)
    if start_marker and start_marker.get('test_suite_start_time'):
        test_suite_start_timestamp = start_marker['test_suite_start_time']
        # Override total_tests if provided in marker
        if start_marker.get('total_tests') and total_tests is None:
            total_tests = start_marker['total_tests']
    
    try:
        while True:
            # Get completed tests from S3
            all_completed_set = get_completed_tests_from_s3(config)
            
            # Filter to only tests from current config if we have expected test IDs
            if expected_test_ids:
                completed_set = all_completed_set & expected_test_ids
            else:
                # If no config, use time-based filtering (last 1 hour for current run)
                # Get recent tests only
                recent_test_ids = set()
                now = datetime.now(timezone.utc)
                for test_id in all_completed_set:
                    metrics = get_test_metrics_from_s3(config, test_id)
                    if metrics:
                        timestamp_str = metrics.get('timestamp', '')
                        if timestamp_str:
                            try:
                                if 'T' in timestamp_str:
                                    if timestamp_str.endswith('Z'):
                                        test_dt = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                                    else:
                                        test_dt = datetime.fromisoformat(timestamp_str)
                                    if test_dt.tzinfo is None:
                                        test_dt = test_dt.replace(tzinfo=timezone.utc)
                                    age_hours = (now - test_dt).total_seconds() / 3600
                                    if age_hours <= 1:  # Only tests from last hour
                                        recent_test_ids.add(test_id)
                            except Exception as e:
                                # Skip tests with invalid timestamps
                                pass
                completed_set = recent_test_ids
            
            completed = len(completed_set)
            
            elapsed = time.time() - start_time
            
            # Get aggregate metrics if we have completed tests
            # Use shorter time window (1 hour) for current run metrics
            aggregate_metrics = {}
            if completed > 0:
                aggregate_metrics = get_aggregate_metrics(config, completed_set, max_age_hours=1)
                # Capture test suite start time from first completed test (fallback if no start marker)
                if test_suite_start_timestamp is None and aggregate_metrics.get('test_suite_start_time'):
                    test_suite_start_timestamp = aggregate_metrics['test_suite_start_time']
            
            # Also check for start marker on each iteration (in case it was just uploaded)
            if test_suite_start_timestamp is None:
                start_marker = get_test_suite_start_marker(config)
                if start_marker and start_marker.get('test_suite_start_time'):
                    test_suite_start_timestamp = start_marker['test_suite_start_time']
            
            # Calculate test execution time (time since test suite started)
            test_execution_time = None
            test_execution_time_str = ""
            if test_suite_start_timestamp:
                try:
                    # Parse ISO format timestamp
                    if 'T' in test_suite_start_timestamp:
                        start_dt = datetime.fromisoformat(test_suite_start_timestamp.replace('Z', '+00:00'))
                        # Get current time in UTC
                        now_dt = datetime.now(start_dt.tzinfo) if start_dt.tzinfo else datetime.utcnow()
                        # Calculate difference
                        test_execution_time = (now_dt - start_dt).total_seconds()
                        
                        # Format as hours:minutes:seconds or minutes:seconds
                        if test_execution_time >= 3600:
                            hours = int(test_execution_time // 3600)
                            minutes = int((test_execution_time % 3600) // 60)
                            seconds = int(test_execution_time % 60)
                            test_execution_time_str = f"{hours}h {minutes}m {seconds}s"
                        elif test_execution_time >= 60:
                            minutes = int(test_execution_time // 60)
                            seconds = int(test_execution_time % 60)
                            test_execution_time_str = f"{minutes}m {seconds}s"
                        else:
                            test_execution_time_str = f"{int(test_execution_time)}s"
                except Exception:
                    pass
            
            # Check EC2 for running tests (if instance_id configured)
            ec2_status = {}
            if config.instance_id:
                ec2_status = check_running_tests_on_ec2(config)
            
            if total_tests:
                remaining = total_tests - completed
                progress_pct = (completed / total_tests * 100) if total_tests > 0 else 0
                
                # Estimate remaining time based on average time per test
                # Use a more conservative estimate: only calculate if we have meaningful progress
                if completed > 0 and elapsed > 0:
                    avg_per_test = elapsed / completed
                    est_remaining = avg_per_test * remaining
                    # Cap estimate at reasonable maximum (e.g., 10 hours)
                    est_remaining = min(est_remaining, 36000)
                else:
                    est_remaining = 0
                
                # Show new tests if any
                new_tests = completed - last_count
                status = ""
                if new_tests > 0:
                    status = f" (+{new_tests} new)"
                elif new_tests < 0:
                    # This can happen if we're filtering by config and tests were removed
                    status = ""
                
                # Format time display - ensure clean output
                elapsed_str = f"{elapsed/60:.1f}m"
                remaining_str = f"{est_remaining/60:.1f}m" if est_remaining > 0 else "calculating..."
                
                # Clear screen or just line based on preference
                if use_clear_screen:
                    # Clear screen and reprint header
                    os.system('clear' if os.name != 'nt' else 'cls')
                    print("=" * 80)
                    print("S3-Based Test Progress Monitoring")
                    print("=" * 80)
                    print(f"S3 Bucket: {config.s3_bucket} | Region: {config.region} | Total: {total_tests} tests")
                    
                    # Show test suite start time and elapsed time if available
                    if test_suite_start_timestamp:
                        try:
                            start_ts = test_suite_start_timestamp
                            # Parse ISO format timestamp
                            if 'T' in start_ts:
                                dt = datetime.fromisoformat(start_ts.replace('Z', '+00:00'))
                                # Convert to local time
                                local_dt = dt.astimezone()
                                start_time_str = local_dt.strftime('%Y-%m-%d %H:%M:%S %Z')
                                print(f"Test Suite Start Time: {start_time_str}")
                        except Exception:
                            pass
                    
                    # Always show elapsed time (either from test suite start or monitoring start)
                    if test_execution_time_str:
                        print(f"Test Suite Elapsed Time: {test_execution_time_str}")
                    else:
                        # Fallback to monitoring elapsed time if test suite start not available yet
                        elapsed_minutes = int(elapsed // 60)
                        elapsed_seconds = int(elapsed % 60)
                        if elapsed_minutes > 0:
                            print(f"Monitoring Elapsed Time: {elapsed_minutes}m {elapsed_seconds}s")
                        else:
                            print(f"Monitoring Elapsed Time: {elapsed_seconds}s")
                    
                    print("=" * 80)
                    print()
                else:
                    # Just clear the line
                    print(f"\r{' ' * 150}\r", end="", flush=True)
                
                # Progress line - always show test suite elapsed time if available
                if test_execution_time_str:
                    progress_line = f"Progress: {completed}/{total_tests} ({progress_pct:.1f}%){status} | " \
                                  f"Elapsed: {test_execution_time_str} | Est. remaining: {remaining_str}"
                else:
                    progress_line = f"Progress: {completed}/{total_tests} ({progress_pct:.1f}%){status} | " \
                                  f"Monitoring: {elapsed_str} | Est. remaining: {remaining_str}"
                
                # EC2 status line (show running processes)
                ec2_status_line = ""
                if ec2_status.get('enabled'):
                    running = ec2_status.get('running_processes', 0)
                    if running > 0:
                        ec2_status_line = f" | 🔄 {running} test(s) running on EC2"
                    elif ec2_status.get('recent_results'):
                        ec2_status_line = f" | ⏸️  No active processes (recent results on EC2)"
                
                # Metrics line (show periodically or when new tests complete)
                metrics_line = ""
                resource_line = ""
                if aggregate_metrics and (new_tests > 0 or elapsed - last_metrics_display >= metrics_display_interval):
                    # Performance metrics
                    metrics_line = "\n" + "─" * 80 + "\n" \
                        f"Performance: Throughput: {aggregate_metrics.get('avg_throughput', 0):.0f} ops/s (max: {aggregate_metrics.get('max_throughput', 0):.0f}) | " \
                        f"P95: {aggregate_metrics.get('avg_p95_latency_ms', 0):.0f}ms (max: {aggregate_metrics.get('max_p95_latency_ms', 0):.0f}) | " \
                        f"P99: {aggregate_metrics.get('avg_p99_latency_ms', 0):.0f}ms (max: {aggregate_metrics.get('max_p99_latency_ms', 0):.0f}) | " \
                        f"Error Rate: {aggregate_metrics.get('error_rate_pct', 0):.1f}%"
                    
                    # Resource utilization (if available)
                    if aggregate_metrics.get('cpu_avg_pct', 0) > 0:
                        resource_line = "\n" + "─" * 80 + "\n" \
                            f"Resource Utilization: " \
                            f"CPU: {aggregate_metrics.get('cpu_avg_pct', 0):.1f}% (max: {aggregate_metrics.get('cpu_max_pct', 0):.1f}%) | " \
                            f"Memory: {aggregate_metrics.get('memory_avg_pct', 0):.1f}% (max: {aggregate_metrics.get('memory_max_pct', 0):.1f}%) | " \
                            f"Disk: R:{aggregate_metrics.get('disk_read_ops_sec', 0):.0f}/s W:{aggregate_metrics.get('disk_write_ops_sec', 0):.0f}/s | " \
                            f"Network: RX:{aggregate_metrics.get('network_rx_mbps', 0):.2f}MB/s TX:{aggregate_metrics.get('network_tx_mbps', 0):.2f}MB/s | " \
                            f"Java: CPU:{aggregate_metrics.get('java_cpu_avg_pct', 0):.1f}% Mem:{aggregate_metrics.get('java_mem_avg_pct', 0):.1f}%"
                    
                    # Add EC2 recent results if available
                    if ec2_status.get('recent_results'):
                        recent = ec2_status['recent_results']
                        if recent:
                            result_ids = ', '.join([r['test_id'] for r in recent[:2]])
                            metrics_line += f"\nEC2 Recent: {result_ids} (on instance, may not be in S3 yet)"
                    
                    last_metrics_display = elapsed
                
                print(f"{progress_line}{ec2_status_line}{metrics_line}{resource_line}", end="", flush=True)
                
                last_count = completed
                
                if completed >= total_tests:
                    print("\n✓ All tests completed!")
                    # Show final metrics summary
                    if aggregate_metrics:
                        print("\n" + "=" * 80)
                        print("Final Metrics Summary")
                        print("=" * 80)
                        print(f"Total Tests: {aggregate_metrics.get('total_tests', 0)}")
                        print(f"Total Operations: {aggregate_metrics.get('total_success', 0) + aggregate_metrics.get('total_errors', 0):,}")
                        print(f"  Success: {aggregate_metrics.get('total_success', 0):,}")
                        print(f"  Errors: {aggregate_metrics.get('total_errors', 0):,}")
                        print(f"  Error Rate: {aggregate_metrics.get('error_rate_pct', 0):.2f}%")
                        print(f"\nThroughput:")
                        print(f"  Average: {aggregate_metrics.get('avg_throughput', 0):.0f} inserts/sec")
                        print(f"  Maximum: {aggregate_metrics.get('max_throughput', 0):.0f} inserts/sec")
                        print(f"\nLatency (P95):")
                        print(f"  Average: {aggregate_metrics.get('avg_p95_latency_ms', 0):.0f} ms")
                        print(f"  Maximum: {aggregate_metrics.get('max_p95_latency_ms', 0):.0f} ms")
                        print(f"\nLatency (P99):")
                        print(f"  Average: {aggregate_metrics.get('avg_p99_latency_ms', 0):.0f} ms")
                        print(f"  Maximum: {aggregate_metrics.get('max_p99_latency_ms', 0):.0f} ms")
                        if aggregate_metrics.get('avg_pool_utilization_pct', 0) > 0:
                            print(f"\nConnection Pool:")
                            print(f"  Average Utilization: {aggregate_metrics.get('avg_pool_utilization_pct', 0):.1f}%")
                    break
            else:
                new_tests = completed - last_count
                status = f" (+{new_tests} new)" if new_tests > 0 else ""
                
                # Clear screen or just line
                if use_clear_screen:
                    os.system('clear' if os.name != 'nt' else 'cls')
                    print("=" * 80)
                    print("S3-Based Test Progress Monitoring")
                    print("=" * 80)
                    print(f"S3 Bucket: {config.s3_bucket} | Region: {config.region}")
                    
                    # Show test suite start time and elapsed time if available
                    if test_suite_start_timestamp:
                        try:
                            start_ts = test_suite_start_timestamp
                            # Parse ISO format timestamp
                            if 'T' in start_ts:
                                dt = datetime.fromisoformat(start_ts.replace('Z', '+00:00'))
                                # Convert to local time
                                local_dt = dt.astimezone()
                                start_time_str = local_dt.strftime('%Y-%m-%d %H:%M:%S %Z')
                                print(f"Test Suite Start Time: {start_time_str}")
                        except Exception:
                            pass
                    
                    # Always show elapsed time (either from test suite start or monitoring start)
                    if test_execution_time_str:
                        print(f"Test Suite Elapsed Time: {test_execution_time_str}")
                    else:
                        # Fallback to monitoring elapsed time if test suite start not available yet
                        elapsed_minutes = int(elapsed // 60)
                        elapsed_seconds = int(elapsed % 60)
                        if elapsed_minutes > 0:
                            print(f"Monitoring Elapsed Time: {elapsed_minutes}m {elapsed_seconds}s")
                        else:
                            print(f"Monitoring Elapsed Time: {elapsed_seconds}s")
                    
                    print("=" * 80)
                    print()
                else:
                    print(f"\r{' ' * 150}\r", end="", flush=True)
                
                # Show metrics if available
                metrics_info = ""
                if aggregate_metrics:
                    metrics_info = f" | Avg Throughput: {aggregate_metrics.get('avg_throughput', 0):.0f} ops/s"
                
                # Include test execution time in progress line if available
                if test_execution_time_str:
                    print(f"Completed: {completed} tests{status}{metrics_info} | Running: {test_execution_time_str}", end="", flush=True)
                else:
                    print(f"Completed: {completed} tests{status}{metrics_info} | Elapsed: {elapsed/60:.1f}m", end="", flush=True)
                last_count = completed
            
            time.sleep(interval)
    
    except KeyboardInterrupt:
        print("\n\nMonitoring stopped by user")
    except Exception as e:
        print(f"\n\nError during monitoring: {e}")
        import traceback
        traceback.print_exc()


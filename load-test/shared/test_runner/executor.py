"""Test execution logic for running k6 tests."""

import os
import subprocess
import time
import json
from pathlib import Path
from typing import Dict, Optional, Tuple
from rich.console import Console

from .config import APIConfig, TestMode, ConfigManager


class TestExecutor:
    """Handles test execution including Docker and k6 operations."""
    
    def __init__(self, base_dir: str, console: Optional[Console] = None):
        self.base_dir = Path(base_dir)
        self.console = console or Console()
        self.results_dir = self.base_dir / "load-test" / "results" / "throughput-sequential"
    
    def ensure_database_running(self) -> bool:
        """Ensure PostgreSQL database is running and Docker network exists."""
        try:
            # Ensure Docker network exists (required for Lambda APIs via SAM Local)
            self._ensure_docker_network()
            
            # Check if container exists and is running
            result = subprocess.run(
                ["docker-compose", "ps", "postgres-large"],
                cwd=self.base_dir,
                capture_output=True,
                text=True,
            )
            
            if "postgres-large" not in result.stdout or "Up" not in result.stdout:
                self.console.print("[yellow]Starting PostgreSQL database...[/yellow]")
                subprocess.run(
                    ["docker-compose", "up", "-d", "postgres-large"],
                    cwd=self.base_dir,
                    check=True,
                )
                time.sleep(5)
            
            # Wait for PostgreSQL to be ready
            max_attempts = 30
            for attempt in range(max_attempts):
                result = subprocess.run(
                    ["docker-compose", "exec", "-T", "postgres-large", "pg_isready", "-U", "postgres"],
                    cwd=self.base_dir,
                    capture_output=True,
                )
                if result.returncode == 0:
                    return True
                time.sleep(2)
            
            self.console.print("[red]PostgreSQL failed to become ready[/red]")
            return False
        except Exception as e:
            self.console.print(f"[red]Error ensuring database: {e}[/red]")
            return False
    
    def _ensure_docker_network(self) -> bool:
        """Ensure Docker network 'car_network' exists (required for Lambda APIs)."""
        try:
            result = subprocess.run(
                ["docker", "network", "inspect", "car_network"],
                capture_output=True,
                text=True,
            )
            if result.returncode == 0:
                return True
            
            # Network doesn't exist, create it
            self.console.print("[yellow]Creating Docker network 'car_network'...[/yellow]")
            subprocess.run(
                ["docker", "network", "create", "car_network"],
                check=True,
                capture_output=True,
            )
            self.console.print("[green]Docker network 'car_network' created[/green]")
            return True
        except subprocess.CalledProcessError as e:
            self.console.print(f"[yellow]Warning: Could not create Docker network: {e}[/yellow]")
            return False
        except Exception as e:
            self.console.print(f"[yellow]Warning: Error checking Docker network: {e}[/yellow]")
            return False
    
    def stop_all_apis(self) -> bool:
        """Stop all producer API containers and Lambda functions."""
        try:
            # Stop Docker-based APIs
            apis = ConfigManager.ALL_APIS
            for api_name in apis:
                api_config = ConfigManager.get_api_config(api_name)
                if api_config and not api_config.is_lambda:
                    subprocess.run(
                        ["docker-compose", "--profile", "producer", "--profile", "producer-grpc",
                         "--profile", "producer-rust", "--profile", "producer-rust-grpc",
                         "--profile", "producer-go", "--profile", "producer-go-grpc",
                         "stop", api_name],
                        cwd=self.base_dir,
                        capture_output=True,
                    )
            
            # Stop Lambda APIs
            stop_lambda_script = self.base_dir / "load-test" / "shared" / "stop-local-lambdas.sh"
            if stop_lambda_script.exists():
                subprocess.run(
                    ["bash", str(stop_lambda_script)],
                    cwd=self.base_dir,
                    capture_output=True,
                )
            return True
        except Exception as e:
            self.console.print(f"[yellow]Warning: Error stopping APIs: {e}[/yellow]")
            return False
    
    def clear_database(self) -> bool:
        """Clear the database before a test."""
        try:
            subprocess.run(
                ["docker-compose", "exec", "-T", "postgres-large", "psql", "-U", "postgres", "-d", "car_entities",
                 "-c", "TRUNCATE TABLE car_entities CASCADE;"],
                cwd=self.base_dir,
                check=True,
                capture_output=True,
            )
            return True
        except Exception as e:
            self.console.print(f"[yellow]Warning: Error clearing database: {e}[/yellow]")
            return False
    
    def start_api(self, api_config: APIConfig) -> bool:
        """Start a specific API container or Lambda function."""
        if api_config.is_lambda:
            return self._start_lambda_api(api_config)
        else:
            return self._start_docker_api(api_config)
    
    def _start_docker_api(self, api_config: APIConfig) -> bool:
        """Start a Docker-based API container."""
        try:
            # Start the API
            result = subprocess.run(
                ["docker-compose", "--profile", api_config.profile, "up", "-d", api_config.name],
                cwd=self.base_dir,
                check=True,
                capture_output=True,
                text=True,
            )
            
            # Wait a moment for container to start
            time.sleep(2)
            
            # Verify container is actually running
            check_result = subprocess.run(
                ["docker", "ps", "--filter", f"name={api_config.name}", "--format", "{{.Names}}"],
                cwd=self.base_dir,
                capture_output=True,
                text=True,
            )
            
            if api_config.name not in check_result.stdout:
                if self.console:
                    self.console.print(f"[red]Container {api_config.name} failed to start[/red]")
                    # Show error output if available
                    if result.stderr:
                        self.console.print(f"[yellow]Error output: {result.stderr}[/yellow]")
                return False
            
            return True
        except subprocess.CalledProcessError as e:
            if self.console:
                self.console.print(f"[red]Error starting {api_config.name}: {e}[/red]")
                if e.stderr:
                    error_msg = e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr
                    self.console.print(f"[yellow]Error details: {error_msg}[/yellow]")
            return False
        except Exception as e:
            if self.console:
                self.console.print(f"[red]Error starting {api_config.name}: {e}[/red]")
            return False
    
    def _start_lambda_api(self, api_config: APIConfig) -> bool:
        """Start a Lambda API using SAM Local (runs in Docker containers)."""
        try:
            # Ensure prerequisites are met
            if not self._ensure_docker_network():
                self.console.print(f"[yellow]Warning: Docker network check failed, but continuing...[/yellow]")
            
            # Ensure database is running (Lambda APIs need it)
            if not self.ensure_database_running():
                self.console.print(f"[red]Database is not running. Lambda APIs require the database.[/red]")
                return False
            
            # Check if SAM CLI is available
            sam_check = subprocess.run(
                ["which", "sam"],
                capture_output=True,
            )
            if sam_check.returncode != 0:
                self.console.print(f"[red]SAM CLI is not installed. Please install it first.[/red]")
                self.console.print(f"[yellow]Install: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html[/yellow]")
                return False
            
            # Use the start-local-lambdas.sh script
            start_lambda_script = self.base_dir / "load-test" / "shared" / "start-local-lambdas.sh"
            if not start_lambda_script.exists():
                self.console.print(f"[red]Lambda start script not found: {start_lambda_script}[/red]")
                return False
            
            # Run the start script for this specific API
            # The script will use SAM Local with --docker-network car_network
            self.console.print(f"[yellow]Starting Lambda {api_config.name} via SAM Local (Docker)...[/yellow]")
            result = subprocess.run(
                ["bash", str(start_lambda_script), api_config.name],
                cwd=self.base_dir,
                capture_output=True,
                text=True,
            )
            
            if result.returncode != 0:
                if self.console:
                    self.console.print(f"[red]Failed to start Lambda {api_config.name}[/red]")
                    if result.stdout:
                        self.console.print(f"[yellow]Output: {result.stdout}[/yellow]")
                    if result.stderr:
                        self.console.print(f"[yellow]Error output: {result.stderr}[/yellow]")
                return False
            
            # Wait a moment for Lambda to start (SAM Local needs time to start Docker containers)
            time.sleep(5)
            
            return True
        except Exception as e:
            if self.console:
                self.console.print(f"[red]Error starting Lambda {api_config.name}: {e}[/red]")
            return False
    
    def check_api_health(self, api_config: APIConfig, max_attempts: int = 60) -> bool:
        """Check if API is healthy."""
        health_port = api_config.health_check_port or api_config.port
        
        for attempt in range(max_attempts):
            try:
                if api_config.protocol == "http":
                    # For Lambda REST APIs, try both health endpoints
                    health_urls = [
                        f"http://localhost:{health_port}/api/v1/events/health",
                        f"http://localhost:{health_port}/health",
                    ]
                    for health_url in health_urls:
                        result = subprocess.run(
                            ["curl", "-f", "-s", health_url],
                            capture_output=True,
                            timeout=5,
                        )
                        if result.returncode == 0:
                            return True
                else:
                    # For gRPC, check if port is open
                    # For Lambda APIs, check if process is running first
                    if api_config.is_lambda:
                        pid_file = self.base_dir / "load-test" / "shared" / ".lambda-pids" / f"{api_config.name}.pid"
                        if pid_file.exists():
                            try:
                                with open(pid_file, 'r') as f:
                                    pid = int(f.read().strip())
                                # Check if process is running
                                check_pid = subprocess.run(
                                    ["ps", "-p", str(pid)],
                                    capture_output=True,
                                )
                                if check_pid.returncode != 0:
                                    # Process not running
                                    if self.console:
                                        self.console.print(f"[yellow]Lambda {api_config.name} process not running, waiting...[/yellow]")
                                    time.sleep(2)
                                    continue
                            except Exception:
                                pass
                    
                    # For Docker-based gRPC APIs, check if container is running
                    if not api_config.is_lambda:
                        container_check = subprocess.run(
                            ["docker", "ps", "--filter", f"name={api_config.name}", "--format", "{{.Names}}"],
                            capture_output=True,
                            text=True,
                        )
                        if api_config.name not in container_check.stdout:
                            if self.console:
                                self.console.print(f"[yellow]Container {api_config.name} is not running, waiting...[/yellow]")
                            time.sleep(2)
                            continue
                    
                    # Check if port is open
                    result = subprocess.run(
                        ["nc", "-z", "localhost", str(health_port)],
                        capture_output=True,
                    )
                    if result.returncode == 0:
                        return True
            except subprocess.TimeoutExpired:
                pass
            except FileNotFoundError:
                # curl or nc not available, try alternative method
                try:
                    import socket
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(2)
                    result = sock.connect_ex(('localhost', health_port))
                    sock.close()
                    if result == 0:
                        return True
                except Exception:
                    pass
            except Exception:
                pass
            
            if attempt < max_attempts - 1:
                time.sleep(2)
        
        return False
    
    def _get_k6_json_path(self, api_config: APIConfig, test_mode: TestMode,
                          payload_size: str = "400b") -> Optional[str]:
        """Get the JSON file path that will be created by k6."""
        api_results_dir = self.results_dir / api_config.name
        if payload_size:
            api_results_dir = api_results_dir / payload_size
        api_results_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        json_filename = f"{api_config.name}-throughput-{test_mode.value}-{payload_size}-{timestamp}.json"
        json_file = api_results_dir / json_filename
        return str(json_file)
    
    def run_k6_test(self, api_config: APIConfig, test_mode: TestMode, 
                   payload_size: str = "400b", json_file_path: Optional[str] = None) -> Tuple[bool, Optional[str]]:
        """Run k6 test and return (success, json_file_path)."""
        # Use provided path or generate one
        if json_file_path:
            json_file = Path(json_file_path)
            api_results_dir = json_file.parent
            json_filename = json_file.name
        else:
            # Create results directory
            api_results_dir = self.results_dir / api_config.name
            if payload_size:
                api_results_dir = api_results_dir / payload_size
            api_results_dir.mkdir(parents=True, exist_ok=True)
            
            # Generate output file name
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            json_filename = f"{api_config.name}-throughput-{test_mode.value}-{payload_size}-{timestamp}.json"
            json_file = api_results_dir / json_filename
        
        # Build k6 command
        k6_script_path = f"/k6/scripts/{api_config.test_file}"
        json_file_in_container = f"/k6/results/throughput-sequential/{api_config.name}"
        if payload_size:
            json_file_in_container = f"{json_file_in_container}/{payload_size}"
        json_file_in_container = f"{json_file_in_container}/{json_filename}"
        
        k6_cmd = ["k6", "run"]
        k6_cmd.extend(["--out", f"json={json_file_in_container}"])
        k6_cmd.extend(["-e", f"TEST_MODE={test_mode.value}"])
        
        # Lambda APIs use API_URL instead of HOST/PORT
        if api_config.is_lambda:
            # Determine API URL based on protocol
            if api_config.protocol == "http":
                api_url = f"http://localhost:{api_config.port}"
            else:  # gRPC
                api_url = f"http://localhost:{api_config.port}"
            k6_cmd.extend(["-e", f"API_URL={api_url}"])
            k6_cmd.extend(["-e", f"LAMBDA_API_URL={api_url}"])
        else:
            # Docker-based APIs use HOST/PORT
            k6_cmd.extend(["-e", f"PROTOCOL={api_config.protocol}"])
            k6_cmd.extend(["-e", f"HOST={api_config.docker_host}"])
            k6_cmd.extend(["-e", f"PORT={api_config.port}"])
        
        # Always specify payload size explicitly
        if payload_size:
            k6_cmd.extend(["-e", f"PAYLOAD_SIZE={payload_size}"])
        
        if api_config.protocol == "grpc":
            if api_config.proto_file:
                k6_cmd.extend(["-e", f"PROTO_FILE={api_config.proto_file}"])
            if api_config.service_name:
                k6_cmd.extend(["-e", f"SERVICE={api_config.service_name}"])
            if api_config.method_name:
                k6_cmd.extend(["-e", f"METHOD={api_config.method_name}"])
        else:
            # For REST APIs, set PATH if not Lambda (Lambda APIs handle this in the test script)
            if not api_config.is_lambda:
                k6_cmd.extend(["-e", "PATH=/api/v1/events"])
            else:
                # Lambda REST APIs use API_PATH
                k6_cmd.extend(["-e", "API_PATH=/api/v1/events"])
        
        k6_cmd.append(k6_script_path)
        
        # Run k6 in Docker container
        try:
            docker_cmd = [
                "docker-compose", "--profile", "k6-test", "run", "--rm",
                "--entrypoint", "/bin/sh", "k6-throughput", "-c", " ".join(k6_cmd)
            ]
            
            result = subprocess.run(
                docker_cmd,
                cwd=self.base_dir,
                capture_output=True,
                text=True,
                timeout=ConfigManager.get_test_duration(test_mode) + 300,  # Add 5 min buffer
            )
            
            # Check if JSON file was created
            if json_file.exists():
                return True, str(json_file)
            else:
                self.console.print(f"[yellow]Warning: k6 test completed but JSON file not found[/yellow]")
                return False, None
                
        except subprocess.TimeoutExpired:
            self.console.print(f"[red]k6 test timed out[/red]")
            return False, None
        except Exception as e:
            self.console.print(f"[red]Error running k6 test: {e}[/red]")
            return False, None
    
    def extract_test_metrics(self, json_file: str) -> Optional[Dict]:
        """Extract metrics from k6 JSON output file (supports both single JSON and NDJSON formats)."""
        try:
            from datetime import datetime
            
            # Try single JSON first (summary format)
            with open(json_file, 'r') as f:
                content = f.read().strip()
                try:
                    data = json.loads(content)
                    if 'metrics' in data:
                        metrics = data.get('metrics', {})
                        req_metric = metrics.get('http_reqs') or metrics.get('grpc_reqs')
                        duration_metric = metrics.get('http_req_duration') or metrics.get('grpc_req_duration')
                        failed_metric = metrics.get('http_req_failed') or metrics.get('grpc_req_failed')
                        
                        if req_metric:
                            values = req_metric.get('values', {})
                            duration_values = duration_metric.get('values', {}) if duration_metric else {}
                            failed_values = failed_metric.get('values', {}) if failed_metric else {}
                            
                            total_requests = int(values.get('count', 0))
                            throughput = float(values.get('rate', 0))
                            error_rate = float(failed_values.get('rate', 0) * 100) if failed_values else 0.0
                            failed_count = int(total_requests * (error_rate / 100)) if total_requests > 0 else 0
                            success_count = total_requests - failed_count
                            
                            avg_response = float(duration_values.get('avg', 0)) if duration_values else 0.0
                            min_response = float(duration_values.get('min', 0)) if duration_values else 0.0
                            max_response = float(duration_values.get('max', 0)) if duration_values else 0.0
                            p95_response = float(duration_values.get('p(95)', 0)) if duration_values else 0.0
                            p99_response = float(duration_values.get('p(99)', 0)) if duration_values else 0.0
                            
                            root = data.get('root_group', {})
                            duration_ms = float(root.get('execution_duration', {}).get('total', 0))
                            duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
                            
                            return {
                                'total_requests': total_requests,
                                'successful': success_count,
                                'failed': failed_count,
                                'throughput': throughput,
                                'avg_response': avg_response,
                                'min_response': min_response,
                                'max_response': max_response,
                                'p95_response': p95_response,
                                'p99_response': p99_response,
                                'error_rate': error_rate,
                                'duration_seconds': duration_seconds,
                            }
                except json.JSONDecodeError:
                    pass
            
            # Parse NDJSON format (k6's default output)
            http_reqs = []
            grpc_reqs = []
            http_durations = []
            grpc_durations = []
            http_failed = []
            grpc_failed = []
            iterations = []
            iteration_durations = []
            connection_failures = []
            errors = []
            start_time = None
            end_time = None
            
            with open(json_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        obj = json.loads(line)
                        obj_type = obj.get('type', '')
                        metric_name = obj.get('metric', '')
                        data = obj.get('data', {})
                        
                        if 'time' in data:
                            time_str = data['time']
                            try:
                                if time_str.endswith('Z'):
                                    time_str = time_str[:-1] + '+00:00'
                                time_obj = datetime.fromisoformat(time_str)
                                if start_time is None or time_obj < start_time:
                                    start_time = time_obj
                                if end_time is None or time_obj > end_time:
                                    end_time = time_obj
                            except Exception:
                                pass
                        
                        if obj_type == 'Point':
                            if metric_name == 'http_reqs':
                                http_reqs.append(data.get('value', 0))
                            elif metric_name == 'grpc_reqs':
                                grpc_reqs.append(data.get('value', 0))
                            elif metric_name == 'http_req_duration':
                                http_durations.append(data.get('value', 0))
                            elif metric_name == 'grpc_req_duration':
                                grpc_durations.append(data.get('value', 0))
                            elif metric_name == 'http_req_failed':
                                failed_value = data.get('value', 0)
                                if failed_value > 0:
                                    http_failed.append(1)
                            elif metric_name == 'grpc_req_failed':
                                failed_value = data.get('value', 0)
                                if failed_value > 0:
                                    grpc_failed.append(1)
                            elif metric_name == 'iterations':
                                iterations.append(data.get('value', 0))
                            elif metric_name == 'iteration_duration':
                                iteration_durations.append(data.get('value', 0))
                            elif metric_name == 'connection_failures':
                                if data.get('value', 0) > 0:
                                    connection_failures.append(1)
                            elif metric_name == 'errors':
                                if data.get('value', 0) > 0:
                                    errors.append(1)
                            elif obj_type == 'Summary' and metric_name == '':
                                # Handle Summary type in NDJSON
                                metrics_data = data.get('metrics', {})
                                duration_metric = metrics_data.get('http_req_duration') or metrics_data.get('grpc_req_duration')
                                req_metric = metrics_data.get('http_reqs') or metrics_data.get('grpc_reqs')
                                failed_metric = metrics_data.get('http_req_failed') or metrics_data.get('grpc_req_failed')
                                
                                if req_metric and duration_metric:
                                    values = req_metric.get('values', {})
                                    duration_values = duration_metric.get('values', {})
                                    failed_values = failed_metric.get('values', {}) if failed_metric else {}
                                    
                                    total_requests = int(values.get('count', 0))
                                    throughput = float(values.get('rate', 0))
                                    error_rate = float(failed_values.get('rate', 0) * 100) if failed_values else 0.0
                                    failed_count = int(total_requests * (error_rate / 100)) if total_requests > 0 else 0
                                    
                                    root = data.get('root_group', {})
                                    duration_ms = float(root.get('execution_duration', {}).get('total', 0))
                                    duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
                                    
                                    return {
                                        'total_requests': total_requests,
                                        'successful': total_requests - failed_count,
                                        'failed': failed_count,
                                        'throughput': throughput,
                                        'avg_response': float(duration_values.get('avg', 0)),
                                        'min_response': float(duration_values.get('min', 0)),
                                        'max_response': float(duration_values.get('max', 0)),
                                        'p95_response': float(duration_values.get('p(95)', 0)),
                                        'p99_response': float(duration_values.get('p(99)', 0)),
                                        'error_rate': error_rate,
                                        'duration_seconds': duration_seconds,
                                    }
                    except json.JSONDecodeError:
                        continue
            
            # Process collected NDJSON data
            # For gRPC, if we don't have grpc_reqs, use grpc_req_duration points
            if not http_reqs and not grpc_reqs:
                if grpc_durations:
                    grpc_reqs = [1] * len(grpc_durations)
                elif iterations:
                    total_iterations = sum(iterations)
                    grpc_reqs = [1] * total_iterations
            
            reqs = http_reqs if http_reqs else grpc_reqs
            durations = http_durations if http_durations else grpc_durations
            failed = http_failed if http_failed else grpc_failed
            
            # Check for connection failures - if we have connection failures but no durations,
            # use iteration_duration as fallback for response time estimation
            has_connection_failures = len(connection_failures) > 0 or len(errors) > 0
            if not durations and iteration_durations and has_connection_failures:
                # Use iteration_duration as proxy for response time (convert seconds to ms)
                durations = [d * 1000.0 for d in iteration_durations]
            
            if not reqs:
                return None
            
            total_requests = len(reqs)
            failed_count = sum(failed) if failed else 0
            
            # If we have connection failures, count them as failures
            if connection_failures:
                failed_count = max(failed_count, len(connection_failures))
            
            success_count = total_requests - failed_count
            
            # Calculate duration
            if start_time and end_time and (end_time - start_time).total_seconds() > 0.01:
                duration_seconds = (end_time - start_time).total_seconds()
            elif iteration_durations:
                duration_seconds = sum(iteration_durations) / 1000.0
            else:
                duration_seconds = max(0.1, total_requests * 0.1)
            
            duration_seconds = max(0.1, duration_seconds)
            throughput = total_requests / duration_seconds
            
            # Calculate response time statistics
            if durations:
                sorted_durations = sorted(durations)
                avg_response = sum(durations) / len(durations)
                min_response = min(durations)
                max_response = max(durations)
                p95_idx = int(len(sorted_durations) * 0.95)
                p99_idx = int(len(sorted_durations) * 0.99)
                p95_response = sorted_durations[min(p95_idx, len(sorted_durations) - 1)]
                p99_response = sorted_durations[min(p99_idx, len(sorted_durations) - 1)]
            else:
                avg_response = 0.0
                min_response = 0.0
                max_response = 0.0
                p95_response = 0.0
                p99_response = 0.0
            
            # Calculate error rate - include connection failures
            total_errors = failed_count
            if connection_failures:
                total_errors = max(total_errors, len(connection_failures))
            error_rate = (total_errors / total_requests * 100) if total_requests > 0 else 0.0
            
            return {
                'total_requests': total_requests,
                'successful': success_count,
                'failed': failed_count,
                'throughput': throughput,
                'avg_response': avg_response,
                'min_response': min_response,
                'max_response': max_response,
                'p95_response': p95_response,
                'p99_response': p99_response,
                'error_rate': error_rate,
                'duration_seconds': duration_seconds,
            }
        except Exception as e:
            if self.config.verbose if hasattr(self, 'config') else False:
                self.console.print(f"[yellow]Warning: Error extracting metrics: {e}[/yellow]")
            return None


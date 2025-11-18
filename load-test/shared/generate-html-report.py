#!/usr/bin/env python3
"""
Generate comprehensive HTML report from k6 test results
"""
import json
import sys
import os
import subprocess
from datetime import datetime, timedelta
from pathlib import Path

def extract_metrics_from_json(json_file):
    """Extract metrics from k6 JSON file (supports both summary and NDJSON formats)"""
    if not json_file or not os.path.exists(json_file):
        return None
    
    try:
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
                        
                        total_samples = int(values.get('count', 0))
                        throughput = float(values.get('rate', 0))
                        error_rate = float(failed_values.get('rate', 0) * 100) if failed_values else 0.0
                        success_samples = int(total_samples * (1 - (error_rate / 100))) if total_samples > 0 else 0
                        error_samples = total_samples - success_samples
                        
                        avg_response = float(duration_values.get('avg', 0)) if duration_values else 0.0
                        min_response = float(duration_values.get('min', 0)) if duration_values else 0.0
                        max_response = float(duration_values.get('max', 0)) if duration_values else 0.0
                        p95_response = float(duration_values.get('p(95)', 0)) if duration_values else 0.0
                        p99_response = float(duration_values.get('p(99)', 0)) if duration_values else 0.0
                        
                        root = data.get('root_group', {})
                        duration_ms = float(root.get('execution_duration', {}).get('total', 0))
                        duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
                        
                        return {
                            'total_samples': total_samples,
                            'success_samples': success_samples,
                            'error_samples': error_samples,
                            'duration_seconds': duration_seconds,
                            'throughput': throughput,
                            'avg_response': avg_response,
                            'min_response': min_response,
                            'max_response': max_response,
                            'p95_response': p95_response,
                            'p99_response': p99_response,
                            'error_rate': error_rate
                        }
            except json.JSONDecodeError:
                pass
        
        # Parse NDJSON format
        http_reqs = []
        grpc_reqs = []
        http_durations = []
        grpc_durations = []
        http_failed = []
        grpc_failed = []
        iterations = []
        iteration_durations = []
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
                            # Handle both Z and +00:00 timezone formats
                            if time_str.endswith('Z'):
                                time_str = time_str[:-1] + '+00:00'
                            time_obj = datetime.fromisoformat(time_str)
                            if start_time is None or time_obj < start_time:
                                start_time = time_obj
                            if end_time is None or time_obj > end_time:
                                end_time = time_obj
                        except Exception:
                            pass
                    
                    if metric_name == 'http_reqs' and obj_type == 'Point':
                        http_reqs.append(data.get('value', 0))
                    elif metric_name == 'grpc_reqs' and obj_type == 'Point':
                        grpc_reqs.append(data.get('value', 0))
                    elif metric_name == 'http_req_duration' and obj_type == 'Point':
                        http_durations.append(data.get('value', 0))
                    elif metric_name == 'grpc_req_duration' and obj_type == 'Point':
                        grpc_durations.append(data.get('value', 0))
                    elif metric_name == 'http_req_failed' and obj_type == 'Point':
                        http_failed.append(data.get('value', 0))
                    elif metric_name == 'grpc_req_failed' and obj_type == 'Point':
                        grpc_failed.append(data.get('value', 0))
                    elif metric_name == 'iterations' and obj_type == 'Point':
                        iterations.append(data.get('value', 0))
                    elif metric_name == 'iteration_duration' and obj_type == 'Point':
                        iteration_durations.append(data.get('value', 0))
                except json.JSONDecodeError:
                    continue
        
        # For gRPC, if we don't have grpc_reqs, use grpc_req_duration points or iterations as request count
        if not http_reqs and not grpc_reqs:
            if grpc_durations:
                grpc_reqs = [1] * len(grpc_durations)
            elif iterations:
                total_iterations = sum(iterations)
                grpc_reqs = [1] * total_iterations
        
        reqs = http_reqs if http_reqs else grpc_reqs
        durations = http_durations if http_durations else grpc_durations
        failed = http_failed if http_failed else grpc_failed
        
        if not reqs:
            return None
        
        total_samples = len(reqs)
        success_samples = total_samples - sum(failed) if failed else total_samples
        error_samples = sum(failed) if failed else 0
        
        # Calculate duration - prefer actual time range, fall back to iteration durations
        if start_time and end_time and (end_time - start_time).total_seconds() > 0.01:
            duration_seconds = (end_time - start_time).total_seconds()
        elif iteration_durations:
            duration_seconds = sum(iteration_durations) / 1000.0 if iteration_durations else 0.0
        else:
            duration_seconds = max(0.1, total_samples * 0.1)
        
        duration_seconds = max(0.1, duration_seconds)
        throughput = total_samples / duration_seconds if duration_seconds > 0 else 0.0
        
        if durations:
            avg_response = sum(durations) / len(durations)
            min_response = min(durations)
            max_response = max(durations)
            # Calculate percentiles
            sorted_durations = sorted(durations)
            p95_idx = int(len(sorted_durations) * 0.95)
            p99_idx = int(len(sorted_durations) * 0.99)
            p95_response = sorted_durations[p95_idx] if p95_idx < len(sorted_durations) else sorted_durations[-1]
            p99_response = sorted_durations[p99_idx] if p99_idx < len(sorted_durations) else sorted_durations[-1]
        else:
            avg_response = 0.0
            min_response = 0.0
            max_response = 0.0
            p95_response = 0.0
            p99_response = 0.0
        
        error_rate = (error_samples / total_samples * 100) if total_samples > 0 else 0.0
        
        return {
            'total_samples': total_samples,
            'success_samples': success_samples,
            'error_samples': error_samples,
            'duration_seconds': duration_seconds,
            'throughput': throughput,
            'avg_response': avg_response,
            'min_response': min_response,
            'max_response': max_response,
            'p95_response': p95_response,
            'p99_response': p99_response,
            'error_rate': error_rate
        }
    except Exception as e:
        print(f"Error reading {json_file}: {e}", file=sys.stderr)
    
    return None

def format_duration(seconds):
    """Format duration in seconds to a human-readable string"""
    if seconds <= 0:
        return "0 seconds"
    elif seconds < 60:
        return f"{seconds:.1f} seconds"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        secs = seconds % 60
        if secs < 0.1:
            return f"{minutes} minutes"
        return f"{minutes} minutes {secs:.1f} seconds"
    else:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = seconds % 60
        if minutes == 0 and secs < 0.1:
            return f"{hours} hours"
        elif secs < 0.1:
            return f"{hours} hours {minutes} minutes"
        return f"{hours} hours {minutes} minutes {secs:.1f} seconds"

def format_payload_size(size_str):
    """Format payload size string to show actual byte values"""
    if not size_str:
        return "~400-500 bytes"
    
    size_lower = size_str.lower().strip()
    
    # Map size strings to kilobyte values
    size_map = {
        'default': '~400-500 bytes',
        '4k': '4 KB',
        '8k': '8 KB',
        '32k': '32 KB',
        '64k': '64 KB'
    }
    
    return size_map.get(size_lower, size_str)

def format_payload_sizes_list(payload_sizes):
    """Format a list of payload sizes to show in kilobytes, ordered by increasing size"""
    if not payload_sizes:
        return "~400-500 bytes"
    
    # Convert payload sizes to numeric values for sorting
    def size_to_kb(size_str):
        if not size_str:
            return 0
        size_lower = size_str.lower().strip()
        size_map = {
            'default': 0.5,  # ~400-500 bytes
            '4k': 4,
            '8k': 8,
            '32k': 32,
            '64k': 64
        }
        return size_map.get(size_lower, 0)
    
    # Sort by KB value
    sorted_sizes = sorted(payload_sizes, key=size_to_kb)
    formatted_sizes = [format_payload_size(size) for size in sorted_sizes]
    return ', '.join(formatted_sizes)

def calculate_statistics(values):
    """Calculate statistical measures: mean, std dev, variance, confidence interval"""
    if not values or len(values) < 2:
        return {
            'mean': values[0] if values else 0.0,
            'std_dev': 0.0,
            'variance': 0.0,
            'ci_lower': values[0] if values else 0.0,
            'ci_upper': values[0] if values else 0.0,
            'cv': 0.0  # coefficient of variation
        }
    
    import statistics
    mean = statistics.mean(values)
    if len(values) > 1:
        std_dev = statistics.stdev(values)
        variance = statistics.variance(values)
        # 95% confidence interval (using t-distribution approximation)
        # For large samples, use z=1.96, for small samples use t-value
        n = len(values)
        if n >= 30:
            z_score = 1.96
        else:
            # Approximate t-value for 95% CI (simplified)
            z_score = 2.0
        margin_error = z_score * (std_dev / (n ** 0.5))
        ci_lower = mean - margin_error
        ci_upper = mean + margin_error
        cv = (std_dev / mean * 100) if mean > 0 else 0.0
    else:
        std_dev = 0.0
        variance = 0.0
        ci_lower = mean
        ci_upper = mean
        cv = 0.0
    
    return {
        'mean': mean,
        'std_dev': std_dev,
        'variance': variance,
        'ci_lower': ci_lower,
        'ci_upper': ci_upper,
        'cv': cv
    }

def validate_metrics(metrics):
    """Validate metrics for data quality issues"""
    warnings = []
    
    if not metrics:
        return ['No metrics data available']
    
    # Check for missing required fields
    required_fields = ['total_samples', 'success_samples', 'error_samples', 'throughput', 'avg_response']
    for field in required_fields:
        if field not in metrics:
            warnings.append(f"Missing required metric: {field}")
    
    # Validate totals
    if 'total_samples' in metrics and 'success_samples' in metrics and 'error_samples' in metrics:
        calculated_total = metrics.get('success_samples', 0) + metrics.get('error_samples', 0)
        if abs(calculated_total - metrics.get('total_samples', 0)) > 1:  # Allow 1 for rounding
            warnings.append(f"Data inconsistency: success ({metrics.get('success_samples', 0)}) + errors ({metrics.get('error_samples', 0)}) != total ({metrics.get('total_samples', 0)})")
    
    # Check for unrealistic values
    if 'avg_response' in metrics and metrics['avg_response'] < 0:
        warnings.append("Negative average response time detected")
    
    if 'throughput' in metrics and metrics['throughput'] < 0:
        warnings.append("Negative throughput detected")
    
    # Check sample size
    if 'total_samples' in metrics and metrics['total_samples'] < 100:
        warnings.append(f"Small sample size ({metrics['total_samples']}) may affect reliability")
    
    return warnings

def generate_html_report(results_dir, test_mode, timestamp):
    """Generate comprehensive HTML report"""
    results_path = Path(results_dir)
    html_file = results_path / f"comparison-report-{timestamp}.html"
    
    # API configurations
    apis = [
        {'name': 'producer-api-java-rest', 'display': 'Java REST', 'port': 9081, 'protocol': 'REST'},
        {'name': 'producer-api-java-grpc', 'display': 'Java gRPC', 'port': 9090, 'protocol': 'gRPC'},
        {'name': 'producer-api-rust-rest', 'display': 'Rust REST', 'port': 9082, 'protocol': 'REST'},
        {'name': 'producer-api-rust-grpc', 'display': 'Rust gRPC', 'port': 9091, 'protocol': 'gRPC'},
        {'name': 'producer-api-go-rest', 'display': 'Go REST', 'port': 9083, 'protocol': 'REST'},
        {'name': 'producer-api-go-grpc', 'display': 'Go gRPC', 'port': 9092, 'protocol': 'gRPC'},
    ]
    
    # Collect metrics for all APIs from database
    api_results = []
    unique_payload_sizes = set()
    total_duration_seconds = 0.0
    
    # Try to load from database first
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        from db_client import get_latest_test_runs, get_resource_metrics_summary
        
        # Get all test runs from database for this test mode
        # If timestamp is provided, we'll filter by matching k6_json_file_path pattern
        # OR collect all runs from the same execution window (within 2 hours)
        all_test_runs = get_latest_test_runs(
            api_names=[api['name'] for api in apis],
            test_mode=test_mode,
            limit=1000  # Get enough to find all matching runs
        )
        
        # Filter by timestamp if provided, and group by API name AND payload size
        # This allows us to collect all test runs (one per API+payload combination)
        # For one execution, we want ALL payload sizes with matching timestamp or within execution window
        api_test_runs = {}  # Key: (api_name, payload_size)
        
        # If timestamp provided, parse it to get the execution time window
        # Also extract timestamp patterns to match similar timestamps (for sequential payload size tests)
        execution_start_time = None
        execution_end_time = None
        timestamp_patterns = []
        if timestamp:
            try:
                # Parse timestamp (YYYYMMDD_HHMMSS) to datetime
                if len(timestamp) >= 15:
                    ts_str = f"{timestamp[:4]}-{timestamp[4:6]}-{timestamp[6:8]} {timestamp[9:11]}:{timestamp[11:13]}:{timestamp[13:15]}"
                    execution_start_time = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                    # Allow 1 hour window for same execution (tests might take time)
                    execution_end_time = execution_start_time + timedelta(hours=1)
                    
                    # Also create timestamp patterns to match similar timestamps
                    # Extract date part (YYYYMMDD) and allow time variations within 30 minutes
                    date_part = timestamp[:8]  # YYYYMMDD
                    time_part = timestamp[9:15] if len(timestamp) > 9 else ''  # HHMMSS
                    if time_part:
                        # Create pattern to match timestamps within 30 minutes
                        timestamp_patterns.append(date_part)  # Match same date
            except:
                pass
        
        for test_run in all_test_runs:
            api_name = test_run['api_name']
            payload_size = test_run.get('payload_size', 'default')
            
            # Skip "default" payload size - we only want explicit payload sizes
            if payload_size == 'default' or not payload_size or payload_size == '':
                continue
            
            # If timestamp is provided, verify it matches
            timestamp_matches = False
            if timestamp:
                json_path = test_run.get('k6_json_file_path', '')
                # Check exact timestamp match in file path
                if json_path and timestamp in json_path:
                    timestamp_matches = True
                
                # Check if timestamp pattern matches (same date, within 30 minutes)
                if not timestamp_matches and timestamp_patterns:
                    import re
                    # Extract timestamp from file path (YYYYMMDD_HHMMSS pattern)
                    path_match = re.search(r'(\d{8}_\d{6})', json_path)
                    if path_match:
                        path_timestamp = path_match.group(1)
                        path_date = path_timestamp[:8]
                        # Check if same date
                        if path_date in timestamp_patterns:
                            # Check if time is within 30 minutes
                            try:
                                path_ts_str = f"{path_timestamp[:4]}-{path_timestamp[4:6]}-{path_timestamp[6:8]} {path_timestamp[9:11]}:{path_timestamp[11:13]}:{path_timestamp[13:15]}"
                                path_ts_dt = datetime.strptime(path_ts_str, "%Y-%m-%d %H:%M:%S")
                                time_diff = abs((path_ts_dt - execution_start_time).total_seconds())
                                if time_diff <= 1800:  # 30 minutes
                                    timestamp_matches = True
                            except:
                                pass
                
                # Also check if test run started within the execution window
                if not timestamp_matches and execution_start_time and test_run.get('started_at'):
                    try:
                        start_time = test_run['started_at']
                        if isinstance(start_time, str):
                            # Try to parse the start time
                            start_time = datetime.fromisoformat(start_time.replace('Z', '+00:00'))
                        if isinstance(start_time, datetime):
                            # Remove timezone for comparison if needed
                            if start_time.tzinfo:
                                start_time = start_time.replace(tzinfo=None)
                            if execution_start_time <= start_time <= execution_end_time:
                                timestamp_matches = True
                    except:
                        pass
                
                if not timestamp_matches:
                    continue  # Timestamp doesn't match, skip this test run
            
            # Group by API name AND payload size, keeping the latest test run per combination
            key = (api_name, payload_size)
            if key not in api_test_runs:
                api_test_runs[key] = test_run
            else:
                # Keep the one with the latest started_at
                if test_run.get('started_at') and api_test_runs[key].get('started_at'):
                    if test_run['started_at'] > api_test_runs[key]['started_at']:
                        api_test_runs[key] = test_run
        
        # Collect all unique payload sizes and calculate total duration
        unique_payload_sizes = set()
        total_duration_seconds = 0.0
        
        for api in apis:
            api_name = api['name']
            
            # Find all test runs for this API (across all payload sizes)
            for (test_api_name, payload_size), test_run in api_test_runs.items():
                if test_api_name != api_name:
                    continue
                
                if test_run and test_run.get('id'):
                    # Track unique payload sizes
                    unique_payload_sizes.add(payload_size)
                    
                    # Get performance metrics from database
                    test_run_id = test_run['id']
                    p95_db = test_run.get('p95_response_time_ms')
                    p99_db = test_run.get('p99_response_time_ms')
                    
                    # Try to get P95/P99 from JSON file if missing from database
                    p95_response = None
                    p99_response = None
                    if p95_db is not None:
                        p95_response = float(p95_db)
                    if p99_db is not None:
                        p99_response = float(p99_db)
                    
                    # If P95/P99 are missing, try to extract from JSON file
                    if (p95_response is None or p99_response is None) and test_run.get('k6_json_file_path'):
                        json_path = Path(test_run['k6_json_file_path'])
                        if json_path.exists():
                            try:
                                json_metrics = extract_metrics_from_json(str(json_path))
                                if json_metrics:
                                    if p95_response is None:
                                        p95_response = json_metrics.get('p95_response', 0) or None
                                    if p99_response is None:
                                        p99_response = json_metrics.get('p99_response', 0) or None
                            except:
                                pass
                    
                    metrics = {
                        'total_samples': test_run.get('total_samples', 0) or 0,
                        'success_samples': test_run.get('success_samples', 0) or 0,
                        'error_samples': test_run.get('error_samples', 0) or 0,
                        'duration_seconds': 0.0,  # Will calculate from timestamps if needed
                        'throughput': float(test_run.get('throughput_req_per_sec', 0) or 0),
                        'avg_response': float(test_run.get('avg_response_time_ms', 0) or 0),
                        'min_response': float(test_run.get('min_response_time_ms', 0) or 0),
                        'max_response': float(test_run.get('max_response_time_ms', 0) or 0),
                        'p95_response': p95_response if p95_response is not None else 0.0,
                        'p99_response': p99_response if p99_response is not None else 0.0,
                        'error_rate': float(test_run.get('error_rate_percent', 0) or 0)
                    }
                    
                    # Calculate duration if we have timestamps
                    if test_run.get('started_at') and test_run.get('completed_at'):
                        try:
                            start = test_run['started_at']
                            end = test_run['completed_at']
                            if isinstance(start, str):
                                start = datetime.fromisoformat(start.replace('Z', '+00:00'))
                            if isinstance(end, str):
                                end = datetime.fromisoformat(end.replace('Z', '+00:00'))
                            duration = (end - start).total_seconds()
                            metrics['duration_seconds'] = duration
                            total_duration_seconds += duration
                        except:
                            pass
                    
                    api_results.append({
                        **api, 
                        'status': 'success', 
                        'metrics': metrics, 
                        'test_run_id': test_run_id,
                        'payload_size': payload_size
                    })
        
        # If we got results from database, skip file-based fallback
        if api_results:
            pass  # Continue to resource metrics collection
        else:
            raise Exception("No test runs found in database")
            
    except Exception as e:
        print(f"Warning: Could not load from database ({e}), falling back to JSON files", file=sys.stderr)
        # Fallback to JSON file parsing
        # Try to extract payload size from directory structure or filename
        for api in apis:
            api_dir = results_path / api['name']
            if not api_dir.exists():
                api_results.append({**api, 'status': 'no_results', 'payload_size': 'default'})
                continue
            
            # Check for payload size subdirectories (skip "default")
            payload_dirs = []
            for item in api_dir.iterdir():
                if item.is_dir() and item.name in ['4k', '8k', '32k', '64k']:
                    payload_dirs.append(item)
            
            if payload_dirs:
                # Process each payload size directory
                for payload_dir in payload_dirs:
                    payload_size = payload_dir.name
                    unique_payload_sizes.add(payload_size)
                    
                    # Find JSON file matching timestamp and test mode in this payload directory
                    if timestamp:
                        if test_mode == 'smoke':
                            json_pattern = f"*-throughput-smoke-*-{timestamp}.json"
                            json_pattern2 = f"*-throughput-smoke-{timestamp}.json"
                        elif test_mode == 'saturation':
                            json_pattern = f"*-throughput-saturation-*-{timestamp}.json"
                            json_pattern2 = f"*-throughput-saturation-{timestamp}.json"
                        else:
                            json_pattern = f"*-throughput-*-{timestamp}.json"
                            json_pattern2 = f"*-throughput-{timestamp}.json"
                        
                        json_files = list(payload_dir.rglob(json_pattern))
                        json_files.extend(list(payload_dir.rglob(json_pattern2)))
                    else:
                        json_files = list(payload_dir.rglob("*-throughput-*.json"))
                    
                    if not json_files:
                        continue
                    
                    latest_json = json_files[0] if timestamp else max(json_files, key=lambda p: p.stat().st_mtime)
                    metrics = extract_metrics_from_json(latest_json)
                    
                    if metrics:
                        total_duration_seconds += metrics.get('duration_seconds', 0.0)
                        api_results.append({
                            **api, 
                            'status': 'success', 
                            'metrics': metrics, 
                            'json_file': latest_json.name,
                            'payload_size': payload_size
                        })
            else:
                # No payload subdirectories, look for JSON files directly
                # Find JSON file matching timestamp and test mode
                if timestamp:
                    if test_mode == 'smoke':
                        json_pattern = f"*-throughput-smoke-*-{timestamp}.json"
                        json_pattern2 = f"*-throughput-smoke-{timestamp}.json"
                    elif test_mode == 'saturation':
                        json_pattern = f"*-throughput-saturation-*-{timestamp}.json"
                        json_pattern2 = f"*-throughput-saturation-{timestamp}.json"
                    else:
                        json_pattern = f"*-throughput-*-{timestamp}.json"
                        json_pattern2 = f"*-throughput-{timestamp}.json"
                    
                    json_files = list(api_dir.rglob(json_pattern))
                    json_files.extend(list(api_dir.rglob(json_pattern2)))
                else:
                    json_files = list(api_dir.rglob("*-throughput-*.json"))
                
                if not json_files:
                    # Skip if no JSON files found (don't add default payload)
                    continue
                
                latest_json = json_files[0] if timestamp else max(json_files, key=lambda p: p.stat().st_mtime)
                metrics = extract_metrics_from_json(latest_json)
                
                if metrics:
                    # Skip default payload - we only want explicit payload sizes
                    # This code path is for when there's no payload subdirectory, so skip it
                    continue
                else:
                    # Skip parse errors for default payload
                    continue
    
    # Collect validation warnings
    all_warnings = []
    for api in api_results:
        if api.get('status') == 'success' and 'metrics' in api:
            warnings = validate_metrics(api['metrics'])
            if warnings:
                all_warnings.extend([f"{api['display']}: {w}" for w in warnings])
    
    # Generate HTML
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Performance Test Report - {test_mode.upper()}</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f5f5;
            padding: 40px 20px;
            color: #333;
            line-height: 1.6;
        }}
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
            padding: 40px;
        }}
        h1 {{
            color: #1a1a1a;
            font-size: 28px;
            font-weight: 600;
            margin-bottom: 10px;
            padding-bottom: 15px;
            border-bottom: 1px solid #e0e0e0;
        }}
        h2 {{
            color: #1a1a1a;
            font-size: 22px;
            font-weight: 600;
            margin-top: 40px;
            margin-bottom: 20px;
        }}
        .header-info {{
            background: #fafafa;
            padding: 20px;
            border-radius: 6px;
            margin-bottom: 30px;
            border: 1px solid #e8e8e8;
        }}
        .header-info p {{
            margin: 6px 0;
            color: #666;
            font-size: 14px;
        }}
        .header-info strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
            font-size: 14px;
            background: white;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }}
        th {{
            background: #2c3e50;
            color: #ffffff;
            padding: 14px 16px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #34495e;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
            position: sticky;
            top: 0;
            z-index: 10;
        }}
        th.text-right {{
            text-align: right;
        }}
        td strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        td {{
            padding: 12px 16px;
            border-bottom: 1px solid #e8e8e8;
            color: #333;
        }}
        td.text-right {{
            text-align: right;
            font-family: 'Courier New', monospace;
        }}
        tbody tr:nth-child(even) {{
            background: #f8f9fa;
        }}
        tbody tr:hover {{
            background: #e8f4f8;
        }}
        tbody tr:last-child td {{
            border-bottom: none;
        }}
        .status-success {{
            color: #22c55e;
            font-weight: 600;
        }}
        .status-error {{
            color: #ef4444;
            font-weight: 600;
        }}
        .status-warning {{
            color: #f59e0b;
            font-weight: 600;
        }}
        .comparison-section {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .comparison-section h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .insight-box {{
            background: white;
            padding: 16px;
            margin: 12px 0;
            border-radius: 4px;
            border: 1px solid #e8e8e8;
        }}
        .insight-box h4 {{
            color: #1a1a1a;
            font-size: 15px;
            font-weight: 600;
            margin-bottom: 8px;
            margin-top: 0;
        }}
        .insight-box p {{
            margin: 6px 0;
            color: #555;
            font-size: 14px;
            line-height: 1.6;
        }}
        .ranking-list {{
            list-style: none;
            padding: 0;
            margin: 0;
        }}
        .ranking-list li {{
            padding: 10px 0;
            border-bottom: 1px solid #f0f0f0;
            color: #555;
            font-size: 14px;
        }}
        .ranking-list li:last-child {{
            border-bottom: none;
        }}
        .ranking-list li strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        .winner {{
            color: #22c55e;
            font-weight: 600;
        }}
        .api-details {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .api-details h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .api-details table {{
            margin: 10px 0;
        }}
        .footer {{
            margin-top: 50px;
            padding-top: 24px;
            border-top: 1px solid #e8e8e8;
            text-align: center;
            color: #999;
            font-size: 13px;
        }}
        .data-table-container {{
            margin: 20px 0;
            padding: 20px;
            background: white;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
            overflow-x: auto;
        }}
        .data-table-container h4 {{
            color: #1a1a1a;
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
        }}
        .data-table-container table {{
            margin: 0;
        }}
        @media (max-width: 768px) {{
            .data-table-container {{
                overflow-x: scroll;
            }}
            table {{
                min-width: 600px;
            }}
        }}
        .resource-section {{
            margin: 30px 0;
            padding: 24px;
            background: #fafafa;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .resource-section h3 {{
            color: #1a1a1a;
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 20px;
            margin-top: 0;
        }}
        .warning-box {{
            background: #fff3cd;
            border: 1px solid #ffc107;
            border-radius: 6px;
            padding: 16px;
            margin: 20px 0;
            color: #856404;
        }}
        .warning-box h4 {{
            color: #856404;
            margin-top: 0;
            margin-bottom: 8px;
        }}
        .warning-box ul {{
            margin: 8px 0;
            padding-left: 20px;
        }}
        .export-buttons {{
            margin: 20px 0;
            text-align: right;
        }}
        .export-button {{
            background: #007bff;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            margin-left: 10px;
        }}
        .export-button:hover {{
            background: #0056b3;
        }}
        .statistics-box {{
            background: #e7f3ff;
            border: 1px solid #b3d9ff;
            border-radius: 6px;
            padding: 16px;
            margin: 12px 0;
        }}
        .statistics-box h4 {{
            color: #004085;
            margin-top: 0;
            margin-bottom: 8px;
        }}
        .statistics-box p {{
            margin: 4px 0;
            color: #004085;
            font-size: 13px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 API Performance Test Report</h1>
        
        <div class="header-info">
            <p><strong>Test Mode:</strong> {test_mode.upper()}</p>
            <p><strong>Test Date:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p><strong>Test Type:</strong> Sequential (one API at a time)</p>
            <p><strong>Total APIs Tested:</strong> {len([r for r in api_results if r.get('status') == 'success'])}</p>
            <p><strong>Test Duration:</strong> {format_duration(total_duration_seconds)}</p>
            <p><strong>Payload Sizes Tested:</strong> {format_payload_sizes_list(unique_payload_sizes)}</p>
        </div>
        
        <h2>📊 Summary</h2>
        <div class="export-buttons">
            <button class="export-button" onclick="exportTableToCSV('executive-summary-table', 'executive-summary.csv')">Export to CSV</button>
            <button class="export-button" onclick="exportDataToJSON('report-data.json')">Export to JSON</button>
        </div>
        <table id="executive-summary-table">
            <thead>
                <tr>
                    <th>API</th>
                    <th>Protocol</th>
                    <th>Payload Size</th>
                    <th>Status</th>
                    <th>Total Requests</th>
                    <th class="text-right">Success Rate (%)</th>
                    <th>Throughput (req/s)</th>
                    <th>Avg Response (ms)</th>
                    <th>Min (ms)</th>
                    <th>Max (ms)</th>
                    <th>P95 (ms)</th>
                </tr>
            </thead>
            <tbody>
"""
    
    # Add table rows
    for api in api_results:
        if api.get('status') == 'success' and 'metrics' in api:
            m = api['metrics']
            status_class = 'status-success' if m['error_rate'] < 1 else 'status-warning' if m['error_rate'] < 5 else 'status-error'
            status_text = '✅ PASS' if m['error_rate'] < 1 else '⚠️ WARN' if m['error_rate'] < 5 else '❌ FAIL'
            payload_size = api.get('payload_size', 'default')
            p95_display = f"{m['p95_response']:.2f}" if m.get('p95_response') and m['p95_response'] > 0 else "-"
            # Calculate success rate
            success_rate = ((m['success_samples'] / m['total_samples']) * 100) if m['total_samples'] > 0 else 0.0
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td>{payload_size}</td>
                    <td class="{status_class}">{status_text}</td>
                    <td>{m['total_samples']}</td>
                    <td class="text-right">{success_rate:.2f}%</td>
                    <td><strong>{m['throughput']:.2f}</strong></td>
                    <td>{m['avg_response']:.2f}</td>
                    <td>{m['min_response']:.2f}</td>
                    <td>{m['max_response']:.2f}</td>
                    <td>{p95_display}</td>
                </tr>
"""
        else:
            status_text = '❌ No Results' if api.get('status') == 'no_results' else '❌ No JSON' if api.get('status') == 'no_json' else '❌ Parse Error'
            payload_size = api.get('payload_size', 'default')
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td>{payload_size}</td>
                    <td class="status-error">{status_text}</td>
                    <td>-</td>
                    <td class="text-right">-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                </tr>
"""
    
    html_content += """
            </tbody>
        </table>
"""
    
    # Generate comparison analysis
    successful_apis = [api for api in api_results if api.get('status') == 'success' and 'metrics' in api]
    
    if successful_apis:
        # Find winners
        highest_throughput = max(successful_apis, key=lambda x: x['metrics']['throughput'])
        lowest_latency = min(successful_apis, key=lambda x: x['metrics']['avg_response'])
        lowest_error = min(successful_apis, key=lambda x: x['metrics']['error_rate'])
        
        # Group by protocol
        rest_apis = [api for api in successful_apis if api['protocol'] == 'REST']
        grpc_apis = [api for api in successful_apis if api['protocol'] == 'gRPC']
        
        # Group by language
        java_apis = [api for api in successful_apis if 'Java' in api['display']]
        rust_apis = [api for api in successful_apis if 'Rust' in api['display']]
        go_apis = [api for api in successful_apis if 'Go' in api['display']]
        
        # Calculate averages
        def avg_metric(apis, metric_key):
            if not apis:
                return 0.0
            return sum(api['metrics'][metric_key] for api in apis) / len(apis)
        
        rest_avg_throughput = avg_metric(rest_apis, 'throughput')
        grpc_avg_throughput = avg_metric(grpc_apis, 'throughput')
        rest_avg_latency = avg_metric(rest_apis, 'avg_response')
        grpc_avg_latency = avg_metric(grpc_apis, 'avg_response')
        
        java_avg_throughput = avg_metric(java_apis, 'throughput')
        rust_avg_throughput = avg_metric(rust_apis, 'throughput')
        go_avg_throughput = avg_metric(go_apis, 'throughput')
        java_avg_latency = avg_metric(java_apis, 'avg_response')
        rust_avg_latency = avg_metric(rust_apis, 'avg_response')
        go_avg_latency = avg_metric(go_apis, 'avg_response')
        
        # Calculate statistical measures for throughput and latency
        throughput_values = [api['metrics']['throughput'] for api in successful_apis]
        latency_values = [api['metrics']['avg_response'] for api in successful_apis]
        throughput_stats = calculate_statistics(throughput_values) if len(throughput_values) > 1 else None
        latency_stats = calculate_statistics(latency_values) if len(latency_values) > 1 else None
        
        html_content += f"""
        <h2>📊 Comparison Analysis</h2>
        
        {f'''
        <div class="statistics-box">
            <h4>📈 Statistical Analysis</h4>
            {f'''
            <p><strong>Throughput Statistics:</strong> Mean: {throughput_stats['mean']:.2f} req/s, 
            Std Dev: {throughput_stats['std_dev']:.2f} req/s, 
            CV: {throughput_stats['cv']:.1f}%, 
            95% CI: [{throughput_stats['ci_lower']:.2f}, {throughput_stats['ci_upper']:.2f}] req/s</p>
            ''' if throughput_stats else ''}
            {f'''
            <p><strong>Latency Statistics:</strong> Mean: {latency_stats['mean']:.2f} ms, 
            Std Dev: {latency_stats['std_dev']:.2f} ms, 
            CV: {latency_stats['cv']:.1f}%, 
            95% CI: [{latency_stats['ci_lower']:.2f}, {latency_stats['ci_upper']:.2f}] ms</p>
            ''' if latency_stats else ''}
            <p><em>CV = Coefficient of Variation (lower is better, indicates consistency)</em></p>
        </div>
        ''' if (throughput_stats or latency_stats) else ''}
        
        <div class="comparison-section">
            <h3>Performance Rankings</h3>
            <ul class="ranking-list">
                <li><strong>Highest Throughput:</strong> <span class="winner">{highest_throughput['display']}</span> with {highest_throughput['metrics']['throughput']:.2f} req/s</li>
                <li><strong>Lowest Latency:</strong> <span class="winner">{lowest_latency['display']}</span> with {lowest_latency['metrics']['avg_response']:.2f} ms average response time</li>
                <li><strong>Most Reliable:</strong> <span class="winner">{lowest_error['display']}</span> with {lowest_error['metrics']['error_rate']:.2f}% error rate</li>
            </ul>
        </div>
        
        <div class="comparison-section">
            <h3>Protocol Comparison</h3>
            <div class="insight-box">
                <h4>REST vs gRPC</h4>
                <p><strong>Throughput:</strong> REST APIs average {rest_avg_throughput:.2f} req/s, gRPC APIs average {grpc_avg_throughput:.2f} req/s</p>
                <p><strong>Latency:</strong> REST APIs average {rest_avg_latency:.2f} ms, gRPC APIs average {grpc_avg_latency:.2f} ms</p>
"""
        
        if rest_avg_throughput > 0 and grpc_avg_throughput > 0:
            throughput_diff = ((grpc_avg_throughput - rest_avg_throughput) / rest_avg_throughput) * 100
            latency_diff = ((rest_avg_latency - grpc_avg_latency) / rest_avg_latency) * 100 if rest_avg_latency > 0 else 0
            html_content += f"""
                <p><strong>Analysis:</strong> gRPC shows {abs(throughput_diff):.1f}% {'higher' if throughput_diff > 0 else 'lower'} throughput and {abs(latency_diff):.1f}% {'lower' if latency_diff > 0 else 'higher'} latency compared to REST</p>
"""
        
        html_content += """
            </div>
        </div>
        
        <div class="comparison-section">
            <h3>Language Comparison</h3>
            <div class="insight-box">
                <h4>Java vs Rust vs Go</h4>
"""
        
        html_content += f"""
                <p><strong>Throughput:</strong> Java ({java_avg_throughput:.2f} req/s), Rust ({rust_avg_throughput:.2f} req/s), Go ({go_avg_throughput:.2f} req/s)</p>
                <p><strong>Latency:</strong> Java ({java_avg_latency:.2f} ms), Rust ({rust_avg_latency:.2f} ms), Go ({go_avg_latency:.2f} ms)</p>
"""
        
        # Find language winners
        lang_throughput_winner = max([('Java', java_avg_throughput), ('Rust', rust_avg_throughput), ('Go', go_avg_throughput)], key=lambda x: x[1])
        lang_latency_winner = min([('Java', java_avg_latency), ('Rust', rust_avg_latency), ('Go', go_avg_latency)], key=lambda x: x[1])
        
        html_content += f"""
                <p><strong>Best Throughput:</strong> <span class="winner">{lang_throughput_winner[0]}</span> ({lang_throughput_winner[1]:.2f} req/s)</p>
                <p><strong>Best Latency:</strong> <span class="winner">{lang_latency_winner[0]}</span> ({lang_latency_winner[1]:.2f} ms)</p>
"""
        
        html_content += """
            </div>
        </div>
        
        <div class="comparison-section">
            <h3>Key Insights</h3>
"""
        
        # Generate key insights
        if len(successful_apis) > 1:
            throughput_values = [api['metrics']['throughput'] for api in successful_apis]
            latency_values = [api['metrics']['avg_response'] for api in successful_apis]
            
            if throughput_values:
                max_throughput = max(throughput_values)
                min_throughput = min(throughput_values)
                if max_throughput > 0:
                    throughput_variation = ((max_throughput - min_throughput) / max_throughput) * 100
                    html_content += f"""
            <div class="insight-box">
                <p>Significant throughput variation ({throughput_variation:.1f}%) across APIs, indicating performance differences</p>
            </div>
"""
            
            if latency_values:
                max_latency = max(latency_values)
                min_latency = min(latency_values)
                fastest_api = min(successful_apis, key=lambda x: x['metrics']['avg_response'])
                slowest_api = max(successful_apis, key=lambda x: x['metrics']['avg_response'])
                if max_latency > 0:
                    if min_latency > 0:
                        latency_diff = ((max_latency - min_latency) / min_latency) * 100
                    else:
                        latency_diff = 0.0
                    html_content += f"""
            <div class="insight-box">
                <p>{fastest_api['display']} is {latency_diff:.1f}% faster than {slowest_api['display']} in terms of average latency</p>
            </div>
"""
            
            # Check error rates
            all_zero_errors = all(api['metrics']['error_rate'] < 0.01 for api in successful_apis)
            if all_zero_errors:
                html_content += """
            <div class="insight-box">
                <p>All APIs achieved 0% error rate, demonstrating excellent reliability</p>
            </div>
"""
            
            # Protocol insight
            if rest_apis and grpc_apis:
                if rest_avg_throughput > grpc_avg_throughput:
                    html_content += """
            <div class="insight-box">
                <p>REST shows higher throughput, making it better for high-volume scenarios</p>
            </div>
"""
        
        html_content += """
        </div>
        
        <div class="comparison-section">
            <h3>Recommendations</h3>
            <div class="insight-box">
                <ul class="ranking-list">
"""
        
        # Generate recommendations
        html_content += f"""
                    <li><strong>For Maximum Throughput:</strong> Choose <span class="winner">{highest_throughput['display']}</span> ({highest_throughput['metrics']['throughput']:.2f} req/s)</li>
"""
        
        html_content += f"""
                    <li><strong>For Lowest Latency:</strong> Choose <span class="winner">{lowest_latency['display']}</span> ({lowest_latency['metrics']['avg_response']:.2f} ms average)</li>
"""
        
        # Reliability recommendation
        if all(api['metrics']['error_rate'] < 0.01 for api in successful_apis):
            html_content += """
                    <li><strong>For Reliability:</strong> All APIs show 0% error rate - excellent reliability across the board</li>
"""
        else:
            html_content += f"""
                    <li><strong>For Reliability:</strong> Choose <span class="winner">{lowest_error['display']}</span> ({lowest_error['metrics']['error_rate']:.2f}% error rate)</li>
"""
        
        html_content += """
                </ul>
            </div>
        </div>
        
        <div class="comparison-section">
            <h3>📈 Performance Comparison Tables</h3>
"""
        
        # Organize performance data by API and payload size
        performance_data_by_api = {}
        all_payload_sizes = set()
        api_order = [
            'producer-api-java-rest',
            'producer-api-java-grpc',
            'producer-api-rust-rest',
            'producer-api-rust-grpc',
            'producer-api-go-rest',
            'producer-api-go-grpc'
        ]
        
        for api in api_results:
            if api.get('status') == 'success' and 'metrics' in api:
                api_name = api['name']
                payload_size = api.get('payload_size', 'default')
                
                # Skip default payload size
                if payload_size and payload_size.lower() != 'default':
                    if api_name not in performance_data_by_api:
                        performance_data_by_api[api_name] = {
                            'display': api['display'],
                            'data': {}
                        }
                    all_payload_sizes.add(payload_size)
                    performance_data_by_api[api_name]['data'][payload_size] = {
                        'throughput': api['metrics'].get('throughput', 0),
                        'avg_response': api['metrics'].get('avg_response', 0),
                        'error_rate': api['metrics'].get('error_rate', 0),
                        'p95_response': api['metrics'].get('p95_response', 0)
                    }
        
        # Sort payload sizes
        payload_size_order = ['4k', '8k', '32k', '64k']
        sorted_payload_sizes = sorted(
            [s for s in all_payload_sizes if s and s.lower() != 'default'],
            key=lambda x: (payload_size_order.index(x) if x in payload_size_order else 999, x)
        )
        
        # Generate tables for each metric
        if sorted_payload_sizes and performance_data_by_api:
            # Throughput table
            html_content += """
            <div class="resource-section">
                <h4>Throughput Comparison (req/s) - Higher is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
"""
            for size in sorted_payload_sizes:
                html_content += f'<th class="text-right">{size.upper()}</th>'
            html_content += """
                            </tr>
                        </thead>
                        <tbody>
"""
            for api_name in api_order:
                if api_name in performance_data_by_api:
                    api_info = performance_data_by_api[api_name]
                    html_content += f'<tr><td><strong>{api_info["display"]}</strong></td>'
                    for size in sorted_payload_sizes:
                        value = api_info['data'].get(size, {}).get('throughput', None)
                        if value is not None and value > 0:
                            html_content += f'<td class="text-right">{value:.2f}</td>'
                        else:
                            html_content += '<td class="text-right">-</td>'
                    html_content += '</tr>'
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Average Response Time Comparison (ms) - Lower is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
"""
            for size in sorted_payload_sizes:
                html_content += f'<th class="text-right">{size.upper()}</th>'
            html_content += """
                            </tr>
                        </thead>
                        <tbody>
"""
            for api_name in api_order:
                if api_name in performance_data_by_api:
                    api_info = performance_data_by_api[api_name]
                    html_content += f'<tr><td><strong>{api_info["display"]}</strong></td>'
                    for size in sorted_payload_sizes:
                        value = api_info['data'].get(size, {}).get('avg_response', None)
                        if value is not None and value > 0:
                            html_content += f'<td class="text-right">{value:.2f}</td>'
                        else:
                            html_content += '<td class="text-right">-</td>'
                    html_content += '</tr>'
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Error Rate Comparison (%) - Lower is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
"""
            for size in sorted_payload_sizes:
                html_content += f'<th class="text-right">{size.upper()}</th>'
            html_content += """
                            </tr>
                        </thead>
                        <tbody>
"""
            for api_name in api_order:
                if api_name in performance_data_by_api:
                    api_info = performance_data_by_api[api_name]
                    html_content += f'<tr><td><strong>{api_info["display"]}</strong></td>'
                    for size in sorted_payload_sizes:
                        value = api_info['data'].get(size, {}).get('error_rate', None)
                        if value is not None:
                            html_content += f'<td class="text-right">{value:.2f}</td>'
                        else:
                            html_content += '<td class="text-right">-</td>'
                    html_content += '</tr>'
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>P95 Response Time Comparison (ms) - Lower is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
"""
            for size in sorted_payload_sizes:
                html_content += f'<th class="text-right">{size.upper()}</th>'
            html_content += """
                            </tr>
                        </thead>
                        <tbody>
"""
            for api_name in api_order:
                if api_name in performance_data_by_api:
                    api_info = performance_data_by_api[api_name]
                    html_content += f'<tr><td><strong>{api_info["display"]}</strong></td>'
                    for size in sorted_payload_sizes:
                        value = api_info['data'].get(size, {}).get('p95_response', None)
                        if value is not None and value > 0:
                            html_content += f'<td class="text-right">{value:.2f}</td>'
                        else:
                            html_content += '<td class="text-right">-</td>'
                    html_content += '</tr>'
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
"""
        else:
            html_content += """
            <div class="insight-box">
                <p>No performance comparison data available. Please ensure test results include payload size information.</p>
            </div>
        </div>
"""
    
    # Load resource metrics from database for all APIs
    resource_data = {}
    
    try:
        script_dir = Path(__file__).parent
        sys.path.insert(0, str(script_dir))
        from db_client import get_resource_metrics_summary
        
        # Get resource metrics from database for each API's test run
        for api_result in api_results:
            if api_result.get('status') != 'success':
                continue
            
            api_name = api_result['name']
            test_run_id = api_result.get('test_run_id')
            
            if test_run_id:
                try:
                    # Get resource metrics summary directly from database
                    resource_summary = get_resource_metrics_summary(test_run_id)
                    
                    if resource_summary and resource_summary.get('sample_count', 0) > 0:
                        # Format resource data in the same structure as analyze-resource-metrics.py
                        resource_data[api_name] = {
                            'test_mode': test_mode,
                            'overall': {
                                'avg_cpu_percent': float(resource_summary.get('avg_cpu_percent', 0) or 0),
                                'max_cpu_percent': float(resource_summary.get('max_cpu_percent', 0) or 0),
                                'avg_memory_percent': float(resource_summary.get('avg_memory_percent', 0) or 0),
                                'max_memory_percent': float(resource_summary.get('max_memory_percent', 0) or 0),
                                'avg_memory_mb': float(resource_summary.get('avg_memory_mb', 0) or 0),
                                'max_memory_mb': float(resource_summary.get('max_memory_mb', 0) or 0),
                                'total_samples': int(resource_summary.get('sample_count', 0))
                            },
                            'phases': {}  # Phase data can be added if needed
                        }
                    elif resource_summary and resource_summary.get('sample_count', 0) == 0:
                        # Log warning for missing resource metrics
                        print(f"Warning: No resource metrics collected for {api_name} (test_run_id: {test_run_id})", file=sys.stderr)
                except Exception as e:
                    print(f"Error loading resource metrics from database for {api_name}: {e}", file=sys.stderr)
    except Exception as e:
        print(f"Warning: Could not load resource metrics from database ({e})", file=sys.stderr)
    
    # Calculate AWS EKS costs after resource data is loaded
    # (successful_apis is already defined above)
    if successful_apis:
        try:
            script_dir = Path(__file__).parent
            sys.path.insert(0, str(script_dir))
            from calculate_aws_costs import calculate_cost_for_api
            
            # Load pod configuration
            pod_config = {}
            pod_config_path = script_dir / 'pod_config.json'
            if pod_config_path.exists():
                try:
                    with open(pod_config_path, 'r') as f:
                        pod_config = json.load(f)
                except Exception as e:
                    print(f"Warning: Could not load pod config ({e}), using defaults", file=sys.stderr)
            
            default_config = pod_config.get('default', {
                'num_pods': 1,
                'cpu_cores_per_pod': 1.0,
                'memory_gb_per_pod': 2.0,
                'storage_gb_per_pod': 20.0
            })
            api_configs = pod_config.get('apis', {})
            
            # Calculate costs for each API
            cost_data = []
            for api in successful_apis:
                metrics = api['metrics']
                api_name = api['name']
                
                # Get pod configuration for this API (or use default)
                api_pod_config = api_configs.get(api_name, default_config)
                num_pods = api_pod_config.get('num_pods', default_config['num_pods'])
                cpu_cores_per_pod = api_pod_config.get('cpu_cores_per_pod', default_config['cpu_cores_per_pod'])
                storage_gb_per_pod = api_pod_config.get('storage_gb_per_pod', default_config['storage_gb_per_pod'])
                
                # Get resource metrics if available
                avg_cpu = 0.0
                avg_memory_mb = 0.0
                memory_limit_mb = 2048.0  # Default 2GB limit
                
                if api_name in resource_data:
                    overall = resource_data[api_name].get('overall', {})
                    avg_cpu = overall.get('avg_cpu_percent', 0.0)
                    avg_memory_mb = overall.get('avg_memory_mb', 0.0)
                    memory_limit_mb = overall.get('max_memory_mb', 2048.0) or 2048.0
                
                # Debug: Check if resource data is missing
                if avg_cpu == 0.0 and avg_memory_mb == 0.0:
                    # Resource metrics might not be available - this is common for smoke tests
                    # or when metrics collection failed. Efficiency will show 0% in this case.
                    pass
                
                # Use configured memory per pod, or calculate from limit
                memory_gb_per_pod = api_pod_config.get('memory_gb_per_pod')
                if memory_gb_per_pod is None:
                    memory_gb_per_pod = memory_limit_mb / 1024.0
                
                # Estimate data transfer (rough estimate: 1KB per request)
                # Ensure minimum value to avoid zero costs
                data_transfer_gb = max((metrics['total_samples'] * 0.001) / 1024.0, 0.000001)
                
                # Calculate costs with pod configuration
                costs = calculate_cost_for_api(
                    api_name=api_name,
                    duration_seconds=metrics.get('duration_seconds', 0.0),
                    total_requests=metrics['total_samples'],
                    avg_cpu_percent=avg_cpu,
                    avg_memory_mb=avg_memory_mb,
                    memory_limit_mb=memory_limit_mb,
                    data_transfer_gb=data_transfer_gb,
                    num_pods=num_pods,
                    cpu_cores_per_pod=cpu_cores_per_pod,
                    memory_gb_per_pod=memory_gb_per_pod,
                    storage_gb_per_pod=storage_gb_per_pod
                )
                
                cost_data.append({
                    'api_name': api_name,
                    'display': api['display'],
                    'payload_size': api.get('payload_size', 'default'),
                    **costs
                })
            
            # Generate cost analytics section
            html_content += """
        <div class="comparison-section">
            <h2>💰 AWS EKS Cost Analytics</h2>
            <div class="insight-box">
                <p><strong>Cost Model:</strong> AWS EKS with EC2 instances (auto-selected based on pod requirements), Application Load Balancer, EBS storage, and data transfer costs. Costs are estimated based on actual resource utilization during tests.</p>
                <p><strong>Note:</strong> These are estimated costs for running on AWS EKS. Actual costs may vary based on instance types, regions, reserved instances, and other factors.</p>
            </div>
            
            <!-- Summary section with Pods, Pod Size, Instance Type, Instances -->
            <div style="margin-bottom: 20px; padding: 15px; background-color: #e7f3ff; border-left: 4px solid #0056b3; border-radius: 4px;">
                <h4 style="margin-top: 0; margin-bottom: 12px; color: #004085;">Infrastructure Configuration Summary</h4>
                <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; font-size: 13px;">
"""
            
            # Get shared infrastructure configuration (all APIs use the same config)
            if cost_data:
                first_cost_info = cost_data[0]
                pod_size = f"{first_cost_info['cpu_cores_per_pod']:.1f} CPU, {first_cost_info['memory_gb_per_pod']:.1f}GB RAM"
                html_content += f"""
                    <div style="padding: 15px; background: white; border-radius: 4px; border: 1px solid #b3d9ff;">
                        <div style="color: #333; line-height: 1.8; display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px;">
                            <div><strong style="color: #004085;">Pods per API:</strong> {first_cost_info['num_pods']}</div>
                            <div><strong style="color: #004085;">Pod Size:</strong> {pod_size}</div>
                            <div><strong style="color: #004085;">Instance Type:</strong> {first_cost_info['instance_type']}</div>
                            <div><strong style="color: #004085;">Instances Needed:</strong> {first_cost_info['instances_needed']}</div>
                        </div>
                        <p style="margin-top: 12px; margin-bottom: 0; color: #666; font-size: 12px; font-style: italic;">Note: All APIs use the same infrastructure configuration for fair comparison.</p>
                    </div>
"""
            
            html_content += """
                </div>
            </div>
            
            <table style="width: 100%; table-layout: auto;">
                <thead>
                    <tr>
                        <th style="text-align: left;">API</th>
                        <th style="text-align: right;">Total Cost ($)</th>
                        <th style="text-align: right;">Cost/1K Requests ($)</th>
                        <th style="text-align: right;">Instance Cost ($)</th>
                        <th style="text-align: right;">Cluster Cost ($)</th>
                        <th style="text-align: right;">ALB Cost ($)</th>
                        <th style="text-align: right;">Storage Cost ($)</th>
                        <th style="text-align: right;">Network Cost ($)</th>
                        <th style="text-align: right;">CPU Efficiency</th>
                        <th style="text-align: right;">Memory Efficiency</th>
                    </tr>
                </thead>
                <tbody>
"""
            
            for cost_info in cost_data:
                # Format costs as dollar-cent amounts rounded to 6 decimal places
                def format_cost(cost):
                    # Round to 6 decimal places and format as currency
                    # Ensure minimum display value to avoid showing zero (must be >= 0.000001 to show 6 decimals)
                    rounded = round(max(cost, 0.000001), 6)
                    return f"${rounded:.6f}"
                
                # Format efficiency percentages
                def format_percentage(value):
                    if value == 0.0:
                        return "0.0%"
                    elif value < 0.1:
                        return f"{value:.2f}%"
                    else:
                        return f"{value:.1f}%"
                
                # Format pod size
                pod_size = f"{cost_info['cpu_cores_per_pod']:.1f} CPU, {cost_info['memory_gb_per_pod']:.1f}GB RAM"
                
                # Ensure all cost values are non-zero (use 0.000001 minimum to show 6 decimals)
                instance_cost_val = cost_info.get('instance_effective_cost')
                instance_cost = max(instance_cost_val if instance_cost_val is not None else 0, 0.000001)
                
                cluster_cost_val = cost_info.get('cluster_cost')
                cluster_cost = max(cluster_cost_val if cluster_cost_val is not None else 0, 0.000001)
                
                alb_cost_val = cost_info.get('alb_cost')
                alb_cost = max(alb_cost_val if alb_cost_val is not None else 0, 0.000001)
                
                storage_cost_val = cost_info.get('storage_cost')
                storage_cost = max(storage_cost_val if storage_cost_val is not None else 0, 0.000001)
                
                network_cost_val = cost_info.get('network_cost')
                network_cost = max(network_cost_val if network_cost_val is not None else 0, 0.000001)
                
                html_content += f"""
                    <tr>
                        <td><strong>{cost_info['display']}</strong></td>
                        <td style="text-align: right;">{format_cost(cost_info['total_cost'])}</td>
                        <td style="text-align: right;">{format_cost(cost_info['cost_per_1000_requests'])}</td>
                        <td style="text-align: right;">{format_cost(instance_cost)}</td>
                        <td style="text-align: right;">{format_cost(cluster_cost)}</td>
                        <td style="text-align: right;">{format_cost(alb_cost)}</td>
                        <td style="text-align: right;">{format_cost(storage_cost)}</td>
                        <td style="text-align: right;">{format_cost(network_cost)}</td>
                        <td style="text-align: right;">{format_percentage(cost_info['cpu_efficiency']*100)}</td>
                        <td style="text-align: right;">{format_percentage(cost_info['memory_efficiency']*100)}</td>
                    </tr>
"""
            
            html_content += """
                </tbody>
            </table>
            
            <p style="margin-top: 15px; color: #666; font-size: 12px; font-style: italic;">
                <strong>Note on Efficiency:</strong> CPU and Memory efficiency are calculated based on actual resource utilization during the test. 
                <ul style="margin: 8px 0; padding-left: 20px;">
                    <li><strong>CPU Efficiency:</strong> Represents the percentage of allocated CPU cores actually used. Low CPU efficiency (e.g., 0.1%) is common in smoke tests because:
                        <ul style="margin: 4px 0; padding-left: 20px;">
                            <li>Short test duration means CPU spikes are averaged down</li>
                            <li>APIs are idle most of the time between requests</li>
                            <li>Modern CPUs are very fast, so processing 5 requests takes minimal CPU time</li>
                        </ul>
                    </li>
                    <li><strong>Memory Efficiency:</strong> Represents the percentage of allocated memory actually used. Memory efficiency is typically higher because:
                        <ul style="margin: 4px 0; padding-left: 20px;">
                            <li>Memory is allocated when the application starts and stays allocated</li>
                            <li>Even idle applications consume memory for runtime, libraries, and buffers</li>
                            <li>Memory doesn't spike and drop like CPU - it remains relatively constant</li>
                        </ul>
                    </li>
                    <li>If efficiency shows 0%, it means resource metrics were not collected. For accurate efficiency metrics, run longer tests (full or saturation mode) with resource monitoring enabled.</li>
                </ul>
            </p>
            
            <p style="margin-top: 10px; color: #666; font-size: 12px; font-style: italic;">
                <strong>Note on Pricing:</strong> All costs are estimated based on AWS us-east-1 on-demand pricing as of 2024. 
                Actual costs may vary based on instance types, regions, reserved instances, spot instances, and other factors. 
                These estimates assume a single EKS cluster shared across all APIs.
            </p>
            
            <p style="margin-top: 10px; color: #666; font-size: 12px; font-style: italic;">
                <strong>Column Definitions:</strong> For detailed explanations of all cost analytics columns, see <code>load-test/README.md</code>.
            </p>
            
            <div class="resource-section">
                <h4>Total Cost Comparison - Lower is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
                                <th>Payload Size</th>
                                <th class="text-right">Total Cost ($)</th>
                            </tr>
                        </thead>
                        <tbody>
"""
            for cost_info in cost_data:
                payload_display = format_payload_size(cost_info.get('payload_size', 'default'))
                html_content += f"""
                            <tr>
                                <td><strong>{cost_info['display']}</strong></td>
                                <td>{payload_display}</td>
                                <td class="text-right">{format_cost(cost_info['total_cost'])}</td>
                            </tr>
"""
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Cost per 1,000 Requests Comparison - Lower is Better</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
                                <th>Payload Size</th>
                                <th class="text-right">Cost per 1K Requests ($)</th>
                            </tr>
                        </thead>
                        <tbody>
"""
            for cost_info in cost_data:
                payload_display = format_payload_size(cost_info.get('payload_size', 'default'))
                html_content += f"""
                            <tr>
                                <td><strong>{cost_info['display']}</strong></td>
                                <td>{payload_display}</td>
                                <td class="text-right">{format_cost(cost_info['cost_per_1000_requests'])}</td>
                            </tr>
"""
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Cost Breakdown by Component</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
                                <th>Payload Size</th>
                                <th class="text-right">Instance ($)</th>
                                <th class="text-right">Cluster ($)</th>
                                <th class="text-right">ALB ($)</th>
                                <th class="text-right">Storage ($)</th>
                                <th class="text-right">Network ($)</th>
                            </tr>
                        </thead>
                        <tbody>
"""
            for cost_info in cost_data:
                payload_display = format_payload_size(cost_info.get('payload_size', 'default'))
                instance_cost_val = cost_info.get('instance_effective_cost')
                instance_cost = max(instance_cost_val if instance_cost_val is not None else 0, 0.000001)
                cluster_cost_val = cost_info.get('cluster_cost')
                cluster_cost = max(cluster_cost_val if cluster_cost_val is not None else 0, 0.000001)
                alb_cost_val = cost_info.get('alb_cost')
                alb_cost = max(alb_cost_val if alb_cost_val is not None else 0, 0.000001)
                storage_cost_val = cost_info.get('storage_cost')
                storage_cost = max(storage_cost_val if storage_cost_val is not None else 0, 0.000001)
                network_cost_val = cost_info.get('network_cost')
                network_cost = max(network_cost_val if network_cost_val is not None else 0, 0.000001)
                html_content += f"""
                            <tr>
                                <td><strong>{cost_info['display']}</strong></td>
                                <td>{payload_display}</td>
                                <td class="text-right">{format_cost(instance_cost)}</td>
                                <td class="text-right">{format_cost(cluster_cost)}</td>
                                <td class="text-right">{format_cost(alb_cost)}</td>
                                <td class="text-right">{format_cost(storage_cost)}</td>
                                <td class="text-right">{format_cost(network_cost)}</td>
                            </tr>
"""
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Resource Efficiency vs Cost</h4>
                <div class="data-table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>API</th>
                                <th>Payload Size</th>
                                <th class="text-right">Avg Efficiency (%)</th>
                                <th class="text-right">Cost per 1K Requests ($)</th>
                            </tr>
                        </thead>
                        <tbody>
"""
            for cost_info in cost_data:
                payload_display = format_payload_size(cost_info.get('payload_size', 'default'))
                avg_efficiency = (cost_info['cpu_efficiency'] + cost_info['memory_efficiency']) / 2 * 100
                html_content += f"""
                            <tr>
                                <td><strong>{cost_info['display']}</strong></td>
                                <td>{payload_display}</td>
                                <td class="text-right">{avg_efficiency:.2f}</td>
                                <td class="text-right">{format_cost(cost_info['cost_per_1000_requests'])}</td>
                            </tr>
"""
            html_content += """
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
"""
        except Exception as e:
            print(f"Warning: Could not calculate AWS costs ({e})", file=sys.stderr)
            html_content += """
        <div class="comparison-section">
            <h2>💰 AWS EKS Cost Analytics</h2>
            <div class="insight-box">
                <p>Cost analytics are currently unavailable. Please ensure the cost calculation module is available.</p>
            </div>
        </div>
"""
        
        if resource_data:
            html_content += """
        <h2>💻 Resource Utilization Metrics</h2>
        
        <div class="resource-section">
            <h3>Overall Resource Usage</h3>
            <table>
                <thead>
                    <tr>
                        <th>API</th>
                        <th class="text-right">Avg CPU %</th>
                        <th class="text-right">Max CPU %</th>
                        <th class="text-right">Avg Memory %</th>
                        <th class="text-right">Max Memory %</th>
                        <th class="text-right">Avg Memory (MB)</th>
                        <th class="text-right">Max Memory (MB)</th>
                    </tr>
                </thead>
                <tbody>
"""
            
            for api in apis:
                if api['name'] in resource_data:
                    r = resource_data[api['name']]['overall']
                    html_content += f"""
                    <tr>
                        <td><strong>{api['display']}</strong></td>
                        <td class="text-right">{r['avg_cpu_percent']:.2f}</td>
                        <td class="text-right">{r['max_cpu_percent']:.2f}</td>
                        <td class="text-right">{r['avg_memory_percent']:.2f}</td>
                        <td class="text-right">{r['max_memory_percent']:.2f}</td>
                        <td class="text-right">{r['avg_memory_mb']:.2f}</td>
                        <td class="text-right">{r['max_memory_mb']:.2f}</td>
                    </tr>
"""
            
            html_content += """
                </tbody>
            </table>
        </div>
        
"""
            # Organize resource data by phases
            all_phases = set()
            for api_name, api_resource_data in resource_data.items():
                phases = api_resource_data.get('phases', {})
                for phase_num in phases.keys():
                    all_phases.add(int(phase_num))
            
            phases_list = sorted(all_phases) if all_phases else []
            has_phases = len(phases_list) > 0
            phase_labels = [f'Phase {p}' for p in phases_list] if has_phases else ['Overall']
            
            if has_phases:
                # Per-Phase CPU Usage table
                html_content += """
        <div class="resource-section">
            <h3>Per-Phase CPU Usage Comparison</h3>
            <div class="data-table-container">
                <table>
                    <thead>
                        <tr>
                            <th>API</th>
"""
                for phase_label in phase_labels:
                    html_content += f'<th class="text-right">{phase_label} (%)</th>'
                html_content += """
                        </tr>
                    </thead>
                    <tbody>
"""
                for api in apis:
                    if api['name'] in resource_data:
                        html_content += f'<tr><td><strong>{api["display"]}</strong></td>'
                        for phase_num in phases_list:
                            phase_data = resource_data[api['name']].get('phases', {}).get(phase_num, {})
                            if phase_data and phase_data.get('avg_cpu_percent', 0) > 0:
                                html_content += f'<td class="text-right">{phase_data["avg_cpu_percent"]:.2f}</td>'
                            else:
                                overall = resource_data[api['name']].get('overall', {})
                                html_content += f'<td class="text-right">{overall.get("avg_cpu_percent", 0):.2f}</td>'
                        html_content += '</tr>'
                html_content += """
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Per-Phase Memory Usage Comparison</h3>
            <div class="data-table-container">
                <table>
                    <thead>
                        <tr>
                            <th>API</th>
"""
                for phase_label in phase_labels:
                    html_content += f'<th class="text-right">{phase_label} (MB)</th>'
                html_content += """
                        </tr>
                    </thead>
                    <tbody>
"""
                for api in apis:
                    if api['name'] in resource_data:
                        html_content += f'<tr><td><strong>{api["display"]}</strong></td>'
                        for phase_num in phases_list:
                            phase_data = resource_data[api['name']].get('phases', {}).get(phase_num, {})
                            if phase_data and phase_data.get('avg_memory_mb', 0) > 0:
                                html_content += f'<td class="text-right">{phase_data["avg_memory_mb"]:.2f}</td>'
                            else:
                                overall = resource_data[api['name']].get('overall', {})
                                html_content += f'<td class="text-right">{overall.get("avg_memory_mb", 0):.2f}</td>'
                        html_content += '</tr>'
                html_content += """
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: CPU % per Request - Lower is Better</h3>
            <div class="data-table-container">
                <table>
                    <thead>
                        <tr>
                            <th>API</th>
"""
                for phase_label in phase_labels:
                    html_content += f'<th class="text-right">{phase_label}</th>'
                html_content += """
                        </tr>
                    </thead>
                    <tbody>
"""
                for api in apis:
                    if api['name'] in resource_data:
                        html_content += f'<tr><td><strong>{api["display"]}</strong></td>'
                        overall = resource_data[api['name']].get('overall', {})
                        for phase_num in phases_list:
                            phase_data = resource_data[api['name']].get('phases', {}).get(phase_num, {})
                            if phase_data and phase_data.get('requests', 0) > 0 and phase_data.get('cpu_percent_per_request', 0) > 0:
                                html_content += f'<td class="text-right">{phase_data["cpu_percent_per_request"]:.6f}</td>'
                            else:
                                requests = phase_data.get('requests', 0) if phase_data else 0
                                if overall and requests > 0:
                                    test_duration = phase_data.get('duration_seconds', 30) if phase_data else 30
                                    cpu_per_req = (overall.get('avg_cpu_percent', 0) * test_duration) / requests
                                    html_content += f'<td class="text-right">{cpu_per_req:.6f}</td>'
                                elif overall and overall.get('total_samples', 0) > 0:
                                    cpu_per_req = (overall.get('avg_cpu_percent', 0) * 30) / overall.get('total_samples', 1)
                                    html_content += f'<td class="text-right">{cpu_per_req:.6f}</td>'
                                else:
                                    html_content += '<td class="text-right">-</td>'
                        html_content += '</tr>'
                html_content += """
                    </tbody>
                </table>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: RAM MB per Request - Lower is Better</h3>
            <div class="data-table-container">
                <table>
                    <thead>
                        <tr>
                            <th>API</th>
"""
                for phase_label in phase_labels:
                    html_content += f'<th class="text-right">{phase_label}</th>'
                html_content += """
                        </tr>
                    </thead>
                    <tbody>
"""
                for api in apis:
                    if api['name'] in resource_data:
                        html_content += f'<tr><td><strong>{api["display"]}</strong></td>'
                        overall = resource_data[api['name']].get('overall', {})
                        for phase_num in phases_list:
                            phase_data = resource_data[api['name']].get('phases', {}).get(phase_num, {})
                            if phase_data and phase_data.get('requests', 0) > 0 and phase_data.get('ram_mb_per_request', 0) > 0:
                                html_content += f'<td class="text-right">{phase_data["ram_mb_per_request"]:.6f}</td>'
                            else:
                                requests = phase_data.get('requests', 0) if phase_data else 0
                                if overall and requests > 0:
                                    test_duration = phase_data.get('duration_seconds', 30) if phase_data else 30
                                    ram_per_req = (overall.get('avg_memory_mb', 0) * test_duration) / requests
                                    html_content += f'<td class="text-right">{ram_per_req:.6f}</td>'
                                elif overall and overall.get('total_samples', 0) > 0:
                                    ram_per_req = (overall.get('avg_memory_mb', 0) * 30) / overall.get('total_samples', 1)
                                    html_content += f'<td class="text-right">{ram_per_req:.6f}</td>'
                                else:
                                    html_content += '<td class="text-right">-</td>'
                        html_content += '</tr>'
                html_content += """
                    </tbody>
                </table>
            </div>
        </div>
"""
            else:
                # No phases, show overall data only
                html_content += """
        <div class="insight-box">
            <p>No phase-specific resource data available. Showing overall resource usage only.</p>
        </div>
"""
        else:
            # Show warning if no resource data available
            html_content += """
        <h2>💻 Resource Utilization Metrics</h2>
        
        <div class="warning-box">
            <h4>⚠️ Resource Metrics Not Available</h4>
            <p>Resource utilization metrics (CPU and memory usage) were not collected for this test run.</p>
            <p><strong>Possible reasons:</strong></p>
            <ul>
                <li>Metrics collection script encountered an error</li>
                <li>Test duration was too short (smoke tests may not collect enough samples)</li>
                <li>Container metrics collection failed</li>
            </ul>
            <p><strong>Note:</strong> For accurate resource metrics, run longer tests (full or saturation mode) with resource monitoring enabled.</p>
        </div>
        """
    
    
    html_content += f"""
        <div class="footer">
            <p>Generated by k6 Performance Testing Framework</p>
            <p>Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
    </div>
    
    <script>
        // Export table to CSV
        function exportTableToCSV(tableId, filename) {{
            const table = document.getElementById(tableId);
            if (!table) {{
                alert('Table not found');
                return;
            }}
            
            let csv = [];
            const rows = table.querySelectorAll('tr');
            
            for (let row of rows) {{
                const cols = row.querySelectorAll('td, th');
                const rowData = [];
                for (let col of cols) {{
                    let text = col.innerText.trim();
                    // Escape quotes and wrap in quotes if contains comma
                    if (text.includes(',') || text.includes('"') || text.includes('\\n')) {{
                        text = '"' + text.replace(/"/g, '""') + '"';
                    }}
                    rowData.push(text);
                }}
                csv.push(rowData.join(','));
            }}
            
            const csvContent = csv.join('\\n');
            const blob = new Blob([csvContent], {{ type: 'text/csv;charset=utf-8;' }});
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);
            link.setAttribute('href', url);
            link.setAttribute('download', filename);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }}
        
        // Export data to JSON
        function exportDataToJSON(filename) {{
            const apiData = """ + json.dumps([{
                'name': api['name'],
                'display': api['display'],
                'protocol': api['protocol'],
                'payload_size': api.get('payload_size', 'default'),
                'status': api.get('status'),
                'metrics': api.get('metrics', {})
            } for api in api_results], default=str) + """;
            const data = {{
                testMode: '{test_mode}',
                testDate: '{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}',
                apis: apiData
            }};
            
            const jsonContent = JSON.stringify(data, null, 2);
            const blob = new Blob([jsonContent], {{ type: 'application/json;charset=utf-8;' }});
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);
            link.setAttribute('href', url);
            link.setAttribute('download', filename);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }}
        
    </script>
</body>
</html>
"""
    
    # Write HTML file
    with open(html_file, 'w') as f:
        f.write(html_content)
    
    return html_file

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: generate-html-report.py <results_dir> <test_mode> <timestamp>", file=sys.stderr)
        sys.exit(1)
    
    results_dir = sys.argv[1]
    test_mode = sys.argv[2]
    timestamp = sys.argv[3]
    
    html_file = generate_html_report(results_dir, test_mode, timestamp)
    print(f"HTML report generated: {html_file}")


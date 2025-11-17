#!/usr/bin/env python3
"""
Generate comprehensive HTML report from k6 test results
"""
import json
import sys
import os
import subprocess
from datetime import datetime
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
    
    # Map size strings to byte values
    size_map = {
        'default': '~400-500 bytes',
        '4k': '4,096 bytes',
        '8k': '8,192 bytes',
        '32k': '32,768 bytes',
        '64k': '65,536 bytes'
    }
    
    return size_map.get(size_lower, size_str)

def format_payload_sizes_list(payload_sizes):
    """Format a list of payload sizes to show actual byte values"""
    if not payload_sizes:
        return "~400-500 bytes"
    
    formatted_sizes = [format_payload_size(size) for size in sorted(payload_sizes)]
    return ', '.join(formatted_sizes)

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
        all_test_runs = get_latest_test_runs(
            api_names=[api['name'] for api in apis],
            test_mode=test_mode,
            limit=1000  # Get enough to find all matching runs
        )
        
        # Filter by timestamp if provided, and group by API name AND payload size
        # This allows us to collect all test runs (one per API+payload combination)
        api_test_runs = {}  # Key: (api_name, payload_size)
        for test_run in all_test_runs:
            api_name = test_run['api_name']
            payload_size = test_run.get('payload_size', 'default')
            
            # If timestamp is provided, verify it matches
            if timestamp:
                if not test_run.get('k6_json_file_path') or timestamp not in test_run['k6_json_file_path']:
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
                    metrics = {
                        'total_samples': test_run.get('total_samples', 0) or 0,
                        'success_samples': test_run.get('success_samples', 0) or 0,
                        'error_samples': test_run.get('error_samples', 0) or 0,
                        'duration_seconds': 0.0,  # Will calculate from timestamps if needed
                        'throughput': float(test_run.get('throughput_req_per_sec', 0) or 0),
                        'avg_response': float(test_run.get('avg_response_time_ms', 0) or 0),
                        'min_response': float(test_run.get('min_response_time_ms', 0) or 0),
                        'max_response': float(test_run.get('max_response_time_ms', 0) or 0),
                        'p95_response': float(test_run.get('p95_response_time_ms', 0) or 0),
                        'p99_response': float(test_run.get('p99_response_time_ms', 0) or 0),
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
            
            # Check for payload size subdirectories
            payload_dirs = []
            for item in api_dir.iterdir():
                if item.is_dir() and item.name in ['default', '4k', '8k', '32k', '64k']:
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
                    api_results.append({**api, 'status': 'no_json', 'payload_size': 'default'})
                    continue
                
                latest_json = json_files[0] if timestamp else max(json_files, key=lambda p: p.stat().st_mtime)
                metrics = extract_metrics_from_json(latest_json)
                
                if metrics:
                    unique_payload_sizes.add('default')
                    total_duration_seconds += metrics.get('duration_seconds', 0.0)
                    api_results.append({
                        **api, 
                        'status': 'success', 
                        'metrics': metrics, 
                        'json_file': latest_json.name,
                        'payload_size': 'default'
                    })
                else:
                    api_results.append({**api, 'status': 'parse_error', 'payload_size': 'default'})
    
    # Generate HTML
    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>API Performance Test Report - {test_mode.upper()}</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
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
        }}
        th {{
            background: #f8f8f8;
            color: #1a1a1a;
            padding: 12px 15px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #e0e0e0;
            font-size: 13px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}
        td strong {{
            color: #1a1a1a;
            font-weight: 600;
        }}
        td {{
            padding: 12px 15px;
            border-bottom: 1px solid #f0f0f0;
        }}
        tr:hover {{
            background: #fafafa;
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
        .chart-container {{
            position: relative;
            height: 400px;
            margin: 20px 0;
            padding: 20px;
            background: white;
            border-radius: 6px;
            border: 1px solid #e8e8e8;
        }}
        .chart-container h4 {{
            color: #1a1a1a;
            font-size: 16px;
            font-weight: 600;
            margin-bottom: 16px;
            margin-top: 0;
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
        
        <h2>📊 Executive Summary</h2>
        <table>
            <thead>
                <tr>
                    <th>API</th>
                    <th>Protocol</th>
                    <th>Payload Size</th>
                    <th>Status</th>
                    <th>Total Requests</th>
                    <th>Success</th>
                    <th>Errors</th>
                    <th>Error Rate</th>
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
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td>{payload_size}</td>
                    <td class="{status_class}">{status_text}</td>
                    <td>{m['total_samples']}</td>
                    <td>{m['success_samples']}</td>
                    <td>{m['error_samples']}</td>
                    <td>{m['error_rate']:.2f}%</td>
                    <td><strong>{m['throughput']:.2f}</strong></td>
                    <td>{m['avg_response']:.2f}</td>
                    <td>{m['min_response']:.2f}</td>
                    <td>{m['max_response']:.2f}</td>
                    <td>{m['p95_response']:.2f}</td>
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
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
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
        
        html_content += f"""
        <h2>📊 Comparison Analysis</h2>
        
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
            <h3>📈 Performance Comparison Charts</h3>
            
            <div class="resource-section">
                <h4>Throughput Comparison (req/s)</h4>
                <div class="chart-container">
                    <canvas id="throughputChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Average Response Time Comparison (ms)</h4>
                <div class="chart-container">
                    <canvas id="responseTimeChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Error Rate Comparison (%)</h4>
                <div class="chart-container">
                    <canvas id="errorRateChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>P95 Response Time Comparison (ms)</h4>
                <div class="chart-container">
                    <canvas id="p95Chart"></canvas>
                </div>
            </div>
        </div>
        
        <script>
            // Performance metrics data - group by API and payload size
            const performanceDataByApi = {};
            const allPayloadSizes = new Set();
            
            """ + json.dumps([{
                'name': api['name'],
                'display': api['display'],
                'payload_size': api.get('payload_size', 'default'),
                'throughput': api['metrics']['throughput'] if api.get('status') == 'success' and 'metrics' in api else 0,
                'avg_response': api['metrics']['avg_response'] if api.get('status') == 'success' and 'metrics' in api else 0,
                'error_rate': api['metrics']['error_rate'] if api.get('status') == 'success' and 'metrics' in api else 0,
                'p95_response': api['metrics']['p95_response'] if api.get('status') == 'success' and 'metrics' in api else 0
            } for api in api_results]) + """.forEach(item => {
                if (!performanceDataByApi[item.name]) {
                    performanceDataByApi[item.name] = {
                        name: item.name,
                        display: item.display,
                        data: {}
                    };
                }
                performanceDataByApi[item.name].data[item.payload_size] = {
                    throughput: item.throughput,
                    avg_response: item.avg_response,
                    error_rate: item.error_rate,
                    p95_response: item.p95_response
                };
                allPayloadSizes.add(item.payload_size);
            });
            
            // Sort payload sizes: default, 4k, 8k, 32k, 64k
            const payloadSizeOrder = ['default', '4k', '8k', '32k', '64k'];
            const sortedPayloadSizes = Array.from(allPayloadSizes).sort((a, b) => {
                const aIdx = payloadSizeOrder.indexOf(a);
                const bIdx = payloadSizeOrder.indexOf(b);
                if (aIdx === -1 && bIdx === -1) return a.localeCompare(b);
                if (aIdx === -1) return 1;
                if (bIdx === -1) return -1;
                return aIdx - bIdx;
            });
            
            // API order for consistent colors
            const apiOrder = [
                'producer-api-java-rest',
                'producer-api-java-grpc',
                'producer-api-rust-rest',
                'producer-api-rust-grpc',
                'producer-api-go-rest',
                'producer-api-go-grpc'
            ];
            
            const colors = [
                'rgba(54, 162, 235, 0.8)',   // Blue - Java REST
                'rgba(255, 99, 132, 0.8)',   // Red - Java gRPC
                'rgba(75, 192, 192, 0.8)',   // Teal - Rust REST
                'rgba(255, 206, 86, 0.8)',   // Yellow - Rust gRPC
                'rgba(153, 102, 255, 0.8)',  // Purple - Go REST
                'rgba(255, 159, 64, 0.8)'    // Orange - Go gRPC
            ];
            
            // Get color for API
            function getApiColor(apiName) {
                const idx = apiOrder.indexOf(apiName);
                return idx >= 0 ? colors[idx] : colors[0];
            }
            
            // Create datasets for each API
            const apiDatasets = apiOrder
                .filter(apiName => performanceDataByApi[apiName])
                .map(apiName => {
                    const apiData = performanceDataByApi[apiName];
                    return {
                        label: apiData.display,
                        backgroundColor: getApiColor(apiName),
                        borderColor: getApiColor(apiName).replace('0.8', '1'),
                        borderWidth: 2,
                        data: sortedPayloadSizes.map(size => {
                            const data = apiData.data[size];
                            return data ? data.throughput : null;
                        })
                    };
                });
            
            // Throughput Chart
            const throughputCtx = document.getElementById('throughputChart');
            if (throughputCtx) {
                new Chart(throughputCtx, {
                    type: 'bar',
                    data: {
                        labels: sortedPayloadSizes.map(s => s === 'default' ? 'Default' : s.toUpperCase()),
                        datasets: apiOrder
                            .filter(apiName => performanceDataByApi[apiName])
                            .map(apiName => {
                                const apiData = performanceDataByApi[apiName];
                                return {
                                    label: apiData.display,
                                    backgroundColor: getApiColor(apiName),
                                    borderColor: getApiColor(apiName).replace('0.8', '1'),
                                    borderWidth: 2,
                                    data: sortedPayloadSizes.map(size => {
                                        const data = apiData.data[size];
                                        return data ? data.throughput : null;
                                    })
                                };
                            })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            x: {
                                stacked: false,
                                title: {
                                    display: true,
                                    text: 'Payload Size'
                                }
                            },
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'Requests per Second'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top',
                                labels: {
                                    usePointStyle: true,
                                    padding: 15,
                                    font: {
                                        size: 12
                                    }
                                }
                            },
                            title: {
                                display: true,
                                text: 'Throughput Comparison by Payload Size - Higher is Better'
                            }
                        }
                    }
                });
            }
            
            // Response Time Chart
            const responseTimeCtx = document.getElementById('responseTimeChart');
            if (responseTimeCtx) {
                new Chart(responseTimeCtx, {
                    type: 'bar',
                    data: {
                        labels: sortedPayloadSizes.map(s => s === 'default' ? 'Default' : s.toUpperCase()),
                        datasets: apiOrder
                            .filter(apiName => performanceDataByApi[apiName])
                            .map(apiName => {
                                const apiData = performanceDataByApi[apiName];
                                return {
                                    label: apiData.display,
                                    backgroundColor: getApiColor(apiName),
                                    borderColor: getApiColor(apiName).replace('0.8', '1'),
                                    borderWidth: 2,
                                    data: sortedPayloadSizes.map(size => {
                                        const data = apiData.data[size];
                                        return data ? data.avg_response : null;
                                    })
                                };
                            })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            x: {
                                stacked: false,
                                title: {
                                    display: true,
                                    text: 'Payload Size'
                                }
                            },
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'Response Time (ms)'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top',
                                labels: {
                                    usePointStyle: true,
                                    padding: 15,
                                    font: {
                                        size: 12
                                    }
                                }
                            },
                            title: {
                                display: true,
                                text: 'Average Response Time Comparison by Payload Size - Lower is Better'
                            }
                        }
                    }
                });
            }
            
            // Error Rate Chart
            const errorRateCtx = document.getElementById('errorRateChart');
            if (errorRateCtx) {
                new Chart(errorRateCtx, {
                    type: 'bar',
                    data: {
                        labels: sortedPayloadSizes.map(s => s === 'default' ? 'Default' : s.toUpperCase()),
                        datasets: apiOrder
                            .filter(apiName => performanceDataByApi[apiName])
                            .map(apiName => {
                                const apiData = performanceDataByApi[apiName];
                                return {
                                    label: apiData.display,
                                    backgroundColor: getApiColor(apiName),
                                    borderColor: getApiColor(apiName).replace('0.8', '1'),
                                    borderWidth: 2,
                                    data: sortedPayloadSizes.map(size => {
                                        const data = apiData.data[size];
                                        return data ? data.error_rate : null;
                                    })
                                };
                            })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            x: {
                                stacked: false,
                                title: {
                                    display: true,
                                    text: 'Payload Size'
                                }
                            },
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'Error Rate (%)'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top',
                                labels: {
                                    usePointStyle: true,
                                    padding: 15,
                                    font: {
                                        size: 12
                                    }
                                }
                            },
                            title: {
                                display: true,
                                text: 'Error Rate Comparison by Payload Size - Lower is Better'
                            }
                        }
                    }
                });
            }
            
            // P95 Response Time Chart
            const p95Ctx = document.getElementById('p95Chart');
            if (p95Ctx) {
                new Chart(p95Ctx, {
                    type: 'bar',
                    data: {
                        labels: sortedPayloadSizes.map(s => s === 'default' ? 'Default' : s.toUpperCase()),
                        datasets: apiOrder
                            .filter(apiName => performanceDataByApi[apiName])
                            .map(apiName => {
                                const apiData = performanceDataByApi[apiName];
                                return {
                                    label: apiData.display,
                                    backgroundColor: getApiColor(apiName),
                                    borderColor: getApiColor(apiName).replace('0.8', '1'),
                                    borderWidth: 2,
                                    data: sortedPayloadSizes.map(size => {
                                        const data = apiData.data[size];
                                        return data ? data.p95_response : null;
                                    })
                                };
                            })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            x: {
                                stacked: false,
                                title: {
                                    display: true,
                                    text: 'Payload Size'
                                }
                            },
                            y: {
                                beginAtZero: true,
                                title: {
                                    display: true,
                                    text: 'P95 Response Time (ms)'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top',
                                labels: {
                                    usePointStyle: true,
                                    padding: 15,
                                    font: {
                                        size: 12
                                    }
                                }
                            },
                            title: {
                                display: true,
                                text: 'P95 Response Time Comparison by Payload Size - Lower is Better'
                            }
                        }
                    }
                });
            }
        </script>
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
                    
                    if resource_summary:
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
            
            <h3>Cost Summary Table</h3>
            <div style="margin-bottom: 15px; padding: 10px; background-color: #f8f9fa; border-left: 4px solid #007bff; border-radius: 4px;">
                <p style="margin: 0 0 10px 0; color: #333; font-size: 14px;">
                    <strong>Pod Configuration:</strong> The cost calculator automatically selects the most cost-effective EC2 instance type based on pod requirements. Configured values:
                </p>
                <table style="width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 5px;">
                    <thead>
                        <tr style="background-color: #e9ecef;">
                            <th style="padding: 6px; text-align: left; border: 1px solid #dee2e6;">API</th>
                            <th style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">Pods</th>
                            <th style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">CPU/Pod</th>
                            <th style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">Memory/Pod</th>
                            <th style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">Storage/Pod</th>
                        </tr>
                    </thead>
                    <tbody>
"""
            
            # Add pod configuration rows
            for api in successful_apis:
                api_name = api['name']
                api_display = api['display']
                api_pod_config = api_configs.get(api_name, default_config)
                num_pods = api_pod_config.get('num_pods', default_config['num_pods'])
                cpu_cores = api_pod_config.get('cpu_cores_per_pod', default_config['cpu_cores_per_pod'])
                memory_gb = api_pod_config.get('memory_gb_per_pod', default_config['memory_gb_per_pod'])
                storage_gb = api_pod_config.get('storage_gb_per_pod', default_config['storage_gb_per_pod'])
                
                html_content += f"""
                        <tr>
                            <td style="padding: 6px; border: 1px solid #dee2e6;"><strong>{api_display}</strong></td>
                            <td style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">{num_pods}</td>
                            <td style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">{cpu_cores:.1f} cores</td>
                            <td style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">{memory_gb:.1f} GB</td>
                            <td style="padding: 6px; text-align: center; border: 1px solid #dee2e6;">{storage_gb:.1f} GB</td>
                        </tr>
"""
            
            html_content += """
                    </tbody>
                </table>
            </div>
            <table style="width: 100%; table-layout: auto;">
                <thead>
                    <tr>
                        <th style="text-align: left;">API</th>
                        <th style="text-align: center;">Pods</th>
                        <th style="text-align: left;">Pod Size</th>
                        <th style="text-align: center;">Instance Type</th>
                        <th style="text-align: center;">Instances</th>
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
                        <td style="text-align: center;">{cost_info['num_pods']}</td>
                        <td>{pod_size}</td>
                        <td style="text-align: center;">{cost_info['instance_type']}</td>
                        <td style="text-align: center;">{cost_info['instances_needed']}</td>
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
                If efficiency shows 0%, it means resource metrics were not collected or the API had minimal resource usage during the test. 
                This is common for very short smoke tests. For accurate efficiency metrics, run longer tests (full or saturation mode) with resource monitoring enabled.
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
                <h4>Total Cost Comparison</h4>
                <div class="chart-container">
                    <canvas id="totalCostChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Cost per 1,000 Requests Comparison</h4>
                <div class="chart-container">
                    <canvas id="costPerRequestChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Cost Breakdown by Component</h4>
                <div class="chart-container">
                    <canvas id="costBreakdownChart"></canvas>
                </div>
            </div>
            
            <div class="resource-section">
                <h4>Resource Efficiency vs Cost</h4>
                <div class="chart-container">
                    <canvas id="efficiencyCostChart"></canvas>
                </div>
            </div>
            
            <script>
                // Cost data
                const costData = """ + json.dumps(cost_data) + """;
                
                // Total Cost Chart
                const totalCostCtx = document.getElementById('totalCostChart');
                if (totalCostCtx) {
                    new Chart(totalCostCtx, {
                        type: 'bar',
                        data: {
                            labels: costData.map(d => d.display),
                            datasets: [{
                                label: 'Total Cost ($)',
                                data: costData.map(d => d.total_cost),
                                backgroundColor: costData.map((d, i) => colors[i % colors.length]),
                                borderColor: costData.map((d, i) => colors[i % colors.length].replace('0.8', '1')),
                                borderWidth: 2
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                y: {
                                    beginAtZero: true,
                                    title: {
                                        display: true,
                                        text: 'Total Cost (USD)'
                                    }
                                }
                            },
                            plugins: {
                                legend: {
                                    display: false
                                },
                                title: {
                                    display: true,
                                    text: 'Total AWS EKS Cost per API - Lower is Better'
                                }
                            }
                        }
                    });
                }
                
                // Cost per Request Chart
                const costPerRequestCtx = document.getElementById('costPerRequestChart');
                if (costPerRequestCtx) {
                    new Chart(costPerRequestCtx, {
                        type: 'bar',
                        data: {
                            labels: costData.map(d => d.display),
                            datasets: [{
                                label: 'Cost per 1,000 Requests ($)',
                                data: costData.map(d => d.cost_per_1000_requests),
                                backgroundColor: costData.map((d, i) => colors[i % colors.length]),
                                borderColor: costData.map((d, i) => colors[i % colors.length].replace('0.8', '1')),
                                borderWidth: 2
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                y: {
                                    beginAtZero: true,
                                    title: {
                                        display: true,
                                        text: 'Cost per 1,000 Requests (USD)'
                                    }
                                }
                            },
                            plugins: {
                                legend: {
                                    display: false
                                },
                                title: {
                                    display: true,
                                    text: 'Cost Efficiency: Cost per 1,000 Requests - Lower is Better'
                                }
                            }
                        }
                    });
                }
                
                // Cost Breakdown Chart
                const costBreakdownCtx = document.getElementById('costBreakdownChart');
                if (costBreakdownCtx) {
                    new Chart(costBreakdownCtx, {
                        type: 'bar',
                        data: {
                            labels: costData.map(d => d.display),
                            datasets: [
                                {
                                    label: 'Instance',
                                    data: costData.map(d => d.instance_effective_cost),
                                    backgroundColor: 'rgba(54, 162, 235, 0.8)'
                                },
                                {
                                    label: 'Cluster',
                                    data: costData.map(d => d.cluster_cost),
                                    backgroundColor: 'rgba(255, 99, 132, 0.8)'
                                },
                                {
                                    label: 'ALB',
                                    data: costData.map(d => d.alb_cost),
                                    backgroundColor: 'rgba(75, 192, 192, 0.8)'
                                },
                                {
                                    label: 'Storage',
                                    data: costData.map(d => d.storage_cost),
                                    backgroundColor: 'rgba(255, 206, 86, 0.8)'
                                },
                                {
                                    label: 'Network',
                                    data: costData.map(d => d.network_cost),
                                    backgroundColor: 'rgba(153, 102, 255, 0.8)'
                                }
                            ]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: {
                                    stacked: true
                                },
                                y: {
                                    stacked: true,
                                    beginAtZero: true,
                                    title: {
                                        display: true,
                                        text: 'Cost (USD)'
                                    }
                                }
                            },
                            plugins: {
                                legend: {
                                    display: true,
                                    position: 'top'
                                },
                                title: {
                                    display: true,
                                    text: 'Cost Breakdown by Component'
                                }
                            }
                        }
                    });
                }
                
                // Efficiency vs Cost Chart
                const efficiencyCostCtx = document.getElementById('efficiencyCostChart');
                if (efficiencyCostCtx) {
                    new Chart(efficiencyCostCtx, {
                        type: 'scatter',
                        data: {
                            datasets: [{
                                label: 'APIs',
                                data: costData.map(d => ({
                                    x: (d.cpu_efficiency + d.memory_efficiency) / 2 * 100,
                                    y: d.cost_per_1000_requests,
                                    label: d.display
                                })),
                                backgroundColor: costData.map((d, i) => colors[i % colors.length]),
                                borderColor: costData.map((d, i) => colors[i % colors.length].replace('0.8', '1')),
                                borderWidth: 2,
                                pointRadius: 8
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false,
                            scales: {
                                x: {
                                    title: {
                                        display: true,
                                        text: 'Average Resource Efficiency (%)'
                                    },
                                    min: 0,
                                    max: 100
                                },
                                y: {
                                    title: {
                                        display: true,
                                        text: 'Cost per 1,000 Requests (USD)'
                                    },
                                    beginAtZero: true
                                }
                            },
                            plugins: {
                                legend: {
                                    display: false
                                },
                                title: {
                                    display: true,
                                    text: 'Resource Efficiency vs Cost Efficiency'
                                },
                                tooltip: {
                                    callbacks: {
                                        label: function(context) {
                                            const point = context.raw;
                                            const api = costData.find(d => 
                                                Math.abs((d.cpu_efficiency + d.memory_efficiency) / 2 * 100 - point.x) < 0.1 &&
                                                Math.abs(d.cost_per_1000_requests - point.y) < 0.0001
                                            );
                                            return api ? `${api.display}: ${point.y.toFixed(4)} $/1K req, ${point.x.toFixed(1)}% efficiency` : '';
                                        }
                                    }
                                }
                            }
                        }
                    });
                }
            </script>
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
                        <th>Avg CPU %</th>
                        <th>Max CPU %</th>
                        <th>Avg Memory %</th>
                        <th>Max Memory %</th>
                        <th>Avg Memory (MB)</th>
                        <th>Max Memory (MB)</th>
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
                        <td>{r['avg_cpu_percent']:.2f}</td>
                        <td>{r['max_cpu_percent']:.2f}</td>
                        <td>{r['avg_memory_percent']:.2f}</td>
                        <td>{r['max_memory_percent']:.2f}</td>
                        <td>{r['avg_memory_mb']:.2f}</td>
                        <td>{r['max_memory_mb']:.2f}</td>
                    </tr>
"""
            
            html_content += """
                </tbody>
            </table>
        </div>
        
        <div class="resource-section">
            <h3>Per-Phase CPU Usage Comparison</h3>
            <div class="chart-container">
                <canvas id="cpuPhaseChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Per-Phase Memory Usage Comparison</h3>
            <div class="chart-container">
                <canvas id="memoryPhaseChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: CPU % per Request</h3>
            <div class="chart-container">
                <canvas id="cpuPerRequestChart"></canvas>
            </div>
        </div>
        
        <div class="resource-section">
            <h3>Derived Metrics: RAM MB per Request</h3>
            <div class="chart-container">
                <canvas id="ramPerRequestChart"></canvas>
            </div>
        </div>
        
        <script>
            // Prepare data for charts
            const resourceData = """ + json.dumps(resource_data) + """;
            
            // Get all phase numbers
            const allPhases = new Set();
            Object.values(resourceData).forEach(data => {
                Object.keys(data.phases || {}).forEach(phase => allPhases.add(parseInt(phase)));
            });
            const phases = Array.from(allPhases).sort((a, b) => a - b);
            
            // Get API names
            const apiNames = Object.keys(resourceData).map(name => {
                const api = """ + json.dumps(apis) + """.find(a => a.name === name);
                return api ? api.display : name;
            });
            
            // Color palette
            const colors = [
                'rgba(54, 162, 235, 0.8)',
                'rgba(255, 99, 132, 0.8)',
                'rgba(75, 192, 192, 0.8)',
                'rgba(255, 206, 86, 0.8)',
                'rgba(153, 102, 255, 0.8)',
                'rgba(255, 159, 64, 0.8)'
            ];
            
            // CPU Phase Chart
            const cpuPhaseCtx = document.getElementById('cpuPhaseChart');
            if (cpuPhaseCtx) {
                new Chart(cpuPhaseCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    // Use phase data if available, otherwise fall back to overall
                                    if (phaseData && phaseData.avg_cpu_percent > 0) {
                                        return phaseData.avg_cpu_percent;
                                    }
                                    // Fall back to overall CPU if phase data is missing or zero
                                    const overall = resourceData[apiName]?.overall;
                                    return overall ? overall.avg_cpu_percent : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                type: 'logarithmic',
                                beginAtZero: false,
                                title: {
                                    display: true,
                                    text: 'CPU %'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Average CPU Usage by Phase'
                            }
                        }
                    }
                });
            }
            
            // Memory Phase Chart
            const memoryPhaseCtx = document.getElementById('memoryPhaseChart');
            if (memoryPhaseCtx) {
                new Chart(memoryPhaseCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    // Use phase data if available, otherwise fall back to overall
                                    if (phaseData && phaseData.avg_memory_mb > 0) {
                                        return phaseData.avg_memory_mb;
                                    }
                                    // Fall back to overall memory if phase data is missing or zero
                                    const overall = resourceData[apiName]?.overall;
                                    return overall ? overall.avg_memory_mb : 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                type: 'logarithmic',
                                beginAtZero: false,
                                title: {
                                    display: true,
                                    text: 'Memory (MB)'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Average Memory Usage by Phase'
                            }
                        }
                    }
                });
            }
            
            // CPU per Request Chart
            const cpuPerRequestCtx = document.getElementById('cpuPerRequestChart');
            if (cpuPerRequestCtx) {
                new Chart(cpuPerRequestCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    // Use phase data if available and has requests
                                    if (phaseData && phaseData.requests > 0 && phaseData.cpu_percent_per_request > 0) {
                                        return phaseData.cpu_percent_per_request;
                                    }
                                    // Calculate from overall if phase data is missing
                                    const overall = resourceData[apiName]?.overall;
                                    const requests = phaseData?.requests || 0;
                                    if (overall && requests > 0) {
                                        // Approximate: (avg CPU % * test duration) / requests
                                        const testDuration = phaseData?.duration_seconds || 30;
                                        return (overall.avg_cpu_percent * testDuration) / requests;
                                    }
                                    return 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                type: 'logarithmic',
                                beginAtZero: false,
                                title: {
                                    display: true,
                                    text: 'CPU %-seconds per Request'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'CPU Efficiency: CPU % per Request (lower is better)'
                            }
                        }
                    }
                });
            }
            
            // RAM per Request Chart
            const ramPerRequestCtx = document.getElementById('ramPerRequestChart');
            if (ramPerRequestCtx) {
                new Chart(ramPerRequestCtx, {
                    type: 'bar',
                    data: {
                        labels: phases.map(p => 'Phase ' + p),
                        datasets: Object.keys(resourceData).map((apiName, idx) => {
                            const api = """ + json.dumps(apis) + """.find(a => a.name === apiName);
                            const displayName = api ? api.display : apiName;
                            return {
                                label: displayName,
                                data: phases.map(phase => {
                                    const phaseData = resourceData[apiName]?.phases?.[phase];
                                    // Use phase data if available and has requests
                                    if (phaseData && phaseData.requests > 0 && phaseData.ram_mb_per_request > 0) {
                                        return phaseData.ram_mb_per_request;
                                    }
                                    // Calculate from overall if phase data is missing
                                    const overall = resourceData[apiName]?.overall;
                                    const requests = phaseData?.requests || 0;
                                    if (overall && requests > 0) {
                                        // Approximate: (avg memory MB * test duration) / requests
                                        const testDuration = phaseData?.duration_seconds || 30;
                                        return (overall.avg_memory_mb * testDuration) / requests;
                                    }
                                    return 0;
                                }),
                                backgroundColor: colors[idx % colors.length],
                                borderColor: colors[idx % colors.length].replace('0.8', '1'),
                                borderWidth: 1
                            };
                        })
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        scales: {
                            y: {
                                type: 'logarithmic',
                                beginAtZero: false,
                                title: {
                                    display: true,
                                    text: 'RAM MB-seconds per Request'
                                }
                            }
                        },
                        plugins: {
                            legend: {
                                display: true,
                                position: 'top'
                            },
                            title: {
                                display: true,
                                text: 'Memory Efficiency: RAM MB per Request (lower is better)'
                            }
                        }
                    }
                });
            }
        </script>
"""
    
    html_content += """
        <h2>📋 Detailed Results</h2>
        <table>
            <thead>
                <tr>
                    <th>API</th>
                    <th>Protocol</th>
                    <th>Payload Size</th>
                    <th>Total Requests</th>
                    <th>Success</th>
                    <th>Errors</th>
                    <th>Error Rate</th>
                    <th>Test Duration (s)</th>
                    <th>Throughput (req/s)</th>
                    <th>Avg Response (ms)</th>
                    <th>Min (ms)</th>
                    <th>Max (ms)</th>
                    <th>P95 (ms)</th>
                    <th>P99 (ms)</th>
                </tr>
            </thead>
            <tbody>
"""
    
    # Add detailed results for each API+payload combination
    for api in api_results:
        if api.get('status') == 'success' and 'metrics' in api:
            m = api['metrics']
            payload_size = api.get('payload_size', 'default')
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td>{payload_size}</td>
                    <td>{m['total_samples']}</td>
                    <td class="status-success">{m['success_samples']}</td>
                    <td class="status-error">{m['error_samples']}</td>
                    <td>{m['error_rate']:.2f}%</td>
                    <td>{m['duration_seconds']:.2f}</td>
                    <td><strong>{m['throughput']:.2f}</strong></td>
                    <td>{m['avg_response']:.2f}</td>
                    <td>{m['min_response']:.2f}</td>
                    <td>{m['max_response']:.2f}</td>
                    <td>{m['p95_response']:.2f}</td>
                    <td>{m['p99_response']:.2f}</td>
                </tr>
"""
        else:
            payload_size = api.get('payload_size', 'default')
            status_text = '❌ No Results' if api.get('status') == 'no_results' else '❌ No JSON' if api.get('status') == 'no_json' else '❌ Parse Error'
            html_content += f"""
                <tr>
                    <td><strong>{api['display']}</strong></td>
                    <td>{api['protocol']}</td>
                    <td>{payload_size}</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
                    <td>-</td>
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
    
    html_content += f"""
        <div class="footer">
            <p>Generated by k6 Performance Testing Framework</p>
            <p>Report generated at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        </div>
    </div>
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


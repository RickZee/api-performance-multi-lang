#!/usr/bin/env python3
"""
Extract metrics from k6 JSON output (supports both summary and NDJSON formats)
"""
import json
import sys
import os
from datetime import datetime

def extract_metrics(json_file):
    if not json_file or not os.path.exists(json_file):
        print("0|0|0|0.00|0.00|0.00|0.00|0.00", file=sys.stderr)
        sys.exit(1)
    
    try:
        # Try single JSON first
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
                        
                        root = data.get('root_group', {})
                        duration_ms = float(root.get('execution_duration', {}).get('total', 0))
                        duration_seconds = duration_ms / 1000.0 if duration_ms > 0 else 0.0
                        
                        print(f"{total_samples}|{success_samples}|{error_samples}|{duration_seconds:.2f}|{throughput:.2f}|{avg_response:.2f}|{min_response:.2f}|{max_response:.2f}")
                        sys.exit(0)
            except json.JSONDecodeError:
                pass
        
        # Parse NDJSON
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
                        except Exception as e:
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
        # Each grpc_req_duration point represents one request
        if not http_reqs and not grpc_reqs:
            if grpc_durations:
                # Use grpc_req_duration points to count requests (each point = 1 request)
                grpc_reqs = [1] * len(grpc_durations)
            elif iterations:
                # Sum all iteration values to get total iterations
                total_iterations = sum(iterations)
                # Create a list with total_iterations entries for consistency
                grpc_reqs = [1] * total_iterations
        
        reqs = http_reqs if http_reqs else grpc_reqs
        durations = http_durations if http_durations else grpc_durations
        failed = http_failed if http_failed else grpc_failed
        
        if not reqs:
            print("0|0|0|0.00|0.00|0.00|0.00|0.00", file=sys.stderr)
            sys.exit(1)
        
        total_samples = len(reqs)
        success_samples = total_samples - sum(failed) if failed else total_samples
        error_samples = sum(failed) if failed else 0
        
        # Calculate duration - prefer actual time range, fall back to iteration durations
        if start_time and end_time and (end_time - start_time).total_seconds() > 0.01:
            # Use actual time range if it's meaningful (> 10ms)
            duration_seconds = (end_time - start_time).total_seconds()
        elif iteration_durations:
            # For smoke tests with 1 VU, iterations run sequentially, so use sum
            # For parallel iterations (multiple VUs), use max duration
            # Since we can't easily determine VU count, use sum for better accuracy
            # (sum works for both sequential and parallel, though it's less accurate for parallel)
            duration_seconds = sum(iteration_durations) / 1000.0 if iteration_durations else 0.0
        else:
            # Last resort: estimate from request count (assume ~100ms per request)
            duration_seconds = max(0.1, total_samples * 0.1)
        
        # Ensure minimum duration of 0.1 seconds to avoid division by zero
        duration_seconds = max(0.1, duration_seconds)
        
        throughput = total_samples / duration_seconds if duration_seconds > 0 else 0.0
        
        if durations:
            avg_response = sum(durations) / len(durations)
            min_response = min(durations)
            max_response = max(durations)
        else:
            avg_response = 0.0
            min_response = 0.0
            max_response = 0.0
        
        print(f"{total_samples}|{success_samples}|{error_samples}|{duration_seconds:.2f}|{throughput:.2f}|{avg_response:.2f}|{min_response:.2f}|{max_response:.2f}")
        sys.exit(0)
    except Exception as e:
        print(f"0|0|0|0.00|0.00|0.00|0.00|0.00", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("0|0|0|0.00|0.00|0.00|0.00|0.00", file=sys.stderr)
        sys.exit(1)
    extract_metrics(sys.argv[1])


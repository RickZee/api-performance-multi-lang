#!/usr/bin/env python3
"""
Phase-Aware Resource Metrics Analyzer
Analyzes resource utilization metrics (CPU, memory) per test phase
"""

import json
import sys
import os
import csv
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def parse_duration(duration_str: str) -> int:
    """Parse k6 duration string (e.g., '2m', '5m') to seconds"""
    if duration_str.endswith('m'):
        return int(duration_str[:-1]) * 60
    elif duration_str.endswith('s'):
        return int(duration_str[:-1])
    elif duration_str.endswith('h'):
        return int(duration_str[:-1]) * 3600
    else:
        # Assume seconds if no unit
        return int(duration_str)


def get_phase_boundaries(test_mode: str) -> List[Tuple[int, int, int]]:
    """
    Get phase boundaries based on test mode.
    Returns list of (phase_num, duration_seconds, target_vus) tuples
    """
    phases = []
    
    if test_mode == 'smoke':
        # Smoke test: single phase, 1 VU, 5 iterations (~5-10 seconds)
        # Treat the entire test as one phase for metrics collection
        phases = [
            (1, 10, 1),    # Phase 1: ~10s at 1 VU (5 iterations)
        ]
    elif test_mode == 'full':
        phases = [
            (1, 120, 10),   # Phase 1: 2m at 10 VUs
            (2, 120, 50),   # Phase 2: 2m at 50 VUs
            (3, 120, 100),  # Phase 3: 2m at 100 VUs
            (4, 300, 200),  # Phase 4: 5m at 200 VUs
        ]
    elif test_mode == 'saturation':
        phases = [
            (1, 120, 10),    # Phase 1: 2m at 10 VUs
            (2, 120, 50),    # Phase 2: 2m at 50 VUs
            (3, 120, 100),   # Phase 3: 2m at 100 VUs
            (4, 120, 200),   # Phase 4: 2m at 200 VUs
            (5, 120, 500),   # Phase 5: 2m at 500 VUs
            (6, 120, 1000),  # Phase 6: 2m at 1000 VUs
            (7, 120, 2000),  # Phase 7: 2m at 2000 VUs
        ]
    else:
        # Unknown test mode, return empty
        return []
    
    return phases


def extract_test_start_time_from_k6_json(json_file: str) -> Optional[float]:
    """Extract test start time from k6 JSON output"""
    try:
        with open(json_file, 'r') as f:
            start_time = None
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                    obj_type = obj.get('type', '')
                    data = obj.get('data', {})
                    
                    if 'time' in data:
                        time_str = data['time']
                        try:
                            # Handle both Z and +00:00 timezone formats
                            if time_str.endswith('Z'):
                                time_str = time_str[:-1] + '+00:00'
                            time_obj = datetime.fromisoformat(time_str)
                            timestamp = time_obj.timestamp()
                            if start_time is None or timestamp < start_time:
                                start_time = timestamp
                        except Exception:
                            pass
                except json.JSONDecodeError:
                    continue
            
            return start_time
    except Exception as e:
        print(f"Error extracting start time from k6 JSON: {e}", file=sys.stderr)
        return None


def extract_requests_per_phase_from_k6_json(json_file: str, phase_boundaries: List[Tuple[int, int, int]], test_start_time: float) -> Dict[int, int]:
    """Extract number of requests per phase from k6 JSON"""
    phase_requests = {phase_num: 0 for phase_num, _, _ in phase_boundaries}
    
    # Calculate phase start/end times
    phase_times = {}
    current_time = test_start_time
    for phase_num, duration, _ in phase_boundaries:
        phase_times[phase_num] = (current_time, current_time + duration)
        current_time += duration
    
    try:
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
                    
                    # Count requests (http_req_duration or grpc_req_duration points)
                    # Each Point with these metrics represents one request
                    # Note: http_reqs/grpc_reqs are counter metrics (cumulative), not individual requests
                    # We should only count http_req_duration/grpc_req_duration which are per-request
                    if obj_type == 'Point' and metric_name in ['http_req_duration', 'grpc_req_duration']:
                        if 'time' in data:
                            time_str = data['time']
                            try:
                                if time_str.endswith('Z'):
                                    time_str = time_str[:-1] + '+00:00'
                                time_obj = datetime.fromisoformat(time_str)
                                request_time = time_obj.timestamp()
                                
                                # Find which phase this request belongs to
                                for phase_num, (phase_start, phase_end) in phase_times.items():
                                    if phase_start <= request_time < phase_end:
                                        phase_requests[phase_num] += 1
                                        break
                            except Exception:
                                pass
                except json.JSONDecodeError:
                    continue
    except Exception as e:
        print(f"Error extracting requests per phase: {e}", file=sys.stderr)
    
    return phase_requests


def extract_metrics_start_time_from_csv(csv_file: str) -> Optional[float]:
    """Extract metrics collection start time from CSV metadata"""
    try:
        with open(csv_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('# Start timestamp:'):
                    timestamp_str = line.split(':', 1)[1].strip()
                    return float(timestamp_str)
    except Exception as e:
        print(f"Error extracting start time from CSV: {e}", file=sys.stderr)
    
    # Fallback: try to get from first data row
    try:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if 'timestamp' in row and row['timestamp']:
                    return float(row['timestamp'])
    except Exception:
        pass
    
    return None


def parse_metrics_csv(csv_file: str) -> List[Dict]:
    """Parse metrics CSV file, skipping comment lines"""
    metrics = []
    
    try:
        with open(csv_file, 'r') as f:
            lines = f.readlines()
            
            # Find the header line (first non-comment line)
            header_line = None
            header_line_num = 0
            for i, line in enumerate(lines):
                line = line.strip()
                if line and not line.startswith('#'):
                    header_line = line
                    header_line_num = i
                    break
            
            if not header_line:
                print("Warning: No header line found in CSV file", file=sys.stderr)
                return metrics
            
            # Create DictReader starting from the header line
            reader = csv.DictReader(lines[header_line_num:])
            
            for row in reader:
                # Skip comment lines
                if any(key.startswith('#') for key in row.keys()):
                    continue
                
                try:
                    metric = {
                        'timestamp': float(row['timestamp']),
                        'datetime': row['datetime'],
                        'container': row['container'],
                        'cpu_percent': float(row['cpu_percent']) if row['cpu_percent'] else 0.0,
                        'memory_percent': float(row['memory_percent']) if row['memory_percent'] else 0.0,
                        'memory_used_mb': float(row['memory_used_mb']) if row['memory_used_mb'] else 0.0,
                        'memory_limit_mb': float(row['memory_limit_mb']) if row['memory_limit_mb'] else 0.0,
                    }
                    metrics.append(metric)
                except (ValueError, KeyError) as e:
                    # Skip invalid rows
                    continue
    except Exception as e:
        print(f"Error parsing metrics CSV: {e}", file=sys.stderr)
    
    return metrics


def calculate_phase_metrics(metrics: List[Dict], phase_boundaries: List[Tuple[int, int, int]], 
                           metrics_start_time: float, k6_start_time: float) -> Dict:
    """Calculate metrics per phase"""
    # Calculate phase start/end times relative to metrics start time
    # Adjust for any offset between k6 start and metrics start
    time_offset = k6_start_time - metrics_start_time
    
    phase_times = {}
    current_time = 0  # Relative to k6 start
    for phase_num, duration, target_vus in phase_boundaries:
        phase_start = current_time + time_offset
        phase_end = current_time + duration + time_offset
        phase_times[phase_num] = (phase_start, phase_end, duration, target_vus)
        current_time += duration
    
    phase_results = {}
    
    for phase_num, (phase_start, phase_end, duration, target_vus) in phase_times.items():
        # Filter metrics for this phase
        phase_metrics = [
            m for m in metrics
            if phase_start <= m['timestamp'] < phase_end
        ]
        
        # If no metrics in phase, try to use metrics from a wider window (within 10 seconds of phase)
        if not phase_metrics:
            phase_metrics = [
                m for m in metrics
                if (phase_start - 10) <= m['timestamp'] < (phase_end + 10)
            ]
        
        # If still no metrics, use all available metrics for this phase (for very short tests like smoke)
        if not phase_metrics and metrics:
            phase_metrics = metrics
        
        if not phase_metrics:
            phase_results[phase_num] = {
                'phase': phase_num,
                'duration_seconds': duration,
                'target_vus': target_vus,
                'avg_cpu_percent': 0.0,
                'max_cpu_percent': 0.0,
                'avg_memory_percent': 0.0,
                'max_memory_percent': 0.0,
                'avg_memory_mb': 0.0,
                'max_memory_mb': 0.0,
                'memory_limit_mb': 2048.0,  # Default
                'sample_count': 0,
            }
            continue
        
        cpu_values = [m['cpu_percent'] for m in phase_metrics]
        memory_percent_values = [m['memory_percent'] for m in phase_metrics]
        memory_mb_values = [m['memory_used_mb'] for m in phase_metrics]
        
        # Extract memory_limit_mb from phase metrics (should be constant)
        phase_memory_limit_mb = 2048.0  # Default
        for m in phase_metrics:
            if m.get('memory_limit_mb', 0.0) > 0:
                phase_memory_limit_mb = m['memory_limit_mb']
                break
        
        phase_results[phase_num] = {
            'phase': phase_num,
            'duration_seconds': duration,
            'target_vus': target_vus,
            'avg_cpu_percent': sum(cpu_values) / len(cpu_values) if cpu_values else 0.0,
            'max_cpu_percent': max(cpu_values) if cpu_values else 0.0,
            'avg_memory_percent': sum(memory_percent_values) / len(memory_percent_values) if memory_percent_values else 0.0,
            'max_memory_percent': max(memory_percent_values) if memory_percent_values else 0.0,
            'avg_memory_mb': sum(memory_mb_values) / len(memory_mb_values) if memory_mb_values else 0.0,
            'max_memory_mb': max(memory_mb_values) if memory_mb_values else 0.0,
            'memory_limit_mb': phase_memory_limit_mb,
            'sample_count': len(phase_metrics),
        }
    
    return phase_results


def calculate_derived_metrics(phase_results: Dict, phase_requests: Dict[int, int]) -> Dict:
    """Calculate derived metrics (CPU % per request, RAM per request)"""
    derived = {}
    
    for phase_num, phase_data in phase_results.items():
        requests = phase_requests.get(phase_num, 0)
        duration = phase_data['duration_seconds']
        avg_cpu = phase_data['avg_cpu_percent']
        avg_memory_mb = phase_data['avg_memory_mb']
        
        # CPU % per request = (avg CPU % * phase duration) / total requests in phase
        # This gives us the CPU percentage-seconds per request
        cpu_per_request = (avg_cpu * duration) / requests if requests > 0 else 0.0
        
        # RAM per request = (avg memory MB * phase duration) / total requests in phase
        # This gives us the memory MB-seconds per request
        ram_per_request = (avg_memory_mb * duration) / requests if requests > 0 else 0.0
        
        derived[phase_num] = {
            'cpu_percent_per_request': cpu_per_request,
            'ram_mb_per_request': ram_per_request,
            'requests': requests,
        }
    
    return derived


def analyze_lambda_metrics_from_logs(lambda_log_file: str, k6_json_file: str, test_mode: str = "smoke") -> Dict:
    """
    Analyze Lambda metrics from CloudWatch Logs file.
    Integrates with k6 JSON to correlate with test phases.
    
    Args:
        lambda_log_file: Path to CloudWatch Logs file (JSON Lines format)
        k6_json_file: Path to k6 JSON results file
        test_mode: Test mode (smoke, full, saturation)
    
    Returns:
        Dictionary with Lambda metrics analysis
    """
    try:
        # Import Lambda metrics analyzer
        script_dir = os.path.dirname(os.path.abspath(__file__))
        sys.path.insert(0, script_dir)
        from analyze_lambda_metrics import analyze_lambda_metrics
        
        # Analyze Lambda metrics
        lambda_metrics = analyze_lambda_metrics(lambda_log_file)
        
        if 'error' in lambda_metrics:
            print(f"Warning: Lambda metrics analysis failed: {lambda_metrics.get('error')}", file=sys.stderr)
            return {}
        
        # Extract k6 start time for phase correlation
        k6_start_time = extract_test_start_time_from_k6_json(k6_json_file)
        
        # Get phase boundaries
        phase_boundaries = get_phase_boundaries(test_mode)
        
        # Convert Lambda metrics to resource metrics format
        # Lambda doesn't have CPU metrics, but we can use duration as a proxy
        # Memory metrics are available from Lambda
        
        result = {
            'test_mode': test_mode,
            'is_lambda': True,
            'k6_start_time': k6_start_time,
            'lambda_metrics': lambda_metrics,
            'overall': {
                'avg_cpu_percent': 0.0,  # Lambda doesn't expose CPU
                'max_cpu_percent': 0.0,
                'avg_memory_percent': lambda_metrics.get('memory', {}).get('utilization_percent', 0.0),
                'max_memory_percent': (lambda_metrics.get('memory', {}).get('max_used_mb', 0.0) / 
                                      lambda_metrics.get('memory', {}).get('allocated_mb', 1.0) * 100) if lambda_metrics.get('memory', {}).get('allocated_mb', 0) > 0 else 0.0,
                'avg_memory_mb': lambda_metrics.get('memory', {}).get('avg_used_mb', 0.0),
                'max_memory_mb': lambda_metrics.get('memory', {}).get('max_used_mb', 0.0),
                'memory_limit_mb': lambda_metrics.get('memory', {}).get('allocated_mb', 0.0),
                'total_samples': lambda_metrics.get('total_invocations', 0),
            },
            'phases': {},
        }
        
        # Add Lambda-specific metrics
        result['lambda_specific'] = {
            'cold_starts': lambda_metrics.get('cold_starts', 0),
            'warm_invocations': lambda_metrics.get('warm_invocations', 0),
            'cold_start_percentage': lambda_metrics.get('cold_start_percentage', 0.0),
            'avg_duration_ms': lambda_metrics.get('duration', {}).get('avg_ms', 0.0),
            'avg_init_duration_ms': lambda_metrics.get('cold_start', {}).get('init_duration', {}).get('avg_ms', 0.0),
        }
        
        return result
    
    except ImportError:
        print("Warning: analyze-lambda-metrics.py not found, skipping Lambda metrics analysis", file=sys.stderr)
        return {}
    except Exception as e:
        print(f"Warning: Failed to analyze Lambda metrics: {e}", file=sys.stderr)
        return {}


def analyze_resource_metrics(k6_json_file: str, metrics_csv_file: Optional[str] = None, test_mode: str = "smoke", test_run_id: Optional[int] = None, lambda_log_file: Optional[str] = None, is_lambda: bool = False) -> Dict:
    """Main analysis function - can read from database, CSV file, or Lambda CloudWatch Logs"""
    if not os.path.exists(k6_json_file):
        print(f"Error: k6 JSON file not found: {k6_json_file}", file=sys.stderr)
        return {}
    
    # For Lambda APIs, use Lambda metrics analyzer
    if is_lambda and lambda_log_file and os.path.exists(lambda_log_file):
        return analyze_lambda_metrics_from_logs(lambda_log_file, k6_json_file, test_mode)
    
    # Try to read from database first if test_run_id is provided
    metrics = []
    metrics_start_time = None
    
    if test_run_id:
        try:
            # Import db_client functions
            script_dir = os.path.dirname(os.path.abspath(__file__))
            sys.path.insert(0, script_dir)
            from db_client import get_resource_metrics
            
            # Get resource metrics from database
            db_metrics = get_resource_metrics(test_run_id)
            if db_metrics:
                # Convert database metrics to the format expected by the rest of the function
                metrics = [
                    {
                        'timestamp': m['timestamp'].timestamp() if hasattr(m['timestamp'], 'timestamp') else float(m['timestamp']),
                        'datetime': str(m['timestamp']),
                        'container': 'unknown',
                        'cpu_percent': float(m['cpu_percent']),
                        'memory_percent': float(m['memory_percent']),
                        'memory_used_mb': float(m['memory_used_mb']),
                        'memory_limit_mb': float(m.get('memory_limit_mb', 2048.0)),  # Default to 2048 if not in DB
                    }
                    for m in db_metrics
                ]
                # Use first metric timestamp as start time
                if metrics:
                    metrics_start_time = metrics[0]['timestamp']
        except Exception as e:
            print(f"Warning: Could not read from database ({e}), falling back to CSV", file=sys.stderr)
            metrics = []
    
    # Fall back to CSV if database read failed or test_run_id not provided
    if not metrics and metrics_csv_file and os.path.exists(metrics_csv_file):
        metrics_start_time = extract_metrics_start_time_from_csv(metrics_csv_file)
        metrics = parse_metrics_csv(metrics_csv_file)
    
    if not metrics:
        print("Warning: No metrics found in CSV file or database", file=sys.stderr)
        return {}
    
    # Get phase boundaries
    phase_boundaries = get_phase_boundaries(test_mode)
    if not phase_boundaries:
        print(f"Error: Unknown test mode: {test_mode}", file=sys.stderr)
        return {}
    
    # Extract start times
    k6_start_time = extract_test_start_time_from_k6_json(k6_json_file)
    
    if k6_start_time is None:
        print("Warning: Could not extract k6 start time, using metrics start time", file=sys.stderr)
        k6_start_time = metrics_start_time or 0.0
    
    if metrics_start_time is None:
        print("Warning: Could not extract metrics start time, using k6 start time", file=sys.stderr)
        metrics_start_time = k6_start_time or 0.0
    
    # Extract requests per phase
    phase_requests = extract_requests_per_phase_from_k6_json(k6_json_file, phase_boundaries, k6_start_time)
    
    # Calculate phase metrics
    phase_results = calculate_phase_metrics(metrics, phase_boundaries, metrics_start_time, k6_start_time)
    
    # Calculate derived metrics
    derived_metrics = calculate_derived_metrics(phase_results, phase_requests)
    
    # Calculate overall metrics
    all_cpu = [m['cpu_percent'] for m in metrics]
    all_memory_percent = [m['memory_percent'] for m in metrics]
    all_memory_mb = [m['memory_used_mb'] for m in metrics]
    
    # Extract memory_limit_mb from metrics (should be constant across all samples)
    # Use the first non-zero value, or default to 2048.0 if not found
    memory_limit_mb = 2048.0  # Default
    for m in metrics:
        if m.get('memory_limit_mb', 0.0) > 0:
            memory_limit_mb = m['memory_limit_mb']
            break
    
    result = {
        'test_mode': test_mode,
        'k6_start_time': k6_start_time,
        'metrics_start_time': metrics_start_time,
        'overall': {
            'avg_cpu_percent': sum(all_cpu) / len(all_cpu) if all_cpu else 0.0,
            'max_cpu_percent': max(all_cpu) if all_cpu else 0.0,
            'avg_memory_percent': sum(all_memory_percent) / len(all_memory_percent) if all_memory_percent else 0.0,
            'max_memory_percent': max(all_memory_percent) if all_memory_percent else 0.0,
            'avg_memory_mb': sum(all_memory_mb) / len(all_memory_mb) if all_memory_mb else 0.0,
            'max_memory_mb': max(all_memory_mb) if all_memory_mb else 0.0,
            'memory_limit_mb': memory_limit_mb,
            'total_samples': len(metrics),
        },
        'phases': {},
    }
    
    # Combine phase results with derived metrics
    for phase_num in sorted(phase_results.keys()):
        phase_data = phase_results[phase_num].copy()
        phase_data.update(derived_metrics.get(phase_num, {}))
        result['phases'][phase_num] = phase_data
    
    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: analyze-resource-metrics.py <k6_json_file> <test_mode> [metrics_csv_file] [test_run_id] [lambda_log_file] [--lambda]", file=sys.stderr)
        sys.exit(1)
    
    k6_json_file = sys.argv[1]
    test_mode = sys.argv[2]
    metrics_csv_file = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith('--') else None
    test_run_id = None
    lambda_log_file = None
    is_lambda = False
    
    # Parse arguments
    for i, arg in enumerate(sys.argv[3:], 3):
        if arg == '--lambda':
            is_lambda = True
        elif arg.isdigit():
            test_run_id = int(arg)
        elif arg.endswith('.log') or arg.endswith('.json'):
            lambda_log_file = arg
    
    result = analyze_resource_metrics(k6_json_file, metrics_csv_file, test_mode, test_run_id, lambda_log_file, is_lambda)
    
    if result:
        print(json.dumps(result, indent=2))
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()

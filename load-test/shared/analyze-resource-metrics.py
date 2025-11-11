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
        # Smoke test: single phase, ~30 seconds, 10 VUs
        phases = [
            (1, 30, 10),   # Single phase: 30s at 10 VUs
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
                'sample_count': 0,
            }
            continue
        
        cpu_values = [m['cpu_percent'] for m in phase_metrics]
        memory_percent_values = [m['memory_percent'] for m in phase_metrics]
        memory_mb_values = [m['memory_used_mb'] for m in phase_metrics]
        
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


def analyze_resource_metrics(k6_json_file: str, metrics_csv_file: str, test_mode: str) -> Dict:
    """Main analysis function"""
    if not os.path.exists(k6_json_file):
        print(f"Error: k6 JSON file not found: {k6_json_file}", file=sys.stderr)
        return {}
    
    if not os.path.exists(metrics_csv_file):
        print(f"Error: Metrics CSV file not found: {metrics_csv_file}", file=sys.stderr)
        return {}
    
    # Get phase boundaries
    phase_boundaries = get_phase_boundaries(test_mode)
    if not phase_boundaries:
        print(f"Error: Unknown test mode: {test_mode}", file=sys.stderr)
        return {}
    
    # Extract start times
    k6_start_time = extract_test_start_time_from_k6_json(k6_json_file)
    metrics_start_time = extract_metrics_start_time_from_csv(metrics_csv_file)
    
    if k6_start_time is None:
        print("Warning: Could not extract k6 start time, using metrics start time", file=sys.stderr)
        k6_start_time = metrics_start_time or 0.0
    
    if metrics_start_time is None:
        print("Warning: Could not extract metrics start time, using k6 start time", file=sys.stderr)
        metrics_start_time = k6_start_time or 0.0
    
    # Extract requests per phase
    phase_requests = extract_requests_per_phase_from_k6_json(k6_json_file, phase_boundaries, k6_start_time)
    
    # Parse metrics CSV
    metrics = parse_metrics_csv(metrics_csv_file)
    
    if not metrics:
        print("Warning: No metrics found in CSV file", file=sys.stderr)
        return {}
    
    # Calculate phase metrics
    phase_results = calculate_phase_metrics(metrics, phase_boundaries, metrics_start_time, k6_start_time)
    
    # Calculate derived metrics
    derived_metrics = calculate_derived_metrics(phase_results, phase_requests)
    
    # Calculate overall metrics
    all_cpu = [m['cpu_percent'] for m in metrics]
    all_memory_percent = [m['memory_percent'] for m in metrics]
    all_memory_mb = [m['memory_used_mb'] for m in metrics]
    
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
    if len(sys.argv) < 4:
        print("Usage: analyze-resource-metrics.py <k6_json_file> <metrics_csv_file> <test_mode>", file=sys.stderr)
        sys.exit(1)
    
    k6_json_file = sys.argv[1]
    metrics_csv_file = sys.argv[2]
    test_mode = sys.argv[3]
    
    result = analyze_resource_metrics(k6_json_file, metrics_csv_file, test_mode)
    
    if result:
        print(json.dumps(result, indent=2))
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()


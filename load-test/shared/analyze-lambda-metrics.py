#!/usr/bin/env python3
"""
Lambda Metrics Analyzer
Extracts Lambda-specific metrics from CloudWatch Logs and analyzes cold starts, duration, memory usage, etc.
"""

import json
import sys
import os
import re
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from pathlib import Path


def parse_lambda_report_line(line: str) -> Optional[Dict]:
    """
    Parse a Lambda REPORT log line to extract metrics.
    
    Example REPORT line:
    REPORT RequestId: abc123 Duration: 123.45 ms Billed Duration: 200 ms Memory Size: 512 MB Max Memory Used: 256 MB Init Duration: 50.12 ms
    
    Returns:
        Dictionary with parsed metrics or None if line is not a REPORT line
    """
    if not line.startswith('REPORT'):
        return None
    
    metrics = {}
    
    # Extract RequestId
    request_id_match = re.search(r'RequestId:\s+([a-f0-9-]+)', line)
    if request_id_match:
        metrics['request_id'] = request_id_match.group(1)
    
    # Extract Duration (ms)
    duration_match = re.search(r'Duration:\s+([\d.]+)\s*ms', line)
    if duration_match:
        metrics['duration_ms'] = float(duration_match.group(1))
    
    # Extract Billed Duration (ms)
    billed_duration_match = re.search(r'Billed Duration:\s+(\d+)\s*ms', line)
    if billed_duration_match:
        metrics['billed_duration_ms'] = int(billed_duration_match.group(1))
    
    # Extract Memory Size (MB)
    memory_size_match = re.search(r'Memory Size:\s+(\d+)\s*MB', line)
    if memory_size_match:
        metrics['memory_size_mb'] = int(memory_size_match.group(1))
    
    # Extract Max Memory Used (MB)
    max_memory_match = re.search(r'Max Memory Used:\s+(\d+)\s*MB', line)
    if max_memory_match:
        metrics['max_memory_used_mb'] = int(max_memory_match.group(1))
    
    # Extract Init Duration (ms) - only present in cold starts
    init_duration_match = re.search(r'Init Duration:\s+([\d.]+)\s*ms', line)
    if init_duration_match:
        metrics['init_duration_ms'] = float(init_duration_match.group(1))
        metrics['is_cold_start'] = True
    else:
        metrics['is_cold_start'] = False
    
    return metrics if metrics else None


def parse_cloudwatch_logs(log_file: str, start_time: Optional[datetime] = None, 
                          end_time: Optional[datetime] = None) -> List[Dict]:
    """
    Parse CloudWatch Logs file and extract Lambda metrics.
    
    Args:
        log_file: Path to CloudWatch Logs file (JSON Lines format or text)
        start_time: Optional start time filter
        end_time: Optional end time filter
    
    Returns:
        List of parsed Lambda invocation metrics
    """
    invocations = []
    
    try:
        with open(log_file, 'r') as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if not line:
                    continue
                
                # Try to parse as JSON Lines format first
                try:
                    log_entry = json.loads(line)
                    # Extract timestamp and message
                    timestamp_str = log_entry.get('timestamp', '')
                    message = log_entry.get('message', '')
                    
                    # Parse timestamp
                    try:
                        # CloudWatch Logs timestamp is in milliseconds
                        timestamp_ms = int(timestamp_str)
                        timestamp = datetime.fromtimestamp(timestamp_ms / 1000.0)
                    except (ValueError, TypeError):
                        # Try ISO format
                        try:
                            timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                        except:
                            timestamp = None
                    
                    # Apply time filters
                    if timestamp:
                        if start_time and timestamp < start_time:
                            continue
                        if end_time and timestamp > end_time:
                            continue
                    
                    # Parse REPORT line
                    if 'REPORT' in message:
                        metrics = parse_lambda_report_line(message)
                        if metrics:
                            metrics['timestamp'] = timestamp
                            metrics['log_line'] = line_num
                            invocations.append(metrics)
                
                except json.JSONDecodeError:
                    # Not JSON, try parsing as plain text log line
                    if 'REPORT' in line:
                        metrics = parse_lambda_report_line(line)
                        if metrics:
                            # Try to extract timestamp from line
                            timestamp = None
                            # Look for ISO timestamp in line
                            timestamp_match = re.search(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[\d.Z+-]*)', line)
                            if timestamp_match:
                                try:
                                    timestamp = datetime.fromisoformat(timestamp_match.group(1).replace('Z', '+00:00'))
                                except:
                                    pass
                            
                            metrics['timestamp'] = timestamp
                            metrics['log_line'] = line_num
                            invocations.append(metrics)
    
    except FileNotFoundError:
        print(f"Error: Log file not found: {log_file}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Error parsing log file {log_file}: {e}", file=sys.stderr)
        return []
    
    return invocations


def identify_cold_starts(invocations: List[Dict], inactivity_threshold_seconds: int = 900) -> List[Dict]:
    """
    Identify cold starts based on Init Duration and time gaps between invocations.
    
    Args:
        invocations: List of invocation metrics
        inactivity_threshold_seconds: Time gap in seconds to consider as cold start (default 15 minutes)
    
    Returns:
        List with cold start flags updated
    """
    if not invocations:
        return invocations
    
    # Sort by timestamp
    sorted_invocations = sorted(invocations, key=lambda x: x.get('timestamp') or datetime.min)
    
    previous_timestamp = None
    
    for inv in sorted_invocations:
        # If Init Duration is present, it's definitely a cold start
        if inv.get('init_duration_ms') is not None:
            inv['is_cold_start'] = True
            previous_timestamp = inv.get('timestamp')
            continue
        
        # Check time gap from previous invocation
        if previous_timestamp and inv.get('timestamp'):
            time_gap = (inv['timestamp'] - previous_timestamp).total_seconds()
            if time_gap >= inactivity_threshold_seconds:
                inv['is_cold_start'] = True
            else:
                inv['is_cold_start'] = inv.get('is_cold_start', False)
        else:
            # First invocation or no timestamp - assume cold start
            inv['is_cold_start'] = True
        
        previous_timestamp = inv.get('timestamp')
    
    return sorted_invocations


def calculate_lambda_metrics(invocations: List[Dict]) -> Dict:
    """
    Calculate aggregated Lambda metrics from invocations.
    
    Args:
        invocations: List of invocation metrics
    
    Returns:
        Dictionary with aggregated metrics
    """
    if not invocations:
        return {
            'total_invocations': 0,
            'cold_starts': 0,
            'warm_invocations': 0,
            'error': 'No invocations found'
        }
    
    cold_starts = [inv for inv in invocations if inv.get('is_cold_start', False)]
    warm_invocations = [inv for inv in invocations if not inv.get('is_cold_start', False)]
    
    # Overall metrics
    total_invocations = len(invocations)
    cold_start_count = len(cold_starts)
    warm_invocation_count = len(warm_invocations)
    
    # Duration metrics (all invocations)
    durations = [inv['duration_ms'] for inv in invocations if inv.get('duration_ms') is not None]
    
    # Cold start metrics
    cold_start_durations = [inv['duration_ms'] for inv in cold_starts if inv.get('duration_ms') is not None]
    init_durations = [inv['init_duration_ms'] for inv in cold_starts if inv.get('init_duration_ms') is not None]
    
    # Warm invocation metrics
    warm_durations = [inv['duration_ms'] for inv in warm_invocations if inv.get('duration_ms') is not None]
    
    # Memory metrics
    memory_sizes = [inv['memory_size_mb'] for inv in invocations if inv.get('memory_size_mb') is not None]
    max_memory_used = [inv['max_memory_used_mb'] for inv in invocations if inv.get('max_memory_used_mb') is not None]
    
    # Billed duration metrics
    billed_durations = [inv['billed_duration_ms'] for inv in invocations if inv.get('billed_duration_ms') is not None]
    
    def percentile(values: List[float], p: float) -> float:
        """Calculate percentile"""
        if not values:
            return 0.0
        sorted_values = sorted(values)
        index = int(len(sorted_values) * p / 100.0)
        index = min(index, len(sorted_values) - 1)
        return sorted_values[index]
    
    def average(values: List[float]) -> float:
        """Calculate average"""
        return sum(values) / len(values) if values else 0.0
    
    result = {
        'total_invocations': total_invocations,
        'cold_starts': cold_start_count,
        'warm_invocations': warm_invocation_count,
        'cold_start_percentage': (cold_start_count / total_invocations * 100) if total_invocations > 0 else 0.0,
        
        # Overall duration metrics
        'duration': {
            'avg_ms': average(durations),
            'min_ms': min(durations) if durations else 0.0,
            'max_ms': max(durations) if durations else 0.0,
            'p50_ms': percentile(durations, 50),
            'p95_ms': percentile(durations, 95),
            'p99_ms': percentile(durations, 99),
        },
        
        # Cold start metrics
        'cold_start': {
            'count': cold_start_count,
            'init_duration': {
                'avg_ms': average(init_durations),
                'min_ms': min(init_durations) if init_durations else 0.0,
                'max_ms': max(init_durations) if init_durations else 0.0,
                'p95_ms': percentile(init_durations, 95),
                'p99_ms': percentile(init_durations, 99),
            },
            'total_duration': {
                'avg_ms': average(cold_start_durations),
                'min_ms': min(cold_start_durations) if cold_start_durations else 0.0,
                'max_ms': max(cold_start_durations) if cold_start_durations else 0.0,
                'p95_ms': percentile(cold_start_durations, 95),
                'p99_ms': percentile(cold_start_durations, 99),
            },
        },
        
        # Warm invocation metrics
        'warm_invocation': {
            'count': warm_invocation_count,
            'duration': {
                'avg_ms': average(warm_durations),
                'min_ms': min(warm_durations) if warm_durations else 0.0,
                'max_ms': max(warm_durations) if warm_durations else 0.0,
                'p50_ms': percentile(warm_durations, 50),
                'p95_ms': percentile(warm_durations, 95),
                'p99_ms': percentile(warm_durations, 99),
            },
        },
        
        # Memory metrics
        'memory': {
            'allocated_mb': memory_sizes[0] if memory_sizes else 0,
            'max_used_mb': max(max_memory_used) if max_memory_used else 0.0,
            'avg_used_mb': average(max_memory_used),
            'utilization_percent': (average(max_memory_used) / memory_sizes[0] * 100) if memory_sizes and memory_sizes[0] > 0 else 0.0,
        },
        
        # Billed duration metrics
        'billed_duration': {
            'avg_ms': average(billed_durations),
            'total_ms': sum(billed_durations),
            'total_seconds': sum(billed_durations) / 1000.0,
        },
    }
    
    return result


def analyze_lambda_metrics(log_file: str, start_time: Optional[datetime] = None,
                           end_time: Optional[datetime] = None,
                           inactivity_threshold_seconds: int = 900) -> Dict:
    """
    Main function to analyze Lambda metrics from CloudWatch Logs.
    
    Args:
        log_file: Path to CloudWatch Logs file
        start_time: Optional start time filter
        end_time: Optional end time filter
        inactivity_threshold_seconds: Time gap to consider as cold start
    
    Returns:
        Dictionary with analyzed metrics
    """
    # Parse log file
    invocations = parse_cloudwatch_logs(log_file, start_time, end_time)
    
    if not invocations:
        return {
            'error': 'No Lambda invocations found in log file',
            'log_file': log_file
        }
    
    # Identify cold starts
    invocations = identify_cold_starts(invocations, inactivity_threshold_seconds)
    
    # Calculate aggregated metrics
    metrics = calculate_lambda_metrics(invocations)
    
    # Add metadata
    metrics['log_file'] = log_file
    metrics['start_time'] = start_time.isoformat() if start_time else None
    metrics['end_time'] = end_time.isoformat() if end_time else None
    metrics['inactivity_threshold_seconds'] = inactivity_threshold_seconds
    
    return metrics


def main():
    """CLI entry point"""
    if len(sys.argv) < 2:
        print("Usage: analyze-lambda-metrics.py <log_file> [start_time] [end_time] [inactivity_threshold]", file=sys.stderr)
        print("  log_file: Path to CloudWatch Logs file", file=sys.stderr)
        print("  start_time: Optional start time filter (ISO format)", file=sys.stderr)
        print("  end_time: Optional end time filter (ISO format)", file=sys.stderr)
        print("  inactivity_threshold: Seconds of inactivity to consider cold start (default: 900)", file=sys.stderr)
        sys.exit(1)
    
    log_file = sys.argv[1]
    start_time = None
    end_time = None
    inactivity_threshold = 900
    
    if len(sys.argv) > 2:
        try:
            start_time = datetime.fromisoformat(sys.argv[2].replace('Z', '+00:00'))
        except ValueError:
            print(f"Warning: Invalid start_time format: {sys.argv[2]}", file=sys.stderr)
    
    if len(sys.argv) > 3:
        try:
            end_time = datetime.fromisoformat(sys.argv[3].replace('Z', '+00:00'))
        except ValueError:
            print(f"Warning: Invalid end_time format: {sys.argv[3]}", file=sys.stderr)
    
    if len(sys.argv) > 4:
        try:
            inactivity_threshold = int(sys.argv[4])
        except ValueError:
            print(f"Warning: Invalid inactivity_threshold: {sys.argv[4]}", file=sys.stderr)
    
    # Analyze metrics
    metrics = analyze_lambda_metrics(log_file, start_time, end_time, inactivity_threshold)
    
    # Output as JSON
    print(json.dumps(metrics, indent=2, default=str))
    
    if 'error' in metrics:
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()

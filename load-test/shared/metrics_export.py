#!/usr/bin/env python3
"""
Export Metrics
Export test run metrics to CSV or JSON format
"""
import sys
import os
import json
import csv
from datetime import datetime
from pathlib import Path

# Add script directory to path
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

from db_client import get_latest_test_runs, get_resource_metrics, get_test_phases, test_connection


def export_to_csv(test_run_id, output_file):
    """Export a test run's metrics to CSV"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    # Get test run info
    runs = get_latest_test_runs(limit=1000)
    test_run = next((r for r in runs if r['id'] == test_run_id), None)
    
    if not test_run:
        print(f"Error: Test run {test_run_id} not found.", file=sys.stderr)
        sys.exit(1)
    
    # Get resource metrics
    resource_metrics = get_resource_metrics(test_run_id)
    
    # Write CSV
    with open(output_file, 'w', newline='') as f:
        writer = csv.writer(f)
        
        # Header
        writer.writerow(['Test Run ID', test_run_id])
        writer.writerow(['API', test_run.get('api_name', '')])
        writer.writerow(['Test Mode', test_run.get('test_mode', '')])
        writer.writerow(['Payload Size', test_run.get('payload_size', '')])
        writer.writerow(['Protocol', test_run.get('protocol', '')])
        writer.writerow(['Status', test_run.get('status', '')])
        writer.writerow(['Started', test_run.get('started_at', '')])
        writer.writerow(['Completed', test_run.get('completed_at', '')])
        writer.writerow([])
        
        # Performance metrics
        writer.writerow(['Performance Metrics'])
        writer.writerow(['Total Samples', test_run.get('total_samples', 0)])
        writer.writerow(['Success Samples', test_run.get('success_samples', 0)])
        writer.writerow(['Error Samples', test_run.get('error_samples', 0)])
        writer.writerow(['Throughput (req/s)', test_run.get('throughput_req_per_sec', 0)])
        writer.writerow(['Avg Response Time (ms)', test_run.get('avg_response_time_ms', 0)])
        writer.writerow(['Error Rate (%)', test_run.get('error_rate_percent', 0)])
        writer.writerow([])
        
        # Resource metrics
        writer.writerow(['Resource Metrics'])
        writer.writerow(['Timestamp', 'CPU %', 'Memory %', 'Memory Used (MB)', 'Memory Limit (MB)'])
        for metric in resource_metrics:
            writer.writerow([
                metric.get('timestamp', ''),
                metric.get('cpu_percent', 0),
                metric.get('memory_percent', 0),
                metric.get('memory_used_mb', 0),
                metric.get('memory_limit_mb', 0)
            ])
    
    print(f"Exported test run {test_run_id} to {output_file}")


def export_to_json(test_run_id, output_file):
    """Export a test run's metrics to JSON"""
    if not test_connection():
        print("Error: Cannot connect to database.", file=sys.stderr)
        sys.exit(1)
    
    # Get test run info
    runs = get_latest_test_runs(limit=1000)
    test_run = next((r for r in runs if r['id'] == test_run_id), None)
    
    if not test_run:
        print(f"Error: Test run {test_run_id} not found.", file=sys.stderr)
        sys.exit(1)
    
    # Get resource metrics and phases
    resource_metrics = get_resource_metrics(test_run_id)
    phases = get_test_phases(test_run_id)
    
    # Build export data
    export_data = {
        'test_run': {
            'id': test_run.get('id'),
            'api_name': test_run.get('api_name'),
            'test_mode': test_run.get('test_mode'),
            'payload_size': test_run.get('payload_size'),
            'protocol': test_run.get('protocol'),
            'status': test_run.get('status'),
            'started_at': str(test_run.get('started_at', '')),
            'completed_at': str(test_run.get('completed_at', '')),
            'duration_seconds': float(test_run.get('duration_seconds', 0)) if test_run.get('duration_seconds') else None,
        },
        'performance_metrics': {
            'total_samples': test_run.get('total_samples', 0),
            'success_samples': test_run.get('success_samples', 0),
            'error_samples': test_run.get('error_samples', 0),
            'throughput_req_per_sec': float(test_run.get('throughput_req_per_sec', 0)) if test_run.get('throughput_req_per_sec') else 0,
            'avg_response_time_ms': float(test_run.get('avg_response_time_ms', 0)) if test_run.get('avg_response_time_ms') else 0,
            'min_response_time_ms': float(test_run.get('min_response_time_ms', 0)) if test_run.get('min_response_time_ms') else 0,
            'max_response_time_ms': float(test_run.get('max_response_time_ms', 0)) if test_run.get('max_response_time_ms') else 0,
            'error_rate_percent': float(test_run.get('error_rate_percent', 0)) if test_run.get('error_rate_percent') else 0,
        },
        'resource_metrics': [
            {
                'timestamp': str(m.get('timestamp', '')),
                'cpu_percent': float(m.get('cpu_percent', 0)),
                'memory_percent': float(m.get('memory_percent', 0)),
                'memory_used_mb': float(m.get('memory_used_mb', 0)),
                'memory_limit_mb': float(m.get('memory_limit_mb', 0)),
            }
            for m in resource_metrics
        ],
        'phases': [
            {
                'phase_number': p.get('phase_number'),
                'phase_name': p.get('phase_name'),
                'target_vus': p.get('target_vus', 0),
                'requests_count': p.get('requests_count', 0),
                'avg_cpu_percent': float(p.get('avg_cpu_percent', 0)),
                'max_cpu_percent': float(p.get('max_cpu_percent', 0)),
                'avg_memory_mb': float(p.get('avg_memory_mb', 0)),
                'max_memory_mb': float(p.get('max_memory_mb', 0)),
            }
            for p in phases
        ]
    }
    
    # Write JSON
    with open(output_file, 'w') as f:
        json.dump(export_data, f, indent=2, default=str)
    
    print(f"Exported test run {test_run_id} to {output_file}")


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Export test run metrics to CSV or JSON')
    parser.add_argument('test_run_id', type=int, help='Test run ID to export')
    parser.add_argument('output_file', help='Output file path')
    parser.add_argument('--format', choices=['csv', 'json'], default='json', help='Export format (default: json)')
    
    args = parser.parse_args()
    
    if args.format == 'csv':
        export_to_csv(args.test_run_id, args.output_file)
    else:
        export_to_json(args.test_run_id, args.output_file)


if __name__ == '__main__':
    main()


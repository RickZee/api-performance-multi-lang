#!/usr/bin/env python3
"""
Import test results from JSON and CSV files into the database
"""
import sys
import os
from pathlib import Path
from datetime import datetime
import re

# Add script directory to path
script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir))

from db_client import (
    create_test_run, 
    insert_performance_metrics, 
    update_test_run_completion,
    insert_resource_metric_cli
)
from extract_k6_metrics import extract_metrics
import csv

def parse_filename(filename):
    """Parse API name, test mode, payload size from filename"""
    # Pattern: producer-api-{lang}-{protocol}-throughput-{mode}-{payload}-{timestamp}.json
    pattern = r'producer-api-(\w+)-(rest|grpc)-throughput-(smoke|full|saturation)-?(\d+k)?-(\d{8}_\d{6})\.json'
    match = re.match(pattern, filename)
    if match:
        lang, protocol, mode, payload, timestamp = match.groups()
        api_name = f'producer-api-{lang}-{protocol}'
        payload_size = payload or 'default'
        return api_name, mode, payload_size, protocol, timestamp
    return None, None, None, None, None

def import_json_file(json_file_path):
    """Import a single JSON test result file into database"""
    json_file = Path(json_file_path)
    if not json_file.exists():
        print(f"Error: File not found: {json_file_path}", file=sys.stderr)
        return False
    
    filename = json_file.name
    api_name, test_mode, payload_size, protocol, timestamp = parse_filename(filename)
    
    if not api_name:
        print(f"Warning: Could not parse filename: {filename}", file=sys.stderr)
        return False
    
    # Extract metrics
    try:
        import subprocess
        result = subprocess.run(
            [sys.executable, str(script_dir / 'extract_k6_metrics.py'), str(json_file)],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"Warning: Could not extract metrics from {filename}", file=sys.stderr)
            return False
        metrics_output = result.stdout.strip()
        if not metrics_output:
            print(f"Warning: Empty metrics output from {filename}", file=sys.stderr)
            return False
        
        parts = metrics_output.strip().split('|')
        if len(parts) < 8:
            print(f"Warning: Invalid metrics format from {filename}", file=sys.stderr)
            return False
        
        total_samples = int(parts[0])
        success_samples = int(parts[1])
        error_samples = int(parts[2])
        duration_seconds = float(parts[3])
        throughput = float(parts[4])
        avg_response = float(parts[5])
        min_response = float(parts[6])
        max_response = float(parts[7])
        
        # Calculate error rate
        error_rate = 0.0
        if total_samples > 0:
            error_rate = (error_samples / total_samples) * 100
        
        # Create test run
        test_run_id = create_test_run(
            api_name=api_name,
            test_mode=test_mode,
            payload_size=payload_size,
            protocol=protocol,
            k6_json_file_path=str(json_file)
        )
        
        # Insert performance metrics
        insert_performance_metrics(
            test_run_id=test_run_id,
            total_samples=total_samples,
            success_samples=success_samples,
            error_samples=error_samples,
            throughput_req_per_sec=throughput,
            avg_response_time_ms=avg_response,
            min_response_time_ms=min_response,
            max_response_time_ms=max_response,
            p50_response_time_ms=None,
            p90_response_time_ms=None,
            p95_response_time_ms=None,
            p99_response_time_ms=None,
            error_rate_percent=error_rate
        )
        
        # Update test run completion
        update_test_run_completion(
            test_run_id=test_run_id,
            status='completed',
            duration_seconds=duration_seconds
        )
        
        print(f"✓ Imported {api_name} ({test_mode}, {payload_size}): {total_samples} samples, {throughput:.2f} req/s")
        return test_run_id
        
    except Exception as e:
        print(f"Error importing {filename}: {e}", file=sys.stderr)
        return False

def import_csv_metrics(csv_file_path, test_run_id):
    """Import resource metrics from CSV file"""
    csv_file = Path(csv_file_path)
    if not csv_file.exists():
        return False
    
    try:
        with open(csv_file, 'r') as f:
            # Skip comment lines
            lines = []
            for line in f:
                if not line.strip().startswith('#'):
                    lines.append(line)
            
            if not lines:
                return False
            
            reader = csv.DictReader(lines)
            count = 0
            for row in reader:
                try:
                    timestamp_str = row.get('timestamp', '') or row.get('datetime', '')
                    if not timestamp_str:
                        continue
                    
                    # Parse timestamp
                    try:
                        timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
                    except:
                        timestamp = datetime.strptime(timestamp_str, '%Y-%m-%d %H:%M:%S')
                    
                    cpu_percent = float(row.get('cpu_percent', 0) or 0)
                    memory_percent = float(row.get('memory_percent', 0) or 0)
                    memory_used_mb = float(row.get('memory_used_mb', 0) or 0)
                    memory_limit_mb = float(row.get('memory_limit_mb', 0) or 2048)
                    
                    insert_resource_metric_cli(
                        test_run_id=test_run_id,
                        timestamp=timestamp.isoformat(),
                        cpu_percent=cpu_percent,
                        memory_percent=memory_percent,
                        memory_used_mb=memory_used_mb,
                        memory_limit_mb=memory_limit_mb
                    )
                    count += 1
                except Exception as e:
                    continue  # Skip invalid rows
            
            if count > 0:
                print(f"  → Imported {count} resource metric samples")
                return True
    except Exception as e:
        print(f"  → Warning: Could not import CSV metrics: {e}", file=sys.stderr)
        return False
    
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: import_test_results.py <results_directory> [timestamp_pattern]")
        print("Example: import_test_results.py load-test/results/throughput-sequential 20251116_132933")
        sys.exit(1)
    
    results_dir = Path(sys.argv[1])
    timestamp_pattern = sys.argv[2] if len(sys.argv) > 2 else None
    
    if not results_dir.exists():
        print(f"Error: Results directory not found: {results_dir}", file=sys.stderr)
        sys.exit(1)
    
    # Find all JSON files
    if timestamp_pattern:
        json_files = list(results_dir.rglob(f"*{timestamp_pattern}*.json"))
    else:
        json_files = list(results_dir.rglob("*-throughput-*.json"))
    
    if not json_files:
        print(f"No JSON files found in {results_dir}")
        sys.exit(1)
    
    print(f"Found {len(json_files)} JSON files to import")
    print()
    
    imported = 0
    for json_file in sorted(json_files):
        test_run_id = import_json_file(json_file)
        if test_run_id:
            imported += 1
            # Try to import corresponding CSV metrics file
            csv_file = json_file.parent / json_file.name.replace('.json', '-metrics.csv')
            if csv_file.exists():
                import_csv_metrics(csv_file, test_run_id)
    
    print()
    print(f"Successfully imported {imported} test runs")

if __name__ == '__main__':
    main()


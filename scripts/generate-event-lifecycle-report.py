#!/usr/bin/env python3
"""
Generate detailed lifecycle report for events from k6 test output and Lambda logs.

This script:
1. Reads events from k6 output JSON file
2. Fetches Lambda logs for each event
3. Generates a detailed lifecycle report showing:
   - Request timeline
   - Response codes
   - Processing stages
   - Duration breakdown
   - Errors (if any)
"""

import json
import sys
import argparse
import subprocess
from datetime import datetime
from typing import Dict, List, Any, Optional
from collections import defaultdict

def parse_args():
    parser = argparse.ArgumentParser(description='Generate detailed event lifecycle report')
    parser.add_argument('--events-file', required=True, help='Path to k6 events JSON file')
    parser.add_argument('--lambda-name', required=True, help='Lambda function name')
    parser.add_argument('--output', help='Output file path (default: stdout)')
    parser.add_argument('--format', choices=['json', 'text', 'html'], default='text',
                       help='Output format (default: text)')
    parser.add_argument('--since', default='1h', help='Time range for log search (default: 1h)')
    return parser.parse_args()

def fetch_lambda_logs(lambda_name: str, event_id: str, since: str = '1h') -> List[str]:
    """Fetch Lambda logs for a specific event ID."""
    try:
        cmd = [
            'aws', 'logs', 'tail',
            f'/aws/lambda/{lambda_name}',
            '--since', since,
            '--format', 'short',
            '--filter-pattern', event_id
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return result.stdout.strip().split('\n')
        return []
    except Exception as e:
        print(f"Error fetching logs for {event_id}: {e}", file=sys.stderr)
        return []

def parse_lifecycle_from_logs(log_lines: List[str], event_id: str) -> Dict[str, Any]:
    """Parse lifecycle information from log lines."""
    lifecycle = {
        'stages': {},
        'errors': [],
        'timestamps': []
    }
    
    for line in log_lines:
        if '[LIFECYCLE]' in line:
            # Extract stage information
            if 'Event processing started' in line:
                lifecycle['stages']['start'] = {'status': 'started'}
            elif 'JSON parsed' in line:
                lifecycle['stages']['json_parsed'] = {'status': 'completed'}
            elif 'Event object created' in line:
                lifecycle['stages']['event_created'] = {'status': 'completed'}
            elif 'Validation passed' in line:
                lifecycle['stages']['validation'] = {'status': 'passed'}
            elif 'Service initialized' in line:
                lifecycle['stages']['service_init'] = {'status': 'completed'}
            elif 'Event processed successfully' in line:
                lifecycle['stages']['processing'] = {'status': 'completed'}
        
        if 'ERROR' in line or 'WARNING' in line:
            lifecycle['errors'].append(line.strip())
    
    return lifecycle

def generate_text_report(events: List[Dict], lambda_name: str, since: str) -> str:
    """Generate text format report."""
    report = []
    report.append("=" * 80)
    report.append("EVENT LIFECYCLE REPORT")
    report.append("=" * 80)
    report.append(f"Lambda: {lambda_name}")
    report.append(f"Total Events: {len(events)}")
    report.append(f"Generated: {datetime.now().isoformat()}")
    report.append("")
    
    # Summary statistics
    status_counts = defaultdict(int)
    for event in events:
        status = event.get('status', 'unknown')
        status_counts[status] += 1
    
    report.append("SUMMARY")
    report.append("-" * 80)
    for status, count in sorted(status_counts.items()):
        report.append(f"  {status}: {count}")
    report.append("")
    
    # Detailed event reports
    report.append("DETAILED EVENT REPORTS")
    report.append("=" * 80)
    
    for idx, event in enumerate(events, 1):
        report.append(f"\nEvent #{idx}")
        report.append("-" * 80)
        report.append(f"UUID: {event.get('uuid', 'N/A')}")
        report.append(f"Event Name: {event.get('eventName', 'N/A')}")
        report.append(f"Event Type: {event.get('eventType', 'N/A')}")
        report.append(f"Entity Type: {event.get('entityType', 'N/A')}")
        report.append(f"Entity ID: {event.get('entityId', 'N/A')}")
        report.append(f"Status: {event.get('status', 'N/A')}")
        report.append(f"Success: {event.get('success', False)}")
        report.append(f"Timestamp: {event.get('timestamp', 'N/A')}")
        report.append(f"VU ID: {event.get('vuId', 'N/A')}")
        report.append(f"Iteration: {event.get('iteration', 'N/A')}")
        
        # Fetch and parse logs
        event_id = event.get('uuid', '')
        if event_id:
            log_lines = fetch_lambda_logs(lambda_name, event_id, since)
            lifecycle = parse_lifecycle_from_logs(log_lines, event_id)
            
            if lifecycle['stages']:
                report.append("\nLifecycle Stages:")
                for stage, info in lifecycle['stages'].items():
                    report.append(f"  - {stage}: {info.get('status', 'N/A')}")
            
            if lifecycle['errors']:
                report.append("\nErrors:")
                for error in lifecycle['errors'][:5]:  # Limit to 5 errors
                    report.append(f"  - {error}")
    
    return "\n".join(report)

def generate_json_report(events: List[Dict], lambda_name: str, since: str) -> str:
    """Generate JSON format report."""
    report = {
        'metadata': {
            'lambda_name': lambda_name,
            'total_events': len(events),
            'generated_at': datetime.now().isoformat(),
            'log_search_since': since
        },
        'summary': {},
        'events': []
    }
    
    # Calculate summary
    status_counts = defaultdict(int)
    for event in events:
        status = event.get('status', 'unknown')
        status_counts[status] += 1
    
    report['summary'] = dict(status_counts)
    
    # Add detailed event information
    for event in events:
        event_report = event.copy()
        event_id = event.get('uuid', '')
        
        if event_id:
            log_lines = fetch_lambda_logs(lambda_name, event_id, since)
            lifecycle = parse_lifecycle_from_logs(log_lines, event_id)
            event_report['lifecycle'] = lifecycle
        
        report['events'].append(event_report)
    
    return json.dumps(report, indent=2)

def main():
    args = parse_args()
    
    # Load events from file
    try:
        with open(args.events_file, 'r') as f:
            events = json.load(f)
    except Exception as e:
        print(f"Error loading events file: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Generate report
    if args.format == 'json':
        report = generate_json_report(events, args.lambda_name, args.since)
    else:
        report = generate_text_report(events, args.lambda_name, args.since)
    
    # Output report
    if args.output:
        with open(args.output, 'w') as f:
            f.write(report)
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(report)

if __name__ == '__main__':
    main()


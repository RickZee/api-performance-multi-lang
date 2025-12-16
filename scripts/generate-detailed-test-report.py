#!/usr/bin/env python3
"""
Generate comprehensive test report with success/failure scenarios and lifecycle details.
"""

import json
import sys
import argparse
import subprocess
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Any

def parse_args():
    parser = argparse.ArgumentParser(description='Generate detailed test report')
    parser.add_argument('--events-file', required=True, help='Path to k6 events JSON file')
    parser.add_argument('--lambda-name', help='Lambda function name for log analysis')
    parser.add_argument('--output', help='Output file path (default: stdout)')
    parser.add_argument('--format', choices=['text', 'json', 'markdown'], default='text')
    return parser.parse_args()

def analyze_events(events: List[Dict]) -> Dict[str, Any]:
    """Analyze events and generate statistics."""
    analysis = {
        'total': len(events),
        'success': [],
        'failed': [],
        'by_status': defaultdict(int),
        'by_type': defaultdict(lambda: {'success': 0, 'failed': 0}),
        'by_vu': defaultdict(lambda: {'success': 0, 'failed': 0}),
    }
    
    for event in events:
        is_success = event.get('success', False)
        status = event.get('status', 'unknown')
        etype = event.get('eventType', 'unknown')
        vu_id = event.get('vuId', 'unknown')
        
        analysis['by_status'][status] += 1
        
        if is_success:
            analysis['success'].append(event)
            analysis['by_type'][etype]['success'] += 1
            analysis['by_vu'][vu_id]['success'] += 1
        else:
            analysis['failed'].append(event)
            analysis['by_type'][etype]['failed'] += 1
            analysis['by_vu'][vu_id]['failed'] += 1
    
    return analysis

def generate_text_report(analysis: Dict, events_file: str) -> str:
    """Generate text format report."""
    report = []
    report.append("=" * 80)
    report.append("COMPREHENSIVE LOAD TEST REPORT")
    report.append("=" * 80)
    report.append(f"Generated: {datetime.now().isoformat()}")
    report.append(f"Events File: {events_file}")
    report.append("")
    
    # Executive Summary
    report.append("EXECUTIVE SUMMARY")
    report.append("-" * 80)
    total = analysis['total']
    success_count = len(analysis['success'])
    failed_count = len(analysis['failed'])
    success_rate = (success_count / total * 100) if total > 0 else 0
    
    report.append(f"Total Events Analyzed: {total}")
    report.append(f"✅ Successful: {success_count} ({success_rate:.1f}%)")
    report.append(f"❌ Failed: {failed_count} ({failed_count/total*100:.1f}%)" if total > 0 else "❌ Failed: 0")
    report.append("")
    
    # Status Code Breakdown
    report.append("STATUS CODE DISTRIBUTION")
    report.append("-" * 80)
    for status, count in sorted(analysis['by_status'].items()):
        pct = (count / total * 100) if total > 0 else 0
        report.append(f"  HTTP {status}: {count} events ({pct:.1f}%)")
    report.append("")
    
    # Success Scenarios
    report.append("SUCCESS SCENARIOS")
    report.append("=" * 80)
    if analysis['success']:
        report.append(f"All {len(analysis['success'])} events were successfully processed.")
        report.append("")
        
        report.append("Success by Event Type:")
        for etype, counts in sorted(analysis['by_type'].items()):
            total_type = counts['success'] + counts['failed']
            if total_type > 0:
                success_pct = (counts['success'] / total_type * 100) if total_type > 0 else 0
                report.append(f"  {etype}: {counts['success']}/{total_type} ({success_pct:.1f}%)")
        report.append("")
        
        report.append("Success by Virtual User:")
        for vu_id, counts in sorted(analysis['by_vu'].items()):
            total_vu = counts['success'] + counts['failed']
            if total_vu > 0:
                success_pct = (counts['success'] / total_vu * 100) if total_vu > 0 else 0
                report.append(f"  VU {vu_id}: {counts['success']}/{total_vu} ({success_pct:.1f}%)")
        report.append("")
        
        # Sample successful events
        report.append("Sample Successful Events:")
        report.append("-" * 80)
        for idx, event in enumerate(analysis['success'][:10], 1):
            report.append(f"\nEvent #{idx}:")
            report.append(f"  UUID: {event.get('uuid', 'N/A')}")
            report.append(f"  Type: {event.get('eventType', 'N/A')}")
            report.append(f"  Entity: {event.get('entityType', 'N/A')} - {event.get('entityId', 'N/A')[:40]}...")
            report.append(f"  Status: {event.get('status', 'N/A')}")
            report.append(f"  Timestamp: {event.get('timestamp', 'N/A')}")
            report.append(f"  VU ID: {event.get('vuId', 'N/A')}")
            report.append(f"  Iteration: {event.get('iteration', 'N/A')}")
    else:
        report.append("No successful events found.")
    report.append("")
    
    # Failure Scenarios
    report.append("FAILURE SCENARIOS")
    report.append("=" * 80)
    if analysis['failed']:
        report.append(f"Found {len(analysis['failed'])} failed events.")
        report.append("")
        
        # Group by failure reason
        fail_by_status = defaultdict(list)
        for event in analysis['failed']:
            status = event.get('status', 'unknown')
            fail_by_status[status].append(event)
        
        report.append("Failure Breakdown by Status Code:")
        for status, events_list in sorted(fail_by_status.items()):
            report.append(f"  HTTP {status}: {len(events_list)} events")
            if events_list:
                report.append(f"    Sample UUID: {events_list[0].get('uuid', 'N/A')[:40]}...")
        report.append("")
        
        report.append("Sample Failed Events:")
        report.append("-" * 80)
        for idx, event in enumerate(analysis['failed'][:10], 1):
            report.append(f"\nFailed Event #{idx}:")
            report.append(f"  UUID: {event.get('uuid', 'N/A')}")
            report.append(f"  Type: {event.get('eventType', 'N/A')}")
            report.append(f"  Status: {event.get('status', 'N/A')}")
            report.append(f"  Timestamp: {event.get('timestamp', 'N/A')}")
            report.append(f"  VU ID: {event.get('vuId', 'N/A')}")
    else:
        report.append("✅ No failures detected in extracted events.")
    report.append("")
    
    # Recommendations
    report.append("RECOMMENDATIONS")
    report.append("=" * 80)
    if success_rate >= 95:
        report.append("✅ Excellent success rate. System is performing well.")
    elif success_rate >= 90:
        report.append("⚠️  Good success rate, but investigate missing events.")
    else:
        report.append("❌ Success rate below acceptable threshold. Investigate failures.")
    report.append("")
    
    return "\n".join(report)

def main():
    args = parse_args()
    
    # Load events
    try:
        with open(args.events_file, 'r') as f:
            events = json.load(f)
    except Exception as e:
        print(f"Error loading events: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Analyze events
    analysis = analyze_events(events)
    
    # Generate report
    if args.format == 'text':
        report = generate_text_report(analysis, args.events_file)
    else:
        report = json.dumps(analysis, indent=2)
    
    # Output report
    if args.output:
        with open(args.output, 'w') as f:
            f.write(report)
        print(f"Report written to {args.output}", file=sys.stderr)
    else:
        print(report)

if __name__ == '__main__':
    main()


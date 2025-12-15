#!/usr/bin/env python3
"""Analyze k6 output to understand failure patterns."""

import sys
import json
import re
from collections import defaultdict

def analyze_k6_output(input_file):
    """Analyze k6 output file for event status patterns."""
    status_counts = defaultdict(int)
    events_by_status = defaultdict(list)
    total_events = 0
    successful_events = 0
    failed_events = 0
    
    with open(input_file, 'r') as f:
        for line in f:
            if 'K6_EVENT:' in line:
                total_events += 1
                # Extract JSON from K6_EVENT line
                start_idx = line.find('K6_EVENT: ')
                if start_idx != -1:
                    json_start = start_idx + len('K6_EVENT: ')
                    # Find end of JSON
                    for end_marker in ['" source', ' source=', '\n', '\r']:
                        end_idx = line.find(end_marker, json_start)
                        if end_idx != -1:
                            event_json = line[json_start:end_idx].strip().rstrip('"').rstrip("'")
                            break
                    else:
                        event_json = line[json_start:].strip().rstrip('"').rstrip("'")
                    
                    try:
                        event = json.loads(event_json)
                        status = event.get('status', 'unknown')
                        success = event.get('success', False)
                        status_counts[status] += 1
                        events_by_status[status].append(event)
                        
                        if success or status == 200:
                            successful_events += 1
                        else:
                            failed_events += 1
                    except json.JSONDecodeError:
                        pass
    
    print(f"Total events logged: {total_events}")
    print(f"Successful events (200): {successful_events}")
    print(f"Failed events (non-200): {failed_events}")
    print(f"\nStatus breakdown:")
    for status, count in sorted(status_counts.items()):
        percentage = (count / total_events * 100) if total_events > 0 else 0
        print(f"  Status {status}: {count} ({percentage:.1f}%)")
    
    # Analyze failure patterns
    if 409 in status_counts:
        print(f"\n409 Conflicts: {status_counts[409]} events")
        print("  These are duplicate event IDs (likely due to incomplete database clearing)")
    
    if failed_events > 0:
        print(f"\n⚠️  {failed_events} events failed out of {total_events} total")
        print("   This explains why only successful events are in the extracted JSON file")
    
    return {
        'total': total_events,
        'successful': successful_events,
        'failed': failed_events,
        'status_counts': dict(status_counts)
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: analyze-k6-failures.py <k6-output-file>")
        sys.exit(1)
    
    input_file = sys.argv[1]
    analyze_k6_output(input_file)

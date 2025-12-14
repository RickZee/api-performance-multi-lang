#!/usr/bin/env python3
"""Extract events from k6 output and save to JSON file."""

import sys
import json
import codecs
import argparse

def extract_events(input_file=None, output_file=None):
    """Extract K6_EVENT lines from input and save to JSON file."""
    events = []
    
    # Read from stdin or file
    if input_file:
        with open(input_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    else:
        lines = sys.stdin
    
    # Process each line
    for line in lines:
        # Output original line (pass through)
        if not input_file:
            sys.stdout.write(line)
            sys.stdout.flush()
        
        # Find K6_EVENT lines
        if 'K6_EVENT:' in line:
            start_idx = line.find('K6_EVENT: ')
            if start_idx != -1:
                json_start = start_idx + len('K6_EVENT: ')
                source_idx = line.find('" source', json_start)
                if source_idx != -1:
                    event_json = line[json_start:source_idx].strip().rstrip('"')
                    try:
                        # Try parsing directly first
                        event = json.loads(event_json)
                        events.append(event)
                    except json.JSONDecodeError:
                        # If that fails, try unescaping (for escaped quotes)
                        try:
                            decoded = codecs.decode(event_json, 'unicode_escape')
                            event = json.loads(decoded)
                            events.append(event)
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            # Skip invalid JSON
                            pass
    
    # Write events to file
    if output_file:
        with open(output_file, 'w') as f:
            json.dump(events, f, indent=2)
        
        if events:
            print(f"✅ Extracted {len(events)} events to: {output_file}", file=sys.stderr)
        else:
            print("⚠️  No valid events found in output", file=sys.stderr)
    
    return events

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Extract events from k6 output')
    parser.add_argument('output_file', nargs='?', default='/tmp/k6-sent-events.json',
                       help='Output JSON file path')
    parser.add_argument('--input-file', help='Input file (if not reading from stdin)')
    
    args = parser.parse_args()
    extract_events(input_file=args.input_file, output_file=args.output_file)

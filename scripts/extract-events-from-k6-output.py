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
                # Try to find the end of JSON - look for common patterns
                # k6 might append " source=..." or just end the line
                event_json = None
                
                # Try to find end markers
                for end_marker in ['" source', ' source=', '\n', '\r']:
                    end_idx = line.find(end_marker, json_start)
                    if end_idx != -1:
                        event_json = line[json_start:end_idx].strip().rstrip('"').rstrip("'")
                        break
                
                # If no end marker found, take the rest of the line
                if event_json is None:
                    event_json = line[json_start:].strip().rstrip('"').rstrip("'")
                
                # Try parsing the JSON
                if event_json:
                    try:
                        # Try parsing directly first
                        event = json.loads(event_json)
                        # Only include successful events (status 200) for validation
                        # Other statuses (409, 500, etc.) are logged but not validated
                        if event.get('success', event.get('status') == 200):
                            events.append(event)
                    except json.JSONDecodeError:
                        # If that fails, try unescaping (for escaped quotes)
                        try:
                            decoded = codecs.decode(event_json, 'unicode_escape')
                            event = json.loads(decoded)
                            # Only include successful events (status 200) for validation
                            if event.get('success', event.get('status') == 200):
                                events.append(event)
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            # Try removing any trailing non-JSON text
                            try:
                                # Find the last } and take everything up to it
                                last_brace = event_json.rfind('}')
                                if last_brace != -1:
                                    event_json_clean = event_json[:last_brace + 1]
                                    event = json.loads(event_json_clean)
                                    # Only include successful events (status 200) for validation
                                    if event.get('success', event.get('status') == 200):
                                        events.append(event)
                            except (json.JSONDecodeError, ValueError):
                                # Skip invalid JSON - log for debugging
                                if input_file:  # Only log when reading from file to avoid spam
                                    print(f"⚠️  Skipped invalid JSON: {event_json[:100]}...", file=sys.stderr)
                                pass
    
    # Write events to file
    if output_file:
        with open(output_file, 'w') as f:
            json.dump(events, f, indent=2)
        
        if events:
            # Count successful vs total if status info is available
            successful = sum(1 for e in events if e.get('success', e.get('status') == 200))
            total_in_file = len(events)
            if successful < total_in_file:
                print(f"✅ Extracted {successful} successful events (filtered from {total_in_file} total) to: {output_file}", file=sys.stderr)
            else:
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

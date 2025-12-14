#!/bin/bash
# Extract events from k6 output and save to JSON file
# Usage: k6 run ... send-batch-events.js 2>&1 | ./scripts/extract-events-from-k6-output.sh [output_file]

OUTPUT_FILE=${1:-/tmp/k6-sent-events.json}

# Use Python to read from stdin, extract events, and pass through output
python3 - <<PYEOF
import sys
import json

output_file = "$OUTPUT_FILE"
events = []
input_lines = []

# Read all input line by line
for line in sys.stdin:
    input_lines.append(line)
    # Find K6_EVENT lines
    # k6 logs: time="..." level=info msg="K6_EVENT: {...}" source=console
    if 'K6_EVENT:' in line:
        # Find the position of K6_EVENT:
        start_idx = line.find('K6_EVENT: ')
        if start_idx != -1:
            # Extract from after "K6_EVENT: " to before " source"
            json_start = start_idx + len('K6_EVENT: ')
            source_idx = line.find('" source', json_start)
            if source_idx != -1:
                event_json = line[json_start:source_idx].strip()
                # Remove any trailing quotes
                event_json = event_json.rstrip('"')
                try:
                    # Try parsing directly first (if quotes are already unescaped)
                    event = json.loads(event_json)
                    events.append(event)
                except json.JSONDecodeError:
                    # If that fails, try unescaping (for escaped quotes like \")
                    try:
                        import codecs
                        event_json_decoded = codecs.decode(event_json, 'unicode_escape')
                        event = json.loads(event_json_decoded)
                        events.append(event)
                    except (json.JSONDecodeError, UnicodeDecodeError, ImportError):
                        # Skip invalid JSON
                        pass

# Output original input (pass through)
for line in input_lines:
    sys.stdout.write(line)
    sys.stdout.flush()

# Write events to file
with open(output_file, 'w') as f:
    json.dump(events, f, indent=2)

if events:
    print(f"✅ Extracted {len(events)} events to: {output_file}", file=sys.stderr)
else:
    print("⚠️  No valid events found in output", file=sys.stderr)
PYEOF

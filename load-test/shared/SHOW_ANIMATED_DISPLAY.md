# How to See the Animated Progress Display

The animated progress display shows real-time test statistics with beautiful formatting. Here's how to see it:

## Quick Start

### 1. Install the rich library (Optional but Recommended)

```bash
# Try with your Python installation
python3 -m pip install --user rich

# Or if that doesn't work, try with homebrew Python
/opt/homebrew/bin/python3 -m pip install --user rich

# Verify installation
python3 -c "import rich; print('✓ rich is installed')"
```

**Note**: The script works without `rich` but will use a simpler text-based display.

### 2. Run Tests in an Interactive Terminal

The animated display **automatically appears** when you run tests in an interactive terminal:

```bash
cd load-test/shared

# Quick smoke test (30 seconds) - best for seeing the display
./run-sequential-throughput-tests.sh smoke '' 4k

# Full test (shows phase-by-phase progress)
./run-sequential-throughput-tests.sh full

# Saturation test (shows all 7 phases with progress)
./run-sequential-throughput-tests.sh saturation
```

## What You'll See

### With rich library installed:
- **Animated dashboard** that updates every second
- **Progress bars** showing test and phase completion
- **Real-time statistics**: throughput, response times, error rates
- **Color-coded metrics** (green for good, yellow/red for warnings)
- **Phase information** showing current test phase and VU count

### Without rich (fallback mode):
- **Text-based progress bars** using characters (█ and ░)
- **Formatted statistics tables** with borders
- **Color-coded output** using ANSI codes
- **Screen-clearing updates** every second

## Important Notes

1. **Interactive Terminal Required**: The display only works in interactive terminals (not in scripts or CI/CD pipelines)

2. **Background Process**: The display runs in the background and monitors the k6 JSON output file in real-time

3. **Non-Intrusive**: The display uses alternate screen buffer (with rich) or screen clearing (basic mode) to avoid interfering with the main test output

4. **Automatic**: No special flags needed - it starts automatically when conditions are met

## Troubleshooting

### Display not showing?

1. **Check terminal type**: Run `echo $TERM` - should show something like `xterm-256color` or `screen-256color`

2. **Check if interactive**: The script checks `[ -t 1 ]` - if this fails, the display won't start

3. **Check rich installation**: 
   ```bash
   python3 -c "import rich; print('OK')"
   ```

4. **Check file permissions**: Ensure the JSON file path is accessible

### Display interfering with output?

The display is designed to be non-intrusive. If you experience issues:
- Disable it: `ENABLE_PROGRESS_DISPLAY=false ./run-sequential-throughput-tests.sh smoke`
- The main test output will still show all information in the logs

## Testing the Display Independently

You can test the display script directly on a completed test:

```bash
# Find a JSON file from a previous test
JSON_FILE=$(find load-test/results/throughput-sequential -name "*.json" | head -1)

# Run the display script
python3 load-test/shared/test-progress-display.py \
    "$JSON_FILE" \
    --api-name "test-api" \
    --test-mode "smoke" \
    --payload-size "4k" \
    --update-interval 1.0
```

## Example Output

When running, you'll see something like this updating in real-time:

```
┌─────────────────────────────────────────────────────────────┐
│ producer-api-go-rest | Mode: smoke | Payload: 4k           │
│ Elapsed: 00:15                                              │
├─────────────────────────────────────────────────────────────┤
│ Progress                                                    │
│ Overall Progress: [████████████████░░░░░░░░] 50%           │
│ Phase 1/1: Smoke Test (10 VUs): [████████████████░░] 80%   │
├─────────────────────────────────────────────────────────────┤
│ Statistics                                                  │
│ Throughput:     125.50 req/s                                │
│ Total Requests: 1,875                                       │
│ Successful:     1,875                                       │
│ Failed:         0                                           │
│ Current VUs:    10                                          │
│ Avg Response:   7.95 ms                                     │
│ Min Response:   1.38 ms                                     │
│ Max Response:   45.23 ms                                    │
│ P95 Response:   12.34 ms                                    │
│ P99 Response:   18.67 ms                                    │
│ Error Rate:     0.00%                                       │
└─────────────────────────────────────────────────────────────┘
```

The display updates every second with the latest metrics from the running test!


# Animated Test Progress Display

The test runner includes an optional animated progress display that shows real-time test statistics and progress bars.

## Features

- **Real-time metrics**: Throughput, response times, error rates, and more
- **Progress bars**: Visual progress for overall test and current phase
- **Phase detection**: Automatically detects and displays current test phase
- **Beautiful formatting**: Uses the `rich` library for enhanced terminal output (optional)

## Installation

### Option 1: Install rich library (Recommended for best experience)

```bash
# Using pip with user install
pip3 install --user rich

# Or using pipx (if available)
pipx install rich

# Or using homebrew (macOS)
brew install python-rich
```

### Option 2: Use without rich (Basic mode)

The script automatically falls back to basic ANSI terminal codes if `rich` is not available. This still provides:
- Progress bars
- Formatted statistics
- Real-time updates
- Color-coded output

## Usage

The animated progress display **automatically starts** when you run tests in an interactive terminal:

```bash
cd load-test/shared

# Run smoke tests (quick, shows the display)
./run-sequential-throughput-tests.sh smoke '' 4k

# Run full tests (longer, shows phase-by-phase progress)
./run-sequential-throughput-tests.sh full

# Run saturation tests (shows all 7 phases)
./run-sequential-throughput-tests.sh saturation
```

## How It Works

1. **Automatic Detection**: The script detects if you're in an interactive terminal (`[ -t 1 ]`)
2. **Background Process**: Starts a background process that monitors the k6 JSON output file
3. **Real-time Updates**: Updates every 1 second with latest metrics
4. **Non-intrusive**: Uses alternate screen buffer (with rich) or clears screen (basic mode) to avoid interfering with main output

## Disabling the Display

If you want to disable the animated display:

```bash
ENABLE_PROGRESS_DISPLAY=false ./run-sequential-throughput-tests.sh smoke
```

## What You'll See

### With rich library:
- Beautiful panels and tables
- Smooth animated updates
- Color-coded statistics
- Professional-looking dashboard

### Without rich (fallback):
- Text-based progress bars
- Formatted statistics tables
- Color-coded output
- Screen-clearing updates

## Troubleshooting

### Display not showing?

1. **Check if running in interactive terminal**: The display only works in interactive terminals (not in scripts or CI/CD)
2. **Check rich installation**: Run `python3 -c "import rich; print('OK')"` to verify
3. **Check terminal support**: Ensure your terminal supports ANSI escape codes
4. **Check file permissions**: Ensure the JSON file can be read

### Display interfering with output?

The display is designed to be non-intrusive. If you experience issues:
- Disable it with `ENABLE_PROGRESS_DISPLAY=false`
- The main test output will still show all information

## Testing the Display

You can test the display independently:

```bash
# Create a test JSON file (from a previous test run)
JSON_FILE="load-test/results/throughput-sequential/producer-api-go-rest/4k/producer-api-go-rest-throughput-smoke-4k-*.json"

# Run the display script directly
python3 load-test/shared/test-progress-display.py \
    "$JSON_FILE" \
    --api-name "producer-api-go-rest" \
    --test-mode "smoke" \
    --payload-size "4k" \
    --update-interval 1.0
```

## Example Output

```
┌─────────────────────────────────────────────────────────┐
│ producer-api-go-rest | Mode: smoke | Payload: 4k       │
│ Elapsed: 00:15                                        │
├─────────────────────────────────────────────────────────┤
│ Progress                                               │
│ Overall Progress: [████████████░░░░░░░░] 50%          │
│ Phase 1/1: Smoke Test (10 VUs): [████████████░░░░] 80%│
├─────────────────────────────────────────────────────────┤
│ Statistics                                             │
│ Throughput:     125.50 req/s                           │
│ Total Requests: 1,875                                  │
│ Successful:     1,875                                  │
│ Failed:         0                                      │
│ Avg Response:   7.95 ms                                │
│ P95 Response:   12.34 ms                               │
│ P99 Response:   18.67 ms                               │
│ Error Rate:     0.00%                                  │
└─────────────────────────────────────────────────────────┘
```

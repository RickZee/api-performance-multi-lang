#!/bin/bash
# Quick script to check test execution progress

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULTS_DIR="$PROJECT_ROOT/results"

# Find latest results directory
LATEST_DIR=""
if [ -L "$RESULTS_DIR/latest" ]; then
    LATEST_DIR=$(readlink -f "$RESULTS_DIR/latest")
elif [ -d "$RESULTS_DIR" ]; then
    LATEST_DIR=$(ls -td "$RESULTS_DIR"/*/ 2>/dev/null | head -1 | sed 's|/$||')
fi

if [ -z "$LATEST_DIR" ] || [ ! -d "$LATEST_DIR" ]; then
    echo "No test results directory found yet."
    echo "Tests may still be initializing..."
    exit 0
fi

echo "=================================================================================="
echo "Test Execution Progress"
echo "=================================================================================="
echo "Results directory: $LATEST_DIR"
echo ""

# Count completed tests
COMPLETED=$(find "$LATEST_DIR" -name "test-*.json" -type f 2>/dev/null | wc -l | tr -d ' ')

# Get total from completed.json if available
TOTAL="?"
if [ -f "$LATEST_DIR/completed.json" ]; then
    TOTAL=$(python3 -c "import json; f=open('$LATEST_DIR/completed.json'); d=json.load(f); print(len(d.get('completed', [])) + 10)" 2>/dev/null || echo "?")
fi

# Try to get total from manifest
if [ -f "$LATEST_DIR/manifest.json" ]; then
    TOTAL=$(python3 -c "import json; f=open('$LATEST_DIR/manifest.json'); d=json.load(f); print(d.get('total_expected', '?'))" 2>/dev/null || echo "?")
fi

# If we can't get total, estimate from test-config
if [ "$TOTAL" = "?" ]; then
    TOTAL=32  # Default total
fi

# Calculate progress
if [ "$TOTAL" != "?" ] && [ "$TOTAL" -gt 0 ]; then
    PROGRESS_PCT=$(python3 -c "print(int(($COMPLETED / $TOTAL) * 100))" 2>/dev/null || echo "0")
else
    PROGRESS_PCT=0
fi

echo "Progress: $COMPLETED/$TOTAL tests completed ($PROGRESS_PCT%)"
echo ""

# Show recent test results
echo "Recent test results:"
find "$LATEST_DIR" -name "test-*.json" -type f -exec basename {} \; 2>/dev/null | sort | tail -5

echo ""
echo "To monitor in real-time:"
echo "  python3 scripts/monitor_tests.py"
echo ""
echo "To view full progress:"
echo "  python3 scripts/monitor_tests.py --results-dir $LATEST_DIR"


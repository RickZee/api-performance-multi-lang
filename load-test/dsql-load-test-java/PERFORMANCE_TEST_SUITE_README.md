# DSQL Performance Test Suite

## Overview

Comprehensive performance testing framework for DSQL that systematically tests performance across multiple dimensions (thread counts, batch sizes, loop sizes, payload sizes), collects structured data, and generates visualizations.

## Quick Start

1. **Run the test suite:**
   ```bash
   cd load-test/dsql-load-test-java
   ./run-performance-suite.sh
   ```

2. **Analyze results:**
   ```bash
   python3 analyze-results.py results/latest
   ```

3. **Generate HTML report:**
   ```bash
   python3 generate-report.py results/latest
   ```

## Test Matrix

The suite runs **31 focused tests** (27 standard + 4 super heavy) using a one-factor-at-a-time approach:

### Scenario 1: Individual Inserts

- **Thread Scaling** (5 tests): Threads: [1, 10, 25, 50, 100]
  - Fixed: iterations=100, count=1, payload=default
- **Loop Impact** (4 tests): Iterations: [10, 100, 1000, 5000]
  - Fixed: threads=10, count=1, payload=default
- **Payload Impact** (4 tests): Payload: [default, 4k, 32k, 200k]
  - Fixed: threads=10, iterations=100, count=1
- **Super Heavy Tests** (2 tests):
  - Threads=200, iterations=10000, count=1, payload=default
  - Threads=100, iterations=50000, count=1, payload=default

### Scenario 2: Batch Inserts

- **Thread Scaling** (5 tests): Threads: [1, 10, 25, 50, 100]
  - Fixed: iterations=100, batch_size=10, payload=default
- **Batch Impact** (5 tests): Batch Size: [1, 10, 25, 50, 100]
  - Fixed: threads=10, iterations=100, payload=default
- **Payload Impact** (4 tests): Payload: [default, 4k, 32k, 200k]
  - Fixed: threads=10, iterations=100, batch_size=10
- **Super Heavy Tests** (2 tests):
  - Threads=200, iterations=1000, batch_size=200, payload=default
  - Threads=100, iterations=5000, batch_size=500, payload=default

## Configuration

Edit `test-config.json` to modify test parameters. The configuration uses a baseline approach where one dimension is varied at a time.

## Results

Results are stored in `results/{timestamp}/` with:
- Individual test JSON files
- Summary CSV
- Performance charts (PNG)
- HTML report

## Dependencies

- Java 17+
- Maven 3.8+
- Python 3.8+ with: pandas, matplotlib, seaborn, jinja2
- jq (for JSON processing)

Install Python dependencies:
```bash
pip install -r requirements.txt
```

## Files

- `test-config.json` - Test matrix configuration
- `run-performance-suite.sh` - Test execution script
- `analyze-results.py` - Chart generation script
- `generate-report.py` - HTML report generator
- `PerformanceMetrics.java` - Metrics data model
- `TestResultsCollector.java` - Results collection and export

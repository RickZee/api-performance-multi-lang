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

The suite runs **27 focused tests** using a one-factor-at-a-time approach:

- **Scenario 1 - Thread Scaling**: 5 tests (1, 10, 25, 50, 100 threads)
- **Scenario 1 - Loop Impact**: 4 tests (10, 100, 1000, 5000 iterations)
- **Scenario 1 - Payload Impact**: 4 tests (default, 4k, 32k, 200k)
- **Scenario 2 - Thread Scaling**: 5 tests (1, 10, 25, 50, 100 threads)
- **Scenario 2 - Batch Impact**: 5 tests (1, 10, 25, 50, 100 batch size)
- **Scenario 2 - Payload Impact**: 4 tests (default, 4k, 32k, 200k)

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

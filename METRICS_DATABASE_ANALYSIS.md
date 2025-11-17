# Metrics Database Analysis

## Summary

After reviewing all code, here's what metrics are being written to the database and what's missing:

## ✅ Metrics Being Written to Database

### 1. Test Run Metadata (`test_runs` table)
- **Status**: ✅ WRITTEN
- **Location**: `run-sequential-throughput-tests.sh` lines 1613-1643
- **Function**: `db_client.py::create_test_run()`
- **Data Written**:
  - api_name
  - test_mode
  - payload_size
  - protocol
  - started_at
  - status
  - k6_json_file_path

### 2. Performance Metrics (`performance_metrics` table)
- **Status**: ✅ WRITTEN
- **Location**: `run-sequential-throughput-tests.sh` lines 1743-1766
- **Function**: `db_client.py::insert_performance_metrics()`
- **Data Written**:
  - total_samples
  - success_samples
  - error_samples
  - throughput_req_per_sec
  - avg_response_time_ms
  - min_response_time_ms
  - max_response_time_ms
  - p50_response_time_ms (if available)
  - p90_response_time_ms (if available)
  - p95_response_time_ms (if available)
  - p99_response_time_ms (if available)
  - error_rate_percent

### 3. Resource Metrics (`resource_metrics` table)
- **Status**: ✅ WRITTEN
- **Location**: `collect-metrics.sh` lines 238-269
- **Function**: `db_client.py::insert_resource_metric_cli()` → `insert_resource_metrics_batch()`
- **Data Written**:
  - timestamp
  - cpu_percent
  - memory_percent
  - memory_used_mb
  - memory_limit_mb
  - network_io_rx
  - network_io_tx
  - block_io_read
  - block_io_write
- **Note**: Written in real-time during test execution (every 5 seconds)

### 4. Test Run Completion (`test_runs` table)
- **Status**: ✅ WRITTEN
- **Location**: `run-sequential-throughput-tests.sh` lines 1759-1761
- **Function**: `db_client.py::update_test_run_completion()`
- **Data Written**:
  - completed_at
  - status
  - duration_seconds

## ✅ Metrics Being Written to Database (FIXED)

### 1. Test Phase Metrics (`test_phases` table)
- **Status**: ✅ NOW WRITTEN (Fixed)
- **Location**: `run-sequential-throughput-tests.sh` lines 1769-1879
- **Implementation**: 
  - Added CLI command `insert_test_phase` to `db_client.py`
  - Updated `run-sequential-throughput-tests.sh` to parse JSON output from `analyze-resource-metrics.py` and insert each phase
  - Uses Python script embedded in bash to parse JSON and call `db_client.py insert_test_phase` for each phase
- **Data Written**:
  - phase_number
  - phase_name (e.g., "Baseline", "Mid-load", "High-load", etc.)
  - target_vus
  - duration_seconds
  - requests_count
  - avg_cpu_percent
  - max_cpu_percent
  - avg_memory_mb
  - max_memory_mb
  - cpu_percent_per_request
  - ram_mb_per_request
- **Note**: Written for all test modes (`smoke`, `full`, and `saturation`). Smoke tests have a single phase.

## Database Schema

All tables are properly defined in:
- `load-test/shared/migrations/001_create_metrics_schema.sql`

The schema includes:
1. ✅ `test_runs` - Test run metadata
2. ✅ `performance_metrics` - Aggregated performance metrics
3. ✅ `resource_metrics` - Time-series resource utilization
4. ✅ `test_phases` - Phase-specific metrics (now populated for full/saturation tests)

## Implementation Summary

All metrics are now being written to the database:

1. ✅ **Test Run Metadata** - Written when test starts
2. ✅ **Performance Metrics** - Written after test completes
3. ✅ **Resource Metrics** - Written in real-time during test execution
4. ✅ **Test Phase Metrics** - Written after test completes (for all test modes: smoke, full, and saturation)

### Changes Made

1. **Added CLI command** `insert_test_phase` to `db_client.py` (lines 546-564)
2. **Updated `run-sequential-throughput-tests.sh`** to:
   - Parse JSON output from `analyze-resource-metrics.py`
   - Extract phase data for each phase
   - Call `db_client.py insert_test_phase` for each phase
   - Handle phase names based on test mode (full vs saturation)
   - Provide proper error handling and cleanup

The fix ensures that all phase-specific metrics (CPU, memory, requests per phase, derived metrics) are now stored in the `test_phases` table for full and saturation test runs.


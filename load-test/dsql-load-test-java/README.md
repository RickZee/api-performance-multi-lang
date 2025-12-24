# DSQL Performance Test Suite

A comprehensive Python-based test orchestration system for evaluating DSQL (Aurora Data API) performance. Executes Java-based load tests on remote EC2 instances and collects performance metrics.

## Quick Start

```bash
# 1. Install dependencies
cd load-test/dsql-load-test-java
pip install -r requirements.txt

# 2. Verify setup
python3 scripts/run_minimal_test.py

# 3. Run full test suite
python3 scripts/run_test_suite.py

# 4. Monitor progress (separate terminal)
python3 scripts/monitor_tests.py

# 5. Analyze results
python3 scripts/analyze_results.py
```

## Prerequisites

- **Python 3.8+** with dependencies (`pip install -r requirements.txt`)
- **Java 17+** and **Maven 3.8+** (on EC2 instance)
- **AWS credentials** configured (boto3)
- **Environment variables** or Terraform outputs:
  - `DSQL_HOST` - DSQL endpoint
  - `TEST_RUNNER_INSTANCE_ID` - EC2 instance ID
  - `S3_BUCKET` - S3 bucket for artifacts
  - `AWS_REGION` - AWS region (default: us-east-1)

## Architecture

```
┌─────────────────────────────────────────┐
│         CLI Scripts (scripts/)          │
│  run_test_suite.py │ monitor_tests.py   │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│      Test Suite Package (test_suite/)   │
│  config.py │ executor.py │ runner.py   │
│  monitor.py │ resource_metrics.py       │
└────────────┬────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────┐
│         AWS Infrastructure              │
│  EC2 │ SSM │ S3 │ DSQL (Aurora)         │
└─────────────────────────────────────────┘
```

**Key Modules:**
- `config.py` - Environment-based configuration
- `executor.py` - AWS operations (SSM, S3, EC2)
- `runner.py` - Test orchestration and execution
- `monitor.py` - Progress monitoring
- `resource_metrics.py` - CloudWatch metrics collection

## Test Scenarios

**Scenario 1: Individual Inserts** - One row per INSERT statement
- Measures single-row insert performance
- Lower throughput, simpler transaction model

**Scenario 2: Batch Inserts** - Multiple rows per INSERT statement
- Configurable batch size (1-1000 rows)
- Higher throughput potential
- More efficient for bulk operations

## Test Matrix

The suite runs **32 focused tests** (24 standard + 8 extreme) using one-factor-at-a-time approach:

### Standard Tests (24 tests)

**Scenario 1:**
- Thread Scaling: [1, 10, 25, 50, 100] threads (5 tests)
- Loop Impact: [10, 20, 50, 100] iterations (4 tests)
- Payload Impact: [default, 4k, 32k] payloads (3 tests)

**Scenario 2:**
- Thread Scaling: [1, 10, 25, 50, 100] threads (5 tests)
- Batch Impact: [1, 10, 25, 50] batch sizes (4 tests)
- Payload Impact: [default, 4k, 32k] payloads (3 tests)

### Extreme Tests (8 tests)

- Super Heavy: 500-1000 threads, high iteration counts (4 tests)
- Extreme Scaling: 2000-5000 threads, large batch sizes (4 tests)

**Expected Duration:** 2-4 hours for full suite

## Usage

### Running Tests

```bash
# Full test suite
python3 scripts/run_test_suite.py

# Specific test groups
python3 scripts/run_test_suite.py --groups scenario1_thread_scaling

# Resume interrupted run
python3 scripts/run_test_suite.py --resume

# Custom options
python3 scripts/run_test_suite.py --max-pool-size 2000 --connection-rate-limit 100
```

### Monitoring

```bash
# Real-time monitoring (auto-refresh every 10s)
python3 scripts/monitor_tests.py

# Custom interval
python3 scripts/monitor_tests.py --interval 5

# Specific results directory
python3 scripts/monitor_tests.py --results-dir results/2025-12-22_14-37-03
```

### Analysis

```bash
# Analyze latest results
python3 scripts/analyze_results.py

# Wait for completion then analyze
python3 scripts/analyze_results.py --wait

# Specific directory
python3 scripts/analyze_results.py results/2025-12-22_14-37-03
```

## Configuration

### Test Configuration (`test-config.json`)

Edit `test-config.json` to modify test parameters:

```json
{
  "baseline": {
    "threads": 10,
    "iterations": 20,
    "batch_size": 10,
    "payload_size": null
  },
  "test_groups": {
    "scenario1_thread_scaling": {
      "scenario": 1,
      "threads": [1, 10, 25, 50, 100],
      "iterations": 20,
      "count": 1
    }
  }
}
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DSQL_HOST` | DSQL endpoint hostname | Required |
| `TEST_RUNNER_INSTANCE_ID` | EC2 instance ID | Required |
| `S3_BUCKET` | S3 bucket name | Required |
| `AWS_REGION` | AWS region | us-east-1 |
| `IAM_DATABASE_USERNAME` | IAM database user | lambda_dsql_user |
| `MAX_POOL_SIZE` | Connection pool size | 2000 (auto-calculated) |
| `DSQL_CONNECTION_RATE_LIMIT` | Connection startup rate | 100 threads/sec |

### Infrastructure Discovery

The test suite automatically discovers infrastructure:

1. **Environment variables** (highest priority)
2. **AWS API queries** (boto3) - finds instances by tags, buckets by name
3. **Terraform outputs** (fallback) - reads from `../../terraform/`

## Results

Results are stored in `results/{timestamp}/`:

```
results/
├── 2025-12-22_14-37-03/
│   ├── manifest.json           # Test run metadata
│   ├── completed.json          # Completed test tracking
│   ├── test-001-*.json         # Individual test results
│   ├── summary.csv             # Summary statistics
│   ├── charts/                 # Performance charts (PNG)
│   └── report.html             # HTML report
└── latest -> 2025-12-22_14-37-03
```

**Result JSON Structure:**
- `configuration` - Test parameters
- `system_metrics` - Hardware, CPU, memory, disk metrics
- `cloudwatch_metrics` - EC2 instance metrics
- `results` - Performance metrics (throughput, latency, errors)
- `pool_metrics` - Connection pool statistics

## EC2 Instance Requirements

**Recommended:** `m5a.2xlarge` (8 vCPU, 32 GB RAM)
- Cost: $0.344/hour (~$1.03 per 3-hour test run)
- Supports 1000-2000 thread tests

**Requirements by Scale:**
- 500-1000 threads: `m5a.xlarge` (4 vCPU, 16 GB RAM) - $0.17/hour
- 1000-2000 threads: `m5a.2xlarge` (8 vCPU, 32 GB RAM) - $0.34/hour
- 2000-5000 threads: `m5a.4xlarge` (16 vCPU, 64 GB RAM) - $0.69/hour

**Cost Optimization:**
- Instance auto-starts before tests
- Instance auto-stops after completion
- Typical cost: ~$1-5/month (only during test runs)

## Performance Tuning

### Connection Pool Sizing

**Default:** `min(max(threads/2, 10), 1000)`
- 100 threads → 50 connections
- 1000 threads → 500 connections
- 5000 threads → 1000 connections (max)

**Manual Override:** Set `MAX_POOL_SIZE` environment variable

### Batch Size Limits

- **Maximum:** 10,000 rows per batch (PostgreSQL limit: 65,535 parameters)
- **Recommended:** 500-1000 rows for extreme scaling
- Automatically validated before execution

## Monitoring & Metrics

### System Metrics (Java Application)

Collected at test initialization:
- Hardware configuration (CPU, memory, architecture, OS, Java version)
- CPU metrics (process load, system load, CPU time)
- Memory metrics (heap, non-heap, system memory)
- Disk metrics (total, free, usable, used)
- Network metrics (active interfaces)

### CloudWatch Metrics (Python Orchestration)

Collected during test execution:
- EC2 instance metadata (type, AZ, VPC, subnet)
- CPU utilization (average, max, min)
- Network I/O (bytes, packets in/out)
- Disk I/O (read/write ops, bytes)

### Performance Metrics

Each test result includes:
- **Throughput:** Inserts per second
- **Latency:** p50, p95, p99 percentiles
- **Error Categorization:** Connection, query, authentication errors
- **Connection Pool:** Active, idle, waiting, total connections

## Troubleshooting

### EC2 Instance Not Found

```bash
# Check instance exists
aws ec2 describe-instances --filters "Name=tag:Name,Values=*test-runner*"

# Set explicitly
export TEST_RUNNER_INSTANCE_ID=i-xxxxxxxxxxxxx
```

### DSQL Host Not Found

```bash
# Set explicitly
export DSQL_HOST=your-endpoint.dsql-fnh4.us-east-1.on.aws

# Or use Terraform
cd ../../terraform && terraform output aurora_dsql_host
```

### Test Execution Fails

1. Check SSM agent is online: `aws ssm describe-instance-information`
2. Verify instance has DSQL permissions (IAM role)
3. Check S3 bucket permissions
4. Review test output in SSM command history

### High Connection Pool Wait Times

- Increase `MAX_POOL_SIZE` environment variable
- Reduce thread count
- Check DSQL connection limits

## Project Structure

```
dsql-load-test-java/
├── scripts/              # CLI entry points
│   ├── run_test_suite.py      # Main orchestrator
│   ├── monitor_tests.py       # Progress monitoring
│   ├── analyze_results.py    # Analysis wrapper
│   └── run_minimal_test.py   # Verification test
├── test_suite/           # Core package
│   ├── config.py         # Configuration
│   ├── executor.py       # AWS operations
│   ├── runner.py         # Test orchestration
│   ├── monitor.py        # Progress monitoring
│   └── resource_metrics.py  # Metrics collection
├── src/main/java/        # Java load test application
├── test-config.json      # Test matrix configuration
├── results/              # Test results
└── archive/              # Archived outdated files
```

## Additional Resources

- **Infrastructure & Costs:** `../INFRASTRUCTURE_AND_COSTS.md`
- **Java Application Details:** See `src/main/java/` for implementation
- **Test Configuration:** See `test-config.json` for test matrix

## Migration Notes

The test suite was migrated from bash scripts to Python:
- Old bash scripts moved to `archive/legacy/`
- Old nested package structure in `archive/archive_old/`
- Current structure uses flat `test_suite/` package


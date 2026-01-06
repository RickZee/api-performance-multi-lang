# DSQL Performance Test Suite

A comprehensive Python-based test orchestration system for evaluating DSQL (Aurora Data API) performance. Executes Java-based load tests on remote EC2 instances and collects performance metrics.

## Quick Start

### Local Docker Testing (Recommended for Development)

```bash
# 1. Start local PostgreSQL (if not already running)
cd load-test/dsql-load-test-java
docker-compose -f docker-compose.local.yml up -d

# 2. Run a small test
./scripts/run_local_test.sh

# 3. Check results in results/local-test-*/
```

### Remote Testing (DSQL/Aurora)

```bash
# 1. Install dependencies
cd load-test/dsql-load-test-java
pip install -r requirements.txt

# 2. Load environment from Terraform
source scripts/load_env_from_terraform.sh

# 3. Verify setup
python3 scripts/run_minimal_test.py

# 4. Run full test suite
python3 scripts/run_test_suite.py

# 5. Monitor progress (separate terminal)
python3 scripts/monitor_tests.py

# 6. Analyze results
python3 scripts/analyze_results.py
```

## Prerequisites

- **Python 3.8+** with dependencies (`pip install -r requirements.txt`)
- **Java 17+** and **Maven 3.8+** (on EC2 instance)
- **AWS credentials** configured (boto3)
- **Environment variables** or Terraform outputs (see Configuration section below)

## Configuration

The test suite supports **DSQL** (Aurora DSQL), **Aurora PostgreSQL**, and **Local Docker PostgreSQL**. Set `DATABASE_TYPE` environment variable to choose:
- `DATABASE_TYPE=dsql` (default) - Use Aurora DSQL with IAM authentication
- `DATABASE_TYPE=aurora` - Use Aurora PostgreSQL with username/password authentication
- `DATABASE_TYPE=local` - Use local Docker PostgreSQL (for development and quick testing)

### DSQL Configuration

**Required Environment Variables:**
- `DSQL_HOST` - DSQL endpoint (from terraform: `aurora_dsql_host`)
- `IAM_USERNAME` - IAM database user (default: `lambda_dsql_user`)
- `DATABASE_NAME` - Database name (default: `postgres`)
- `AWS_REGION` - AWS region (default: `us-east-1`)

**Optional:**
- `DSQL_PORT` - Port (default: `5432`)
- `MAX_POOL_SIZE` - Connection pool size (default: calculated from thread count)
- `DSQL_CONNECTION_RATE_LIMIT` - Connection rate limit (default: `100` threads/second)

**Load from Terraform:**
```bash
source scripts/load_env_from_terraform.sh
# Or explicitly set database type:
DATABASE_TYPE=dsql source scripts/load_env_from_terraform.sh
```

### Aurora PostgreSQL Configuration

**Required Environment Variables:**
- `AURORA_HOST` or `AURORA_ENDPOINT` - Aurora cluster endpoint (from terraform: `aurora_endpoint`)
- `AURORA_USERNAME` - Database username (from terraform: `database_user`)
- `AURORA_PASSWORD` - Database password (from terraform: `database_password`)
- `DATABASE_NAME` - Database name (default: `car_entities`)

**Optional:**
- `AURORA_PORT` - Port (default: `5432`)
- `MAX_POOL_SIZE` - Connection pool size (default: calculated from thread count, more conservative than DSQL)
- `DSQL_CONNECTION_RATE_LIMIT` - Connection rate limit (default: `50` threads/second for Aurora)

**Load from Terraform:**
```bash
DATABASE_TYPE=aurora source scripts/load_env_from_terraform.sh
```

**Note:** Aurora password is sensitive and stored in terraform variables, not outputs. The script will warn if password is not set. You may need to set it manually:
```bash
export AURORA_PASSWORD="your-password"
# Or from terraform variables file
export AURORA_PASSWORD=$(cd ../../terraform && terraform output -raw database_password 2>/dev/null || echo "")
```

### Local Docker Configuration

**Quick Start:**
```bash
# Run a small test against local Docker PostgreSQL
./scripts/run_local_test.sh
```

**Required Environment Variables:**
- `LOCAL_HOST` - PostgreSQL host (default: `localhost`)
- `LOCAL_PORT` - PostgreSQL port (default: `5433`)
- `LOCAL_USERNAME` - Database username (default: `postgres`)
- `LOCAL_PASSWORD` - Database password (default: `password`)
- `DATABASE_NAME` - Database name (default: `car_entities`)

**Optional:**
- `MAX_POOL_SIZE` - Connection pool size (default: calculated from thread count)
- `DSQL_CONNECTION_RATE_LIMIT` - Connection rate limit (default: `50` threads/second)

**Setup Local Docker PostgreSQL:**

Option 1: Use existing docker-compose (if available):
```bash
cd ../..  # Go to project root
docker-compose up -d postgres-large
```

Option 2: Use dedicated load test docker-compose:
```bash
docker-compose -f docker-compose.local.yml up -d
```

**Manual Test Execution:**
```bash
export DATABASE_TYPE=local
export LOCAL_HOST=localhost
export LOCAL_PORT=5433
export LOCAL_USERNAME=postgres
export LOCAL_PASSWORD=password
export DATABASE_NAME=car_entities
export SCENARIO=1
export THREADS=5
export ITERATIONS=2
export COUNT=10

# Build JAR if needed
mvn clean package -DskipTests

# Run test
java -jar target/dsql-load-test-1.0.0.jar
```

**Note:** Local testing runs directly on your machine (no EC2/SSM required). `TEST_RUNNER_INSTANCE_ID` and `S3_BUCKET` are not required for local execution.

### Common Configuration

**Required for remote execution (DSQL/Aurora):**
- `TEST_RUNNER_INSTANCE_ID` - EC2 instance ID for test execution
- `S3_BUCKET` - S3 bucket for test artifacts and results
- `AWS_REGION` - AWS region (default: `us-east-1`)

**Note:** These are not required for `DATABASE_TYPE=local` (runs directly on your machine).

### Connection Limits

- **DSQL**: Supports up to 5000 connections per cluster endpoint. Pool size can be up to 2000 connections.
- **Aurora PostgreSQL**: Connection limits vary by instance class (e.g., `db.t3.small` ~40 connections). Pool size is more conservative, typically capped at 1000 connections.

### Differences

| Feature | DSQL | Aurora PostgreSQL | Local Docker |
|---------|------|------------------|--------------|
| Authentication | IAM (automatic token generation) | Username/Password | Username/Password |
| Connection Limits | Up to 5000 per endpoint | Varies by instance class | ~200 (Docker default) |
| Default Pool Size | More aggressive (threads/2 to threads/3) | More conservative (threads/3 to threads/5) | Conservative (threads/3 to threads/5) |
| Default Rate Limit | 100 threads/second | 50 threads/second | 50 threads/second |
| SSL/TLS | Required | Required | Optional (not required for localhost) |
| Execution | Remote (EC2/SSM) | Remote (EC2/SSM) | Local (direct) |

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
│  config.py │ executor.py │ runner.py    │
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
- `monitor.py` - Progress monitoring (local file-based)
- `s3_monitor.py` - S3-based progress monitoring (recommended)
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

# Specify total tests manually
python3 scripts/monitor_tests.py --total-tests 32

# Use specific config file
python3 scripts/monitor_tests.py --config test-config.json
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

The test suite loads configuration from:

1. **Environment variables** (required) - must be set explicitly
2. **Terraform outputs** (fallback in some scripts) - reads from `../../terraform/` when env vars are missing

**Note:** The main configuration (`test_suite/config.py`) requires environment variables. Some monitoring scripts may attempt Terraform fallback, but the test runner itself requires explicit environment variables.

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

**Default:** Auto-calculated based on thread count:
- Threads < 500: `min(max(threads, 10), 200)`
- Threads 500-1999: `min(threads / 2, 2000)`
- Threads ≥ 2000: `min(threads / 3, 2000)`

**Examples:**
- 100 threads → 100 connections
- 1000 threads → 500 connections
- 5000 threads → 1666 connections (capped at 2000 max)

**Manual Override:** Set `MAX_POOL_SIZE` environment variable (max: 2000)

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
```

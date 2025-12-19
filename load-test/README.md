# Load Test Documentation

## HTML Report Structure and Testing

### Report Structure

The HTML performance test report (`comparison-report-{timestamp}.html`) contains the following sections:

1. **Header Section**: Test metadata (mode, date, type, duration, payload sizes)
2. **Data Validation Warnings**: Alerts for data quality issues (if any)
3. **Executive Summary Table**: Overview of all APIs with key metrics
4. **Comparison Analysis**: 
   - Statistical Analysis (mean, std dev, confidence intervals, coefficient of variation)
   - Performance Rankings (highest throughput, lowest latency, most reliable)
   - Protocol Comparison (REST vs gRPC)
   - Language Comparison (Java vs Rust vs Go)
   - Key Insights
   - Recommendations
5. **Performance Comparison Charts**: Interactive Chart.js visualizations
6. **AWS EKS Cost Analytics**: Cost breakdown and efficiency metrics (if resource data available)
7. **Resource Utilization Metrics**: CPU and memory usage (if resource data available)
8. **Detailed Results**: Expanded metrics table per API
9. **Footer**: Generation timestamp and framework info

### Data Sources

- **Primary**: PostgreSQL database via `db_client.py` (`test_runs` and `resource_metrics` tables)
- **Fallback**: JSON files from k6 test results
- **Cost Calculations**: `calculate_aws_costs.py` module
- **Resource Metrics**: Database `resource_metrics` table (optional)

### Testing the Report

A comprehensive test suite is available to validate report completeness:

```bash
# Run tests with default report location
pytest load-test/shared/test_html_report.py -v

# Run tests with specific report file
pytest load-test/shared/test_html_report.py --report-path=/path/to/report.html -v
```

The test suite validates:
- All sections are present
- Tables contain data
- Numeric values are valid
- Charts are properly configured
- Required elements exist

See `load-test/shared/test_html_report.py` for detailed test coverage.

### Report Improvements

The report includes several enhancements:

1. **Data Validation**: Automatic detection of data quality issues
2. **Statistical Analysis**: Mean, standard deviation, confidence intervals, coefficient of variation
3. **Export Capabilities**: CSV and JSON export buttons
4. **Enhanced Chart Tooltips**: Detailed information on hover
5. **Error Handling**: Graceful degradation when optional data is missing

## AWS EKS Cost Analytics - Column Definitions

This document explains the columns in the AWS EKS Cost Analytics section of the performance test reports.

| Column | Meaning | Calculation |
|--------|---------|-------------|
| **Pods** | Number of pod replicas configured for this API | Configured in `pod_config.json` (currently all APIs use 1 pod for fair comparison) |
| **Pod Size** | CPU cores and memory allocated per pod | From `pod_config.json`: CPU cores per pod and memory (GB) per pod |
| **Instance Type** | EC2 instance type automatically selected based on pod requirements | Smallest cost-effective instance type that can fit all pods (considers 20% overhead for system/kubelet). Selected from t3.small, t3.medium, t3.large, t3.xlarge, t3.2xlarge. |
| **Instances** | Number of EC2 instances needed to run all pods | Calculated as: `ceil(num_pods / pods_per_instance)` where pods_per_instance is limited by CPU and memory capacity of the instance type |
| **Total Cost ($)** | Total cost for running this API during the test duration | Sum of: Instance Cost + Cluster Cost + ALB Cost + Storage Cost + Network Cost |
| **Cost/1K Requests ($)** | Cost per 1,000 requests processed | Calculated as: `(Total Cost / total_requests) × 1000`. Useful for comparing cost efficiency across APIs. |
| **Instance Cost ($)** | EC2 instance compute cost (adjusted for resource utilization) | Formula: `instance_hourly_cost × instances_needed × duration_hours × max(cpu_efficiency, memory_efficiency)`. If efficiency is 0% (no metrics), uses base cost. Efficiency = actual_utilization / allocated_resources. |
| **Cluster Cost ($)** | EKS cluster management cost | Calculated as: `$0.10/hour × duration_hours`. Fixed cost for EKS cluster management regardless of workload size. |
| **ALB Cost ($)** | Application Load Balancer cost | Calculated as: `($0.0225/hour × duration_hours) + ($0.008/GB × data_processed_gb)`. Includes base hourly cost and LCU (Load Balancer Capacity Unit) charges for data processed. |
| **Storage Cost ($)** | EBS storage cost for pod volumes | Calculated as: `$0.08/GB/month × (storage_gb_per_pod × num_pods) × (duration_hours / 720)`. Based on gp3 EBS storage pricing (converted to hourly rate). |
| **Network Cost ($)** | Data transfer out cost | Calculated as: `$0.09/GB × data_transfer_gb`. Estimated from request count (1KB per request). Only outbound data transfer is charged. |
| **CPU Efficiency** | Percentage of allocated CPU actually utilized | Calculated as: `(avg_cpu_percent / 100) × 100%`. Shows how efficiently CPU resources are used. 0% means no resource metrics were collected (common for short smoke tests). |
| **Memory Efficiency** | Percentage of allocated memory actually utilized | Calculated as: `(avg_memory_mb / memory_limit_mb) × 100%`. Shows how efficiently memory resources are used. 0% means no resource metrics were collected (common for short smoke tests). |

### Notes

**Note on Efficiency:** CPU and Memory efficiency are calculated based on actual resource utilization during the test. If efficiency shows 0%, it means resource metrics were not collected or the API had minimal resource usage during the test. This is common for very short smoke tests. For accurate efficiency metrics, run longer tests (full or saturation mode) with resource monitoring enabled.

**Note on Pricing:** All costs are estimated based on AWS us-east-1 on-demand pricing as of 2024. Actual costs may vary based on instance types, regions, reserved instances, spot instances, and other factors. These estimates assume a single EKS cluster shared across all APIs.

## Lambda API Testing

The load testing framework supports testing AWS Lambda functions both locally (using SAM Local) and in AWS.

### Lambda Test Scripts

- **`run-lambda-tests.sh`** - Main script for running Lambda performance tests
- **`start-local-lambdas.sh`** - Start Lambda functions locally using SAM Local
- **`stop-local-lambdas.sh`** - Stop locally running Lambda functions
- **`deploy-all-lambdas.sh`** - Deploy Lambda functions to AWS
- **`lambda-config.json`** - Configuration for Lambda APIs and test settings
- **`lambda-local-config.json`** - Configuration for local Lambda execution

### Lambda Test Scripts (k6)

- **`lambda-rest-api-test.js`** - k6 test script for Lambda REST APIs
- **`lambda-grpc-api-test.js`** - k6 test script for Lambda gRPC APIs

### Batch Event Scripts (k6)

- **`send-batch-events.js`** - Consolidated script to send configurable number of events of each type
  - Always sends all 4 event types: Car Created, Loan Created, Loan Payment Submitted, Car Service Done
  - Default: 5 events per type (20 total events)
  - Configurable via `EVENTS_PER_TYPE` environment variable
  - Supports both regular REST APIs (HOST/PORT) and Lambda APIs (API_URL or DB_TYPE)
  - Uses deterministic UUID generation for uniqueness across parallel VUs
  - Usage examples:
    ```bash
    # Send 5 events of each type (default)
    k6 run --env HOST=producer-api-java-rest --env PORT=8081 load-test/k6/send-batch-events.js
    
    # Send 1000 events of each type with parallelism
    k6 run --env HOST=producer-api-java-rest --env PORT=8081 --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=10 load-test/k6/send-batch-events.js
    
    # Lambda API with PostgreSQL (pg)
    k6 run --env DB_TYPE=pg --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=20 load-test/k6/send-batch-events.js
    
    # Lambda API with DSQL (dsql)
    k6 run --env DB_TYPE=dsql --env EVENTS_PER_TYPE=1000 --env VUS_PER_EVENT_TYPE=20 load-test/k6/send-batch-events.js
    
    # Lambda API with explicit URL
    k6 run --env API_URL=https://xxxxx.execute-api.us-east-1.amazonaws.com --env EVENTS_PER_TYPE=1000 load-test/k6/send-batch-events.js
    
    # Sequential mode (process events in order: Car → Loan → Payment → Service)
    k6 run --env HOST=producer-api-java-rest --env PORT=8081 --env SEQUENTIAL_MODE=true load-test/k6/send-batch-events.js
    
    # Save events to custom file for validation
    k6 run --env DB_TYPE=pg --env EVENTS_FILE=/tmp/my-events.json load-test/k6/send-batch-events.js
    ```
  
  **Environment Variables:**
  - `EVENTS_PER_TYPE` (default: 5) - Number of events to send per event type
  - `VUS_PER_EVENT_TYPE` (default: 1) - Number of virtual users per event type for parallelism
  - `TOTAL_VUS` - Total virtual users (overrides VUS_PER_EVENT_TYPE if set)
  - `SEQUENTIAL_MODE` (default: false) - Process events sequentially (Car → Loan → Payment → Service)
  - `DB_TYPE` - Database type for Lambda APIs: `pg` (PostgreSQL) or `dsql`
  - `API_URL` - Full API endpoint URL (for Lambda APIs)
  - `HOST` / `PORT` - API host and port (for regular REST APIs)
  - `EVENTS_FILE` - File path to save sent events for validation (default: `/tmp/k6-sent-events.json`)

### Running Lambda Tests

**Local Execution (SAM Local):**

```bash
cd load-test/shared

# Start local Lambda functions
./start-local-lambdas.sh

# Run tests
./run-lambda-tests.sh smoke local
./run-lambda-tests.sh full local
./run-lambda-tests.sh saturation local

# Stop local Lambda functions
./stop-local-lambdas.sh
```

**Cloud Execution (AWS):**

```bash
cd load-test/shared

# Deploy Lambda functions to AWS
./deploy-all-lambdas.sh

# Run tests
./run-lambda-tests.sh smoke cloud
./run-lambda-tests.sh full cloud
./run-lambda-tests.sh saturation cloud
```

### Preferred Script for Lambda API Testing with Validation

**`run-k6-and-validate.sh`** is the **preferred script** for running and validating Lambda APIs. This script:
- Runs k6 batch tests against Lambda APIs
- Automatically validates database results against sent events
- Supports both PostgreSQL (`pg`) and DSQL (`dsql`) Lambda APIs
- Pre-warms Lambda functions before testing
- Clears databases before test execution
- Provides comprehensive timing and throughput metrics

**Usage:**

```bash
# Test PostgreSQL Lambda API (preferred for two lambda APIs)
./scripts/run-k6-and-validate.sh pg [EVENTS_PER_TYPE] [VUS] [API_URL]

# Test DSQL Lambda API
./scripts/run-k6-and-validate.sh dsql [EVENTS_PER_TYPE] [VUS] [API_URL]

# Examples:
# Default: 10 events per type, 1 VU
./scripts/run-k6-and-validate.sh pg

# Custom: 100 events per type, 5 VUs
./scripts/run-k6-and-validate.sh pg 100 5

# Custom API URL
./scripts/run-k6-and-validate.sh pg 50 3 https://custom-api.execute-api.us-east-1.amazonaws.com
```

**Features:**
- Automatically extracts events from k6 output
- Validates data in target database (Aurora PostgreSQL for `pg`, DSQL for `dsql`)
- Provides detailed timing breakdown (k6 test, extraction, validation)
- Calculates throughput metrics (events per second)
- Saves sent events to a JSON file for re-validation

**Environment Variables:**
- `CLEAR_DATABASE` (default: `true`) - Clear database before test
- `PRE_WARM_LAMBDAS` (default: `true`) - Pre-warm Lambda functions before test

### Lambda Test Configuration

Lambda tests support different memory configurations and execution modes. See `lambda-config.json` for available settings and `system-test-config.json` for test execution configuration.

For more information, see:
- [Lambda REST API README](../producer-api-go-rest-lambda/README.md)
- [Lambda gRPC API README](../producer-api-go-grpc-lambda/README.md)
- [Terraform README](../terraform/README.md)

## K6 Shared Utilities

The `k6/shared/` subdirectory contains shared JavaScript utilities for k6 load testing scripts.

### `k6/shared/event-generators.js`

Reusable event generation functions for creating test events.

**Functions:**
- `generateUUID()`: Generate random UUID v4 (uses `Math.random()` for generation)
- `generateTimestamp()`: Generate ISO 8601 timestamp
- `generateCarCreatedEvent(carId)`: Generate Car Created event
- `generateLoanCreatedEvent(carId, loanId)`: Generate Loan Created event
- `generateLoanPaymentEvent(loanId, amount)`: Generate Loan Payment Submitted event
- `generateCarServiceDoneEvent(carId, serviceId)`: Generate Car Service Done event
- `generateLinkedEventSet()`: Generate a complete linked event set

**UUID Generation Methods:**

The codebase uses two different UUID generation approaches:

1. **Random UUID v4** (used in `event-generators.js` and `helpers.js`):
   - Uses `Math.random()` to generate random UUIDs
   - Suitable for general event generation where uniqueness is handled by the database
   - Each call produces a different UUID

2. **Deterministic UUID** (used in `send-batch-events.js`):
   - Generates deterministic UUIDs based on VU ID, iteration, event type index, and event index
   - Ensures uniqueness across parallel VUs and iterations without collisions
   - Useful for batch testing where deterministic UUIDs make validation and debugging easier
   - Format: UUID v4 compliant, but generated deterministically from test parameters

**Usage:**
```javascript
import { 
    generateCarCreatedEvent,
    generateLoanCreatedEvent 
} from './shared/event-generators.js';

export default function() {
    const carEvent = generateCarCreatedEvent();
    const loanEvent = generateLoanCreatedEvent('CAR-123');
    // ... send events
}
```

For detailed usage information, see the [Shared Scripts Documentation](../scripts/README.md#shared-scripts).

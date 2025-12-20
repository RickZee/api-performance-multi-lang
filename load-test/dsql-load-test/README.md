# DSQL Load Test Suite

A standalone load testing project for measuring DSQL (Aurora Data API) insert performance using parallel Lambda invocations.

## Overview

This project implements two test scenarios to maximize inserts into the `business_events` table in DSQL:

1. **Scenario 1: Individual Inserts** - 1000 parallel Lambda invocations, each looping N times and performing M individual INSERT statements per iteration
2. **Scenario 2: Batch Inserts** - 1000 parallel Lambda invocations, each looping N times and performing 1 batch INSERT statement with 100 rows per iteration

Both scenarios use configurable loop iterations to simulate fast continuous loads.

## Project Structure

```
load-test/dsql-load-test/
├── lambda/                          # Standalone Lambda function
│   ├── lambda_function.py          # Main Lambda handler
│   ├── repository.py                # Batch insert repository
│   ├── connection.py                # DSQL connection logic
│   ├── config.py                    # Configuration management
│   ├── iam_auth.py                  # IAM authentication
│   ├── event_generators.py          # Event data generation
│   ├── requirements.txt             # Python dependencies
│   └── sam-template.yaml            # SAM deployment template
├── test-dsql-parallel-inserts.py    # Test script
├── config.json                      # Configuration file
└── README.md                        # This file
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Python 3.11+
- AWS SAM CLI (for deployment)
- Access to Aurora DSQL cluster
- IAM permissions for Lambda execution and DSQL connection

## Configuration

Edit `config.json` to configure test parameters:

```json
{
  "lambda_function_name": "dsql-load-test-lambda",
  "region": "us-east-1",
  "scenario_1": {
    "num_lambdas": 1000,
    "iterations": 10,
    "inserts_per_iteration": 1
  },
  "scenario_2": {
    "num_lambdas": 1000,
    "iterations": 10,
    "rows_per_batch": 100
  },
  "warm_up_invocations": 20,
  "event_type": "CarCreated"
}
```

### Configurable Parameters

- **num_lambdas**: Number of parallel Lambda invocations (default: 1000)
- **iterations**: Number of loop iterations per Lambda (default: 10)
- **inserts_per_iteration**: For Scenario 1, number of individual inserts per iteration (default: 1)
- **rows_per_batch**: For Scenario 2, number of rows per batch (default: 100)
- **event_type**: Event type to generate - "CarCreated", "LoanCreated", "LoanPaymentSubmitted", "CarServiceDone" (default: "CarCreated")
- **warm_up_invocations**: Number of warm-up invocations to avoid cold starts (default: 20)

## Deployment

### 1. Deploy Lambda Function

```bash
cd lambda
sam build
sam deploy --guided
```

During guided deployment, provide:
- Stack name: `dsql-load-test-stack`
- AWS Region: Your region (e.g., `us-east-1`)
- Aurora DSQL endpoint: Your DSQL cluster endpoint
- Database name: Your database name
- IAM username: Your IAM database user
- DSQL cluster resource ID: Your cluster resource ID (format: `cluster-xxxxx`)
- VPC ID: Your VPC ID (if Lambda needs VPC access)
- Subnet IDs: Comma-separated subnet IDs

### 2. Update Configuration

After deployment, update `config.json` with the deployed Lambda function name:

```json
{
  "lambda_function_name": "dsql-load-test-lambda"
}
```

## Usage

### Run Both Scenarios

```bash
python test-dsql-parallel-inserts.py
```

### Run Specific Scenario

```bash
# Scenario 1 only (Individual inserts)
python test-dsql-parallel-inserts.py --scenario 1

# Scenario 2 only (Batch inserts)
python test-dsql-parallel-inserts.py --scenario 2
```

### Override Configuration

```bash
# Custom number of Lambdas and iterations
python test-dsql-parallel-inserts.py \
  --num-lambdas 500 \
  --iterations 20 \
  --count 1 \
  --event-type CarCreated

# Skip warm-up
python test-dsql-parallel-inserts.py --no-warm-up
```

### Command Line Options

- `--function-name`: Lambda function name (overrides config)
- `--region`: AWS region (default: us-east-1)
- `--scenario`: Scenario to run - "1", "2", or "both" (default: both)
- `--num-lambdas`: Number of parallel Lambdas (overrides config)
- `--iterations`: Number of loop iterations per Lambda (overrides config)
- `--count`: Inserts per iteration (scenario 1) or rows per batch (scenario 2)
- `--event-type`: Event type to generate
- `--warm-up`: Number of warm-up invocations (default: 20)
- `--no-warm-up`: Skip warm-up phase
- `--config`: Path to config file (default: config.json)

## Test Scenarios

### Scenario 1: Individual Inserts

- **Pattern**: One INSERT statement per row, executed in a loop
- **Execution**: 1000 parallel Lambda invocations
- **Each Lambda**: Loops 10 times, each iteration performs 1 individual INSERT
- **Total per Lambda**: 10 individual INSERT statements
- **Total across all Lambdas**: 10,000 individual INSERT statements
- **Goal**: Test DSQL performance with high concurrency of fast continuous individual operations

### Scenario 2: Batch Inserts

- **Pattern**: One INSERT statement with 100 rows (multi-value INSERT), executed in a loop
- **Execution**: 1000 parallel Lambda invocations
- **Each Lambda**: Loops 10 times, each iteration performs 1 batch INSERT (100 rows)
- **Total per Lambda**: 10 batch INSERT statements (1,000 rows)
- **Total across all Lambdas**: 1,000,000 rows inserted
- **Goal**: Test DSQL performance with fast continuous batch operations at maximum parallelism

## Metrics Collected

The test script collects and reports:

- **Total inserts attempted**: Sum of all inserts across all lambdas
- **Total inserts successful**: Count of successful inserts
- **Total duration**: Time from first invocation to last completion
- **Throughput**: Inserts per second
- **Invocation latency**: Min, max, avg, median, P95, P99 per Lambda invocation
- **Lambda execution duration**: Min, max, avg, median, P95, P99 per Lambda execution
- **Lambda throughput**: Min, max, avg, median inserts per second per Lambda
- **Success rate**: Percentage of successful Lambda invocations
- **Error tracking**: List of failed invocations with error messages

## Results

Results are saved to a JSON file with timestamp: `results_YYYYMMDD_HHMMSS.json`

The file contains detailed metrics for each scenario, including:
- Aggregated statistics
- Latency distributions
- Throughput metrics
- Error details

## Event Types

Supported event types (matching k6 test generators):

- **CarCreated**: Car creation events with random VIN, make, model, year, color, mileage
- **LoanCreated**: Loan creation events with random loan amount, interest rate, term
- **LoanPaymentSubmitted**: Loan payment events with random payment amounts
- **CarServiceDone**: Car service events with random service details

## Environment Variables

The Lambda function uses the following environment variables (set via SAM template):

- `AURORA_DSQL_ENDPOINT`: Aurora DSQL cluster endpoint
- `AURORA_DSQL_PORT`: Database port (default: 5432)
- `DATABASE_NAME`: Database name
- `IAM_USERNAME`: IAM database username
- `AWS_REGION`: AWS region
- `DSQL_HOST`: DSQL host (format: `<cluster-id>.<service-suffix>.<region>.on.aws`)
- `LOG_LEVEL`: Logging level (debug, info, warn, error)

## Troubleshooting

### Lambda Timeout

If Lambdas timeout, increase the timeout in `sam-template.yaml`:

```yaml
Timeout: 900  # 15 minutes
```

### Connection Errors

Ensure:
- Lambda has VPC access if DSQL is in a VPC
- Security groups allow outbound traffic on port 5432
- IAM permissions include `rds-db:connect` for the DSQL cluster

### Cold Starts

The test includes a warm-up phase by default. Increase `warm_up_invocations` in config if needed.

### Concurrency Limits

AWS Lambda default concurrency is 1000 per region. For higher parallelism, request a limit increase via AWS Support.

## Cost Estimation

Approximate costs (us-east-1, as of 2024):

- **Lambda invocations**: $0.20 per 1M requests
- **Lambda compute**: $0.0000166667 per GB-second
- **Data transfer**: $0.09 per GB out

For 1000 Lambdas × 10 iterations:
- ~1000 invocations (if each Lambda handles all iterations internally)
- Estimated cost: < $1 for a full test run

## Notes

- This is a standalone project, separate from the producer API
- All event IDs are generated with unique timestamps to avoid conflicts
- Batch inserts use `ON CONFLICT DO NOTHING` for idempotency
- The Lambda function connects directly to DSQL (no dependency on producer API)
